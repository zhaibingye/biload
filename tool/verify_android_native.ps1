param(
    [Parameter(Mandatory=$true)][string]$DeviceId,
    [switch]$Network,
    [ValidatePattern('^BV[0-9A-Za-z]{10}$')][string]$NetworkBvid,
    [string]$FlutterRoot = "$env:USERPROFILE/develop/flutter",
    [string]$AndroidSdkRoot = "$env:USERPROFILE/develop/android-sdk",
    [string]$AliasPath = "$env:USERPROFILE/develop/biload-build"
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
[string[]]$defines = if ($Network) { @('BILOAD_NETWORK_SMOKE=true') } else { @() }
if ($NetworkBvid) {
    if (-not $Network) { throw 'NetworkBvid requires -Network.' }
    $defines += "BILOAD_TEST_BVID=$NetworkBvid"
}
# Build first: Flutter's test runner can cache the package ID from an old APK
# or fall back to the production namespace before it builds the new test APK.
& (Join-Path $PSScriptRoot 'build_android.ps1') -Mode debug -NoSplit `
    -Target integration_test/native_smoke_test.dart -DartDefine $defines `
    -FlutterRoot $FlutterRoot -AliasPath $AliasPath
$buildRoot = if ($projectRoot -match '[^\x00-\x7F]') { $AliasPath } else { $projectRoot }
$adb = Join-Path $AndroidSdkRoot 'platform-tools/adb.exe'
$aapt = Join-Path $AndroidSdkRoot 'build-tools/36.0.0/aapt.exe'
$flutter = Join-Path $FlutterRoot 'bin/flutter.bat'
Push-Location -LiteralPath $buildRoot
try {
    $apk = 'build/app/outputs/flutter-apk/app-debug.apk'
    $badging = & $aapt dump badging $apk
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify the test APK package.' }
    $packageLine = $badging | Where-Object { $_ -match "^package: name='([^']+)'" } | Select-Object -First 1
    if ($packageLine -notmatch "^package: name='app\.biload\.biload\.dev'") {
        throw 'Refusing device verification: the APK is not the isolated development package.'
    }
    # Never let Flutter's install-retry path uninstall a newer development app.
    $installOutput = & $adb -s $DeviceId install -r $apk 2>&1
    $installCode = $LASTEXITCODE
    $installOutput | Write-Output
    if ($installCode -ne 0 -or ($installOutput -join "`n") -match '(?m)^Failure\b') {
        throw 'Test app installation failed. Existing application data was not cleared.'
    }
    & $adb -s $DeviceId shell pm grant app.biload.biload.dev android.permission.POST_NOTIFICATIONS
    if ($LASTEXITCODE -ne 0) { throw 'Could not prepare test app notification permission.' }
    $testArguments = @('test', 'integration_test/native_smoke_test.dart', '-d', $DeviceId,
        '--no-uninstall', '--reporter', 'expanded')
    foreach ($define in $defines) { $testArguments += "--dart-define=$define" }
    & $flutter @testArguments 2>&1 | Tee-Object -Variable testOutput
    if ($LASTEXITCODE -ne 0) { throw 'Native device verification failed.' }
    $reportMatch = [regex]::Match(($testOutput -join "`n"),
        'BILOAD_NATIVE_REPORT=(/storage/emulated/\d+/Android/data/app\.biload\.biload\.dev/files/biload-verification-\d+)/report\.json')
    if (-not $reportMatch.Success) { throw 'Tests passed but no native report path was received.' }
    & (Join-Path $PSScriptRoot 'collect_android_verification.ps1') -DeviceId $DeviceId `
        -ReportDirectory $reportMatch.Groups[1].Value -AndroidSdkRoot $AndroidSdkRoot
} finally { Pop-Location }
