param(
    [Parameter(Mandatory=$true)][string]$DeviceId,
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^/storage/emulated/\d+/Android/data/app\.biload\.biload\.dev/files/biload-verification-\d+$')]
    [string]$ReportDirectory,
    [string]$AndroidSdkRoot = "$env:USERPROFILE/develop/android-sdk"
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$destination = Join-Path $projectRoot "artifacts/native/$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')"
New-Item -ItemType Directory -Path $destination | Out-Null
$adb = Join-Path $AndroidSdkRoot 'platform-tools/adb.exe'
$reportFile = Join-Path $destination 'report.json'
& $adb -s $DeviceId pull "$ReportDirectory/report.json" $reportFile
if ($LASTEXITCODE -ne 0) { throw 'Could not retrieve the native verification report.' }
$report = Get-Content -Raw -LiteralPath $reportFile | ConvertFrom-Json
# Windows adb cannot reliably create Unicode directory trees. Keep original
# names on the phone, and collect each output under an ASCII case name.
foreach ($result in $report.results.PSObject.Properties) {
    $relative = $result.Value.output
    if (-not $relative) { continue }
    if ($result.Name -notmatch '^[A-Za-z0-9_]+$' -or
        $relative.StartsWith('/') -or $relative.Contains('\') -or
        ($relative.Split('/') -contains '..')) {
        throw 'Unexpected path in native verification report.'
    }
    $extension = [IO.Path]::GetExtension($relative)
    if ($extension -notin @('.mp4','.mkv','.m4a','.flac','.mka')) {
        throw 'Unexpected media extension in native verification report.'
    }
    $output = Join-Path $destination ($result.Name + $extension)
    & $adb -s $DeviceId pull "$ReportDirectory/$relative" $output
    if ($LASTEXITCODE -ne 0) { throw "Could not collect $($result.Name)." }
    if ((Get-Item -LiteralPath $output).Length -ne $result.Value.bytes) {
        throw "Collected file length differs from native result: $($result.Name)."
    }
}
Write-Output "Native evidence: $destination"
