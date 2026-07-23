[CmdletBinding()]
param(
    [string]$KeyAlias = "fantextviewer-local",
    [int]$ValidityDays = 3650
)

$ErrorActionPreference = "Stop"

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$androidRoot = Join-Path $projectRoot "android"
$keystorePath = Join-Path $androidRoot "app\fantextviewer-local.jks"
$propertiesPath = Join-Path $androidRoot "key.properties"

if (Test-Path -LiteralPath $keystorePath) {
    throw "A local keystore already exists: $keystorePath"
}
if (Test-Path -LiteralPath $propertiesPath) {
    throw "Signing properties already exist: $propertiesPath"
}

$keytoolCommand = Get-Command "keytool" -ErrorAction SilentlyContinue
$keytoolPath = if ($null -eq $keytoolCommand) { $null } else { $keytoolCommand.Source }
if ($null -eq $keytoolPath -and -not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    $javaKeytool = Join-Path $env:JAVA_HOME "bin\keytool.exe"
    if (Test-Path -LiteralPath $javaKeytool) {
        $keytoolPath = $javaKeytool
    }
}
if ($null -eq $keytoolPath) {
    throw "keytool was not found. Install a JDK or set JAVA_HOME."
}

$passwordBytes = New-Object byte[] 24
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $random.GetBytes($passwordBytes)
} finally {
    $random.Dispose()
}
$password = [Convert]::ToBase64String($passwordBytes)
$env:FANTEXTVIEWER_KEYSTORE_PASSWORD = $password

try {
    & $keytoolPath `
        -genkeypair `
        -keystore $keystorePath `
        -storetype PKCS12 `
        -alias $KeyAlias `
        -keyalg RSA `
        -keysize 3072 `
        -validity $ValidityDays `
        -dname "CN=FanTextViewer Local, OU=Personal Sideload, O=Local, C=KR" `
        -storepass:env FANTEXTVIEWER_KEYSTORE_PASSWORD `
        -keypass:env FANTEXTVIEWER_KEYSTORE_PASSWORD
    if ($LASTEXITCODE -ne 0) {
        throw "keytool failed with exit code $LASTEXITCODE."
    }

    $properties = @(
        "storeFile=app/fantextviewer-local.jks"
        "storePassword=$password"
        "keyAlias=$KeyAlias"
        "keyPassword=$password"
    )
    [IO.File]::WriteAllLines(
        $propertiesPath,
        $properties,
        [Text.UTF8Encoding]::new($false)
    )
} catch {
    if (Test-Path -LiteralPath $keystorePath) {
        Remove-Item -LiteralPath $keystorePath -Force
    }
    throw
} finally {
    Remove-Item Env:FANTEXTVIEWER_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
}

Write-Host "Created the local release key and signing properties."
Write-Host "Keystore: $keystorePath"
Write-Host "Properties: $propertiesPath"
Write-Host "Both files are ignored by Git. Deleting them breaks update signing continuity."
