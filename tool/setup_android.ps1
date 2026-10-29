param([string]$SdkRoot = "$env:USERPROFILE/develop/android-sdk")
$ErrorActionPreference = 'Stop'
$SdkRoot = [IO.Path]::GetFullPath($SdkRoot)
$toolsDir = Join-Path $SdkRoot 'cmdline-tools/latest'
if (-not (Test-Path -LiteralPath (Join-Path $toolsDir 'bin/sdkmanager.bat'))) {
    New-Item -ItemType Directory -Path $SdkRoot -Force | Out-Null
    $archivePath = Join-Path $SdkRoot 'commandlinetools-win-15859902_latest.zip'
    if (-not (Test-Path -LiteralPath $archivePath)) {
        Invoke-WebRequest 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip' -OutFile $archivePath
    }
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a') {
        throw 'Android command-line tools checksum mismatch.'
    }
    $stagingDir = Join-Path $SdkRoot 'bootstrap'
    Expand-Archive -LiteralPath $archivePath -DestinationPath $stagingDir -Force
    $sourceDir = [IO.Path]::GetFullPath((Join-Path $stagingDir 'cmdline-tools'))
    $destinationDir = [IO.Path]::GetFullPath($toolsDir)
    foreach ($candidate in @($sourceDir, $destinationDir)) {
        if (-not $candidate.StartsWith($SdkRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'SDK path verification failed.'
        }
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationDir) -Force | Out-Null
    Move-Item -LiteralPath $sourceDir -Destination $destinationDir
}
$env:ANDROID_HOME = $SdkRoot
$sdkmanagerPath = Join-Path $toolsDir 'bin/sdkmanager.bat'
1..20 | ForEach-Object { 'y' } | & $sdkmanagerPath "--sdk_root=$SdkRoot" 'platform-tools' 'platforms;android-36' 'platforms;android-35' 'build-tools;36.0.0' 'ndk;28.2.13676358' 'cmake;3.22.1'
if ($LASTEXITCODE -ne 0) { throw 'Android SDK component installation failed.' }
$flutterPath = Join-Path $env:USERPROFILE 'develop/flutter/bin/flutter.bat'
& $flutterPath config --android-sdk $SdkRoot
if ($LASTEXITCODE -ne 0) { throw 'Flutter Android SDK configuration failed.' }
