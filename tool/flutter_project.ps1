# Shared setup for native builds on Windows, including projects in Unicode paths.
function Invoke-InFlutterProject {
    param(
        [string]$FlutterRoot,
        [string]$AliasPath,
        [scriptblock]$Build
    )
    $ErrorActionPreference = 'Stop'
    $projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
    $buildRoot = $projectRoot
    if ($projectRoot -match '[^\x00-\x7F]') {
        $AliasPath = [IO.Path]::GetFullPath($AliasPath)
        if ($AliasPath -match '[^\x00-\x7F]') { throw 'Specify an ASCII -AliasPath for the native build.' }
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
        $pubFailed = $LASTEXITCODE -ne 0
        if ($pubFailed -and ($pubOutput -join "`n") -notmatch 'requires symlink support') {
            throw 'Dependency resolution failed.'
        }
        # Dependency changes can clear desktop links even when pub get reports
        # success. Prepare junctions once before the native build.
        & (Join-Path $PSScriptRoot 'link_plugins.ps1')
        if ($pubFailed) {
            # A failed pub get stops before native plugin registration finishes.
            & $flutterPath pub get
            if ($LASTEXITCODE -ne 0) { throw 'Native plugin setup failed.' }
        }
        & $Build $flutterPath $projectRoot
    } finally { Pop-Location }
}
