#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

# Ensure the release directory exists before copying artifacts.
$releaseDir = "build/windows/x64/runner/Release"
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

# Always package the freshly built bridge from bindings/.
$source = Join-Path $PSScriptRoot "..\bindings\libgo_native_bridge.dll"
if (Test-Path $source) {
    Copy-Item $source -Destination $releaseDir -Force
    Write-Host "Copied bridge DLL: $source"
} else {
    Write-Error "Error: libgo_native_bridge.dll not found!"
    exit 1
}

# Package the release bundle.
Compress-Archive -Path "$releaseDir/*" -DestinationPath "$releaseDir/xstream-windows.zip" -Force

# Verify the package was created.
if (!(Test-Path "$releaseDir/xstream-windows.zip")) {
    Write-Error "Error: Zip package not created!"
    exit 1
}

Write-Host "Package created successfully: $releaseDir/xstream-windows.zip"
