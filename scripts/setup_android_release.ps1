# Creates Play Store upload keystore + android/key.properties (gitignored), then builds app bundle.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$android = Join-Path $root "android"
$jks = Join-Path $android "app" "upload-keystore.jks"
$keyProps = Join-Path $android "key.properties"
$credsFile = Join-Path $android ".keystore-credentials.local"

function New-RandomPassword {
    $chars = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    -join (1..20 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

if (-not (Test-Path $jks)) {
    if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
        Write-Error "keytool not found. Install JDK (Android Studio includes it) and ensure keytool is on PATH."
    }
    $storePass = if ($env:KEYSTORE_PASSWORD) { $env:KEYSTORE_PASSWORD } else { New-RandomPassword }
    $keyPass = if ($env:KEY_PASSWORD) { $env:KEY_PASSWORD } else { $storePass }
    $dname = "CN=HRMS Mobile, OU=Engineering, O=Siyana Info, L=India, C=IN"
    Write-Host "Creating upload keystore at $jks ..."
    & keytool -genkeypair -v `
        -keystore $jks `
        -storetype JKS `
        -storepass $storePass `
        -keypass $keyPass `
        -alias upload `
        -keyalg RSA `
        -keysize 2048 `
        -validity 10000 `
        -dname $dname
    if ($LASTEXITCODE -ne 0) { throw "keytool failed" }

    @"
storePassword=$storePass
keyPassword=$keyPass
keyAlias=upload
storeFile=app/upload-keystore.jks
"@ | Set-Content -Path $keyProps -Encoding UTF8

    @"
BACK UP THESE VALUES — you need them for every Play Store update.
Keystore file: $jks
Alias: upload
Store password: $storePass
Key password: $keyPass

Add the release SHA-1 to Google Cloud (Android OAuth client):
  cd android && ./gradlew signingReport
"@ | Set-Content -Path $credsFile -Encoding UTF8

    Write-Host "Wrote $keyProps and $credsFile (gitignored). BACK UP the keystore file and passwords."
} else {
    Write-Host "Keystore already exists: $jks"
    if (-not (Test-Path $keyProps)) {
        Write-Error "key.properties missing. Copy android/key.properties.example and fill in passwords."
    }
}

Push-Location $root
try {
    Write-Host "Building release app bundle..."
    flutter pub get
    flutter build appbundle --release
    $aab = Join-Path $root "build" "app" "outputs" "bundle" "release" "app-release.aab"
    if (Test-Path $aab) {
        Write-Host ""
        Write-Host "SUCCESS: $aab"
        Write-Host "Upload this file in Play Console -> Release -> Production (or Testing)."
    }
} finally {
    Pop-Location
}
