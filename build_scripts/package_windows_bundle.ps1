#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

# 确保目标目录存在
$releaseDir = "build/windows/x64/runner/Release"
$zipPath = Join-Path $releaseDir "xstream-windows.zip"
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

# 查找并复制 dll
$source = Get-ChildItem -Recurse -Filter "libgo_native_bridge.dll" | Select-Object -First 1
if ($source) {
    Copy-Item $source.FullName -Destination $releaseDir -Force
    Write-Host "Found and copied: $($source.FullName)"
} else {
    Write-Error "Error: libgo_native_bridge.dll not found!"
    exit 1
}

if (!(Test-Path (Join-Path $releaseDir "xstream.exe"))) {
    Write-Error "Error: Windows release executable not found!"
    exit 1
}

if (!(Test-Path (Join-Path $releaseDir "data"))) {
    Write-Error "Error: Flutter data directory not found in release bundle!"
    exit 1
}

# 打包
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}
$archiveItems = Get-ChildItem -Path $releaseDir | Where-Object { $_.Name -ne "xstream-windows.zip" }
Compress-Archive -Path $archiveItems.FullName -DestinationPath $zipPath -Force

# 简单验证打包结果
if (!(Test-Path $zipPath)) {
    Write-Error "Error: Zip package not created!"
    exit 1
}

Write-Host "Package created successfully: $zipPath"
