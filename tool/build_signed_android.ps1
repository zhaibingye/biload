param(
    [string]$FlutterRoot = "$env:USERPROFILE/develop/flutter",
    [string]$JavaRoot = 'C:/Program Files/Java/jdk-17.0.19'
)
$ErrorActionPreference = 'Stop'
$signingDirectory = Join-Path $env:USERPROFILE '.biload/signing'
$configPath = Join-Path $signingDirectory 'release.json'
$keytool = Join-Path $JavaRoot 'bin/keytool.exe'
$expectedCertificate = '10918b393dca1b5b284b21f8b9a3ee24005cd779dbe0256a7f2de58bd099c27e'
if (-not (Test-Path -LiteralPath $configPath)) {
    $legacyKey = Join-Path $env:USERPROFILE '.android/debug.keystore'
    if (-not (Test-Path -LiteralPath $legacyKey)) {
        throw 'The existing biload compatibility key is required for the first signing setup.'
    }
    New-Item -ItemType Directory -Path $signingDirectory -Force | Out-Null
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls $signingDirectory /inheritance:r /grant:r "*${sid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot restrict access to the signing directory.' }
    $certificatePath = Join-Path $signingDirectory 'certificate.der'
    $keyPath = Join-Path $signingDirectory 'biload-release.p12'
    $env:BILOAD_LEGACY_PASSWORD = 'android'
    $env:BILOAD_NEW_PASSWORD = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
    try {
        & $keytool -exportcert -keystore $legacyKey -alias androiddebugkey -storepass:env BILOAD_LEGACY_PASSWORD -file $certificatePath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Cannot check the compatibility certificate.' }
        $fingerprint = (Get-FileHash -LiteralPath $certificatePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($fingerprint -ne $expectedCertificate) { throw 'Compatibility signing certificate does not match existing biload releases.' }
        if (Test-Path -LiteralPath $keyPath) { throw 'A signing key already exists without configuration. Inspect it before continuing.' }
        & $keytool -importkeystore -noprompt -srckeystore $legacyKey -srcalias androiddebugkey -srcstorepass:env BILOAD_LEGACY_PASSWORD -srckeypass:env BILOAD_LEGACY_PASSWORD -destkeystore $keyPath -deststoretype PKCS12 -destalias biload -deststorepass:env BILOAD_NEW_PASSWORD -destkeypass:env BILOAD_NEW_PASSWORD 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Cannot migrate the persistent signing key.' }
        $protectedPassword = ConvertFrom-SecureString (ConvertTo-SecureString $env:BILOAD_NEW_PASSWORD -AsPlainText -Force)
        @{ path = $keyPath; alias = 'biload'; password = $protectedPassword; certificate = $fingerprint } | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
    } finally {
        Remove-Item Env:BILOAD_LEGACY_PASSWORD,Env:BILOAD_NEW_PASSWORD -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $certificatePath) { Remove-Item -LiteralPath $certificatePath }
    }
}
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($config.certificate -ne $expectedCertificate) { throw 'Unexpected signing certificate.' }
try {
    $secret = ConvertTo-SecureString $config.password
    $credential = [PSCredential]::new('biload', $secret)
    $env:BILOAD_KEYSTORE_PATH = $config.path
    $env:BILOAD_STORE_PASSWORD = $credential.GetNetworkCredential().Password
    $env:BILOAD_KEY_PASSWORD = $env:BILOAD_STORE_PASSWORD
    $env:BILOAD_KEY_ALIAS = $config.alias
    & (Join-Path $PSScriptRoot 'build_android.ps1') -FlutterRoot $FlutterRoot -Mode release
} finally {
    Remove-Item Env:BILOAD_KEYSTORE_PATH,Env:BILOAD_STORE_PASSWORD,Env:BILOAD_KEY_PASSWORD,Env:BILOAD_KEY_ALIAS -ErrorAction SilentlyContinue
    $credential = $null
    $secret = $null
}
