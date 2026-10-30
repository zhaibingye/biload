param(
    [ValidateSet('debug','profile','release')][string]$Mode = 'release',
    [string]$FlutterRoot = "$env:USERPROFILE/develop/flutter",
    [string]$AliasPath = "$env:USERPROFILE/develop/biload-build",
    [string]$Target = 'lib/main.dart'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'flutter_project.ps1')
Invoke-InFlutterProject -FlutterRoot $FlutterRoot -AliasPath $AliasPath -Build {
    param($flutterPath, $projectRoot)
    & $flutterPath build windows "--$Mode" --target $Target
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    $configuration = (Get-Culture).TextInfo.ToTitleCase($Mode)
    Write-Output "Bundle: $(Join-Path $projectRoot "build/windows/x64/runner/$configuration")"
}
