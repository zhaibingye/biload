# Workspace-local NTFS junctions allow plugin builds without changing Windows Developer Mode.
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$metadataPath = Join-Path $projectRoot '.flutter-plugins-dependencies'
if (-not (Test-Path -LiteralPath $metadataPath)) { throw 'Run flutter pub get first.' }
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
foreach ($platformName in @('windows','linux','macos')) {
    $platformRoot = if ($platformName -eq 'macos') { 'macos/Flutter/ephemeral/.symlinks/plugins' } else { "$platformName/flutter/ephemeral/.plugin_symlinks" }
    $linkRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot $platformRoot))
    if (-not $linkRoot.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Workspace path verification failed.' }
    New-Item -ItemType Directory -Path $linkRoot -Force | Out-Null
    foreach ($plugin in $metadata.plugins.$platformName) {
        if ($plugin.name -notmatch '^[a-zA-Z0-9_]+$') { throw 'Invalid plugin name.' }
        $linkPath = Join-Path $linkRoot $plugin.name
        if (-not (Test-Path -LiteralPath $linkPath)) {
            New-Item -ItemType Junction -Path $linkPath -Target $plugin.path | Out-Null
        }
    }
}
Write-Output 'Workspace plugin links are ready. Re-run flutter pub get if its previous attempt failed.'
