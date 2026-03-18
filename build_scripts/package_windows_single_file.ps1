#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "windows_bundle_utils.ps1")

$releaseDir = Get-XstreamWindowsReleaseDir
$portableDir = Join-Path $PSScriptRoot "..\build\windows\x64\portable"
$runtimeDir = Join-Path $portableDir "runtime"
$launcherSrcDir = Join-Path $portableDir "launcher-src"
$payloadZip = Join-Path $portableDir "payload.zip"
$portableExe = Join-Path $portableDir "xstream.exe"
$innerExeName = "xstream_runtime.exe"

New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
New-Item -ItemType Directory -Force -Path $portableDir | Out-Null

Copy-XstreamBridgeDll -ReleaseDir $releaseDir
Copy-XstreamVcRuntime -ReleaseDir $releaseDir
Copy-XstreamWintunDll -ReleaseDir $releaseDir

if (Test-Path $runtimeDir) {
    Remove-Item -Recurse -Force $runtimeDir
}
if (Test-Path $launcherSrcDir) {
    Remove-Item -Recurse -Force $launcherSrcDir
}
if (Test-Path $payloadZip) {
    Remove-Item -Force $payloadZip
}

New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
New-Item -ItemType Directory -Force -Path $launcherSrcDir | Out-Null

$excludeNames = @(
    "xstream-windows.zip",
    "AppxManifest.xml",
    "Images",
    "resources.pri",
    "resources.scale-125.pri",
    "resources.scale-150.pri",
    "resources.scale-200.pri",
    "resources.scale-400.pri"
)

Get-ChildItem $releaseDir -Force | ForEach-Object {
    if ($excludeNames -contains $_.Name) {
        return
    }

    if ($_.PSIsContainer) {
        Copy-Item $_.FullName -Destination (Join-Path $runtimeDir $_.Name) -Recurse -Force
    } elseif ($_.Name -eq "xstream.exe") {
        Copy-Item $_.FullName -Destination (Join-Path $runtimeDir $innerExeName) -Force
    } else {
        Copy-Item $_.FullName -Destination (Join-Path $runtimeDir $_.Name) -Force
    }
}

Compress-Archive -Path (Join-Path $runtimeDir "*") -DestinationPath $payloadZip -Force

Copy-Item (Join-Path $PSScriptRoot "..\tools\windows-portable-launcher\*") `
    -Destination $launcherSrcDir -Recurse -Force
Copy-Item $payloadZip -Destination (Join-Path $launcherSrcDir "payload.zip") -Force

$goCommand = Get-Command go -ErrorAction SilentlyContinue
if (-not $goCommand) {
    throw "go not found in PATH. Install Go or add it to PATH before building the single-file Windows launcher."
}

Push-Location $launcherSrcDir
try {
    & $goCommand.Source build -trimpath -ldflags "-s -w -H=windowsgui" -o $portableExe .
    if ($LASTEXITCODE -ne 0) {
        throw "go build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path $portableExe)) {
    throw "Single-file launcher was not created: $portableExe"
}

Write-Host "Single-file launcher created successfully: $portableExe"
