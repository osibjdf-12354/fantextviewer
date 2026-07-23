[CmdletBinding()]
param(
    [string]$KeyAlias = "geulbom-local",
    [int]$ValidityDays = 3650
)

$ErrorActionPreference = "Stop"

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$androidRoot = Join-Path $projectRoot "android"
$keystorePath = Join-Path $androidRoot "app\geulbom-local.jks"
$propertiesPath = Join-Path $androidRoot "key.properties"

if (Test-Path -LiteralPath $keystorePath) {
    throw "이미 로컬 키스토어가 있습니다: $keystorePath"
}
if (Test-Path -LiteralPath $propertiesPath) {
    throw "이미 서명 설정이 있습니다: $propertiesPath"
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
    throw "keytool을 찾지 못했습니다. JDK를 설치하거나 JAVA_HOME을 설정하세요."
}

$passwordBytes = New-Object byte[] 24
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $random.GetBytes($passwordBytes)
} finally {
    $random.Dispose()
}
$password = [Convert]::ToBase64String($passwordBytes)
$env:GEULBOM_KEYSTORE_PASSWORD = $password

try {
    & $keytoolPath `
        -genkeypair `
        -keystore $keystorePath `
        -storetype PKCS12 `
        -alias $KeyAlias `
        -keyalg RSA `
        -keysize 3072 `
        -validity $ValidityDays `
        -dname "CN=Geulbom Local, OU=Personal Sideload, O=Local, C=KR" `
        -storepass:env GEULBOM_KEYSTORE_PASSWORD `
        -keypass:env GEULBOM_KEYSTORE_PASSWORD
    if ($LASTEXITCODE -ne 0) {
        throw "keytool이 종료 코드 $LASTEXITCODE 로 실패했습니다."
    }

    $properties = @(
        "storeFile=app/geulbom-local.jks"
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
    Remove-Item Env:GEULBOM_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
}

Write-Host "로컬 릴리스 키와 서명 설정을 만들었습니다."
Write-Host "키스토어: $keystorePath"
Write-Host "설정: $propertiesPath"
Write-Host "두 파일은 .gitignore에 포함되며 삭제하면 같은 앱의 업데이트 서명을 유지할 수 없습니다."
