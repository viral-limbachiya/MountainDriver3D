$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot
$godot = "C:\Users\Viral L\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
$keystore = "$project\signing_backup\mountain-driver-release.keystore"
$outputApk = Join-Path $project "builds\android\VRL-Mountain-Driver-3D-release.apk"
$outputAab = Join-Path $project "builds\android\VRL-Mountain-Driver-3D-release.aab"
$alias = "mountaindriver"
$androidTemplate = Join-Path $project "android\build"

if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot was not found at: $godot"
}

# Fallback to home Documents directory if backup keystore is missing
if (-not (Test-Path -LiteralPath $keystore)) {
    $keystore = "$HOME\Documents\MountainDriver-Signing\mountain-driver-release.keystore"
}

if (-not (Test-Path -LiteralPath $keystore)) {
    throw "Release keystore was not found at: $keystore"
}

New-Item -ItemType Directory -Path (Split-Path -Parent $outputApk) -Force | Out-Null

$securePassword = Read-Host "Enter the VRL PRO release-key password" -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

    # Copy keystore to a space-free path to avoid Gradle path-parsing bugs
    $tempKeystore = "C:\Users\Public\temp-mountain-driver-release.keystore"
    Copy-Item -LiteralPath $keystore -Destination $tempKeystore -Force

    # Set Java and Keystore environment variables for Godot build pipeline
    $env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $tempKeystore
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $alias
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $plainPassword

    # 1. Export Signed Release APK
    Write-Host "Exporting signed release APK to $outputApk..."
    & $godot --headless --path $project --export-release "Android Test" $outputApk

    if ($LASTEXITCODE -ne 0) {
        throw "Godot APK export failed with exit code $LASTEXITCODE."
    }

    # 2. Export Signed Release AAB
    Write-Host "Exporting signed release AAB to $outputAab..."
    & $godot --headless --path $project --export-release "Android Play Store" $outputAab

    if ($LASTEXITCODE -ne 0) {
        throw "Godot AAB export failed with exit code $LASTEXITCODE."
    }

    Write-Host "`nSuccess! Signed Release builds generated:"
    Get-Item -LiteralPath $outputApk, $outputAab |
        Select-Object Name, Length, LastWriteTime
}
finally {
    # Clean up sensitive env variables and temp files
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $null
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $null
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $null
    $plainPassword = $null
    $securePassword = $null

    Remove-Item -LiteralPath "C:\Users\Public\temp-mountain-driver-release.keystore" -ErrorAction SilentlyContinue

    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
}
