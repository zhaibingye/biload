param(
    [ValidateSet('debug','release')][string]$Mode = 'release',
    [string]$FlutterRoot = "$env:USERPROFILE/develop/flutter",
    [string]$AliasPath = "$env:USERPROFILE/develop/biload-build",
    [string]$Target = 'lib/main.dart',
    [string[]]$DartDefine = @(),
    [switch]$NoSplit
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$buildRoot = $projectRoot
if ($projectRoot -match '[^\x00-\x7F]') {
    # Windows gen_snapshot's command-line path handling requires an ASCII build root.
    $AliasPath = [IO.Path]::GetFullPath($AliasPath)
    if ($AliasPath -match '[^\x00-\x7F]') { throw 'Specify an ASCII -AliasPath for the Windows AOT compiler.' }
    if (Test-Path -LiteralPath $AliasPath) {
        $existing = Get-Item -LiteralPath $AliasPath
        if ($existing.LinkType -ne 'Junction' -or
            [IO.Path]::GetFullPath([string]$existing.Target) -ne $projectRoot) {
            throw 'AliasPath is already used by another folder. Choose a different -AliasPath.'
        }
    } else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $AliasPath) -Force | Out-Null
        New-Item -ItemType Junction -Path $AliasPath -Target $projectRoot | Out-Null
    }
    $buildRoot = $AliasPath
}
$flutterPath = Join-Path $FlutterRoot 'bin/flutter.bat'
Push-Location -LiteralPath $buildRoot
try {
    & $flutterPath pub get 2>&1 | Tee-Object -Variable pubOutput
    if ($LASTEXITCODE -ne 0) {
        if (($pubOutput -join "`n") -notmatch 'requires symlink support') {
            throw 'Dependency resolution failed.'
        }
        & (Join-Path $PSScriptRoot 'link_plugins.ps1')
        # The failed pub get stops before native plugin registrants are written.
        # Complete it after creating links; never build from partial setup.
        & $flutterPath pub get
        if ($LASTEXITCODE -ne 0) { throw 'Native plugin setup failed.' }
    }
    & (Join-Path $PSScriptRoot 'link_plugins.ps1')
    $dartPath = Join-Path $FlutterRoot 'bin/dart.bat'
    & $dartPath run tool/verify_android_plugins.dart "--$Mode"
    if ($LASTEXITCODE -ne 0) { throw 'Android plugin registration is incomplete.' }
    # Flutter must also regenerate the registrant for the selected build mode;
    # release builds omit native development-only plugins such as integration_test.
    $buildArguments = @('build', 'apk', "--$Mode", '--target-platform', 'android-arm64', '--target', $Target)
    if (-not $NoSplit) { $buildArguments += '--split-per-abi' }
    foreach ($define in $DartDefine) { $buildArguments += "--dart-define=$define" }
    & $flutterPath @buildArguments
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
    & $dartPath run tool/verify_android_plugins.dart "--$Mode"
    if ($LASTEXITCODE -ne 0) { throw 'Android plugin registration changed during build.' }
    $apkName = if ($NoSplit) { "app-$Mode.apk" } else { "app-arm64-v8a-$Mode.apk" }
    Write-Output "APK: $(Join-Path $projectRoot "build/app/outputs/flutter-apk/$apkName")"
} finally { Pop-Location }
