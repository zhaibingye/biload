param(
    [switch]$InstallBuildTools,
    [string]$InstallerPath = (Join-Path $env:TEMP 'biload-vs-BuildTools.exe')
)
$ErrorActionPreference = 'Stop'
if (-not $InstallBuildTools) {
    Write-Output 'Run in an Administrator PowerShell: .\tool\setup_windows.ps1 -InstallBuildTools'
    Write-Output 'Installs Microsoft C++ Build Tools, Windows SDK, CMake and ATL. Allow several GB of disk space.'
    exit 0
}
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator PowerShell is required to install Microsoft Build Tools.'
}
if (-not (Test-Path -LiteralPath $InstallerPath)) {
    Invoke-WebRequest 'https://aka.ms/vs/17/release/vs_BuildTools.exe' -OutFile $InstallerPath -TimeoutSec 120
}
$signature = Get-AuthenticodeSignature -LiteralPath $InstallerPath
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
    throw 'Microsoft installer signature verification failed.'
}
$process = Start-Process -FilePath $InstallerPath -WindowStyle Hidden -Wait -PassThru -ArgumentList @(
    '--quiet', '--wait', '--norestart', '--nocache',
    '--add', 'Microsoft.VisualStudio.Workload.VCTools', '--includeRecommended',
    '--add', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
    '--add', 'Microsoft.VisualStudio.Component.VC.CMake.Project',
    '--add', 'Microsoft.VisualStudio.Component.VC.ATL'
)
if ($process.ExitCode -notin @(0,3010)) { throw "Build Tools installer exited with code $($process.ExitCode)." }
Write-Output "Build Tools installation completed (exit code $($process.ExitCode))."
