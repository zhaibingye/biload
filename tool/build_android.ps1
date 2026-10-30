param(
    [ValidateSet('debug','release')][string]$Mode = 'release',
    [string]$FlutterRoot = "$env:USERPROFILE/develop/flutter",
    [string]$AliasPath = "$env:USERPROFILE/develop/biload-build",
    [string]$Target = 'lib/main.dart',
    [string[]]$DartDefine = @(),
    [switch]$NoSplit
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'flutter_project.ps1')
Invoke-InFlutterProject -FlutterRoot $FlutterRoot -AliasPath $AliasPath -Build {
    param($flutterPath, $projectRoot)
    $dartPath = Join-Path $FlutterRoot 'bin/dart.bat'
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
}
