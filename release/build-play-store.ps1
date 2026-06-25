$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot
$godot = "C:\Users\Viral L\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
$keystore = "$HOME\Documents\MountainDriver-Signing\mountain-driver-release.keystore"
$output = Join-Path $project "builds\android\VRL-Mountain-Driver-3D-release.aab"
$alias = "mountaindriver"
$androidTemplate = Join-Path $project "android\build"

if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot was not found at: $godot"
}

if (-not (Test-Path -LiteralPath $keystore)) {
    throw "Release keystore was not found at: $keystore"
}

New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null

$securePassword = Read-Host "Enter the VRL PRO release-key password" -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $keystore
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $alias
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $plainPassword

    $godotArguments = @(
        "--headless",
        "--path", $project
    )

    if (-not (Test-Path -LiteralPath $androidTemplate)) {
        $godotArguments += "--install-android-build-template"
    }

    $godotArguments += @(
        "--export-release", "Android Play Store",
        $output
    )

    & $godot @godotArguments

    if ($LASTEXITCODE -ne 0) {
        throw "Godot export failed with exit code $LASTEXITCODE."
    }

    if (-not (Test-Path -LiteralPath $output)) {
        throw "The AAB was not created."
    }

    Get-Item -LiteralPath $output |
        Select-Object FullName, Length, LastWriteTime
}
finally {
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $null
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $null
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $null
    $plainPassword = $null
    $securePassword = $null

    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
}
