# Mountain Driver 3D - Signing Backup and Setup Guide

This folder contains a backup of the signing certificates required to build and publish **Mountain Driver 3D** to the Google Play Store or to test builds locally. If you ever switch laptops or lose access to your current environment, copy this folder and follow these instructions.

---

## Files Included

1. **`mountain-driver-release.keystore`**
   - **Purpose:** Release signing key for publishing builds (AAB/APK) to the Google Play Console.
   - **Alias:** `mountaindriver`
   - **Original Location:** `C:\Users\Viral L\Documents\MountainDriver-Signing\mountain-driver-release.keystore`

2. **`debug.keystore`**
   - **Purpose:** Local testing signature key automatically used by Godot for debug builds.
   - **Alias:** `androiddebugkey`
   - **Password:** `android`
   - **Original Location:** `C:\Users\Viral L\.android\debug.keystore`

---

## Building Signed Release Packages

The project contains two scripts inside the `release/` directory to generate signed release builds:

### Option A: Generate Signed Release APK (For direct installation/sharing)
1. Run [build-release-apk.ps1](file:///c:/Users/Viral%20L/Downloads/game%201/MountainDriver3D/release/build-release-apk.ps1) in PowerShell.
2. Enter the release keystore password when prompted.
3. This creates a release-signed APK at `builds/android/VRL-Mountain-Driver-3D-release.apk`.

### Option B: Generate Signed Release AAB (For Google Play Store upload)
1. Run [build-play-store.ps1](file:///c:/Users/Viral%20L/Downloads/game%201/MountainDriver3D/release/build-play-store.ps1) in PowerShell.
2. Enter the release keystore password when prompted.
3. This creates a release-signed AAB bundle at `builds/android/VRL-Mountain-Driver-3D-release.aab`.

---

## Restoring Signing Config on a New Laptop

When setting up on a new laptop:
1. Open [build-release-apk.ps1](file:///c:/Users/Viral%20L/Downloads/game%201/MountainDriver3D/release/build-release-apk.ps1) or [build-play-store.ps1](file:///c:/Users/Viral%20L/Downloads/game%201/MountainDriver3D/release/build-play-store.ps1).
2. Update the `$godot` executable path (line 4) to point to the location of the Godot console executable on your new machine.
3. The scripts automatically search this backup directory (`signing_backup`) first for the release keystore file, making it fully portable!
