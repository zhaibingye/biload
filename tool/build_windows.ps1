param(
    [ValidateSet('debug','profile','release')][string]$Mode = 'release',
    [string]$FlutterRoot = "$env:USERPROFILE/develop/flutter",
    [string]$AliasPath = "$env:USERPROFILE/develop/biload-build",
    [string]$Target = 'lib/main.dart'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$buildRoot = $projectRoot
if ($projectRoot -match '[^\x00-\x7F]') {
    $AliasPath = [IO.Path]::GetFullPath($AliasPath)
    if ($AliasPath -match '[^\x00-\x7F]') { throw 'Specify an ASCII -AliasPath for the Windows native build.' }
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
        & $flutterPath pub get
        if ($LASTEXITCODE -ne 0) { throw 'Native plugin setup failed.' }
    }
    & (Join-Path $PSScriptRoot 'link_plugins.ps1')
    & $flutterPath build windows "--$Mode" --target $Target
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    $configuration = (Get-Culture).TextInfo.ToTitleCase($Mode)
    Write-Output "Bundle: $(Join-Path $projectRoot "build/windows/x64/runner/$configuration")"
} finally { Pop-Location }
