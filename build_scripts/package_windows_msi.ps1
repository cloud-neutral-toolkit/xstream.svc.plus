#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "windows_bundle_utils.ps1")

function Get-XstreamProjectRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-XstreamVersion {
    $projectRoot = Get-XstreamProjectRoot
    $pubspecPath = Join-Path $projectRoot "pubspec.yaml"
    $versionLine = Select-String -Path $pubspecPath -Pattern '^version:\s*(.+)$' | Select-Object -First 1
    if (-not $versionLine) {
        throw "Unable to find version in $pubspecPath"
    }

    $rawVersion = $versionLine.Matches[0].Groups[1].Value.Trim()
    $parts = $rawVersion -split '\+'
    $semanticVersion = $parts[0]
    $buildNumber = if ($parts.Length -gt 1) { $parts[1] } else { "0" }
    return "$semanticVersion.$buildNumber"
}

function Ensure-WixCli {
    $dotnetTools = Join-Path $env:USERPROFILE ".dotnet\tools"
    if ($env:PATH -notlike "*$dotnetTools*") {
        $env:PATH = "$dotnetTools;$env:PATH"
    }

    if (Get-Command wix -ErrorAction SilentlyContinue) {
        return
    }

    dotnet tool install --global wix --version 5.*

    if (-not (Get-Command wix -ErrorAction SilentlyContinue)) {
        throw "Failed to install WiX CLI."
    }
}

function Escape-Xml {
    param(
        [Parameter(Mandatory = $true)][string]$Value
    )

    return [System.Security.SecurityElement]::Escape($Value)
}

function Get-IdHash {
    param(
        [Parameter(Mandatory = $true)][string]$Value
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA1]::HashData($bytes)
    return ([System.BitConverter]::ToString($hash)).Replace("-", "").Substring(0, 8)
}

function Convert-ToDirectoryId {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return "INSTALLFOLDER"
    }

    $sanitized = $RelativePath -replace '[^A-Za-z0-9]', '_'
    if ($sanitized.Length -gt 36) {
        $sanitized = $sanitized.Substring($sanitized.Length - 36)
    }
    return "Dir_${sanitized}_$(Get-IdHash -Value $RelativePath)"
}

function Convert-ToComponentId {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $sanitized = $RelativePath -replace '[^A-Za-z0-9]', '_'
    if ($sanitized.Length -gt 36) {
        $sanitized = $sanitized.Substring($sanitized.Length - 36)
    }
    return "Cmp_${sanitized}_$(Get-IdHash -Value $RelativePath)"
}

function Convert-ToFileId {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $sanitized = $RelativePath -replace '[^A-Za-z0-9]', '_'
    if ($sanitized.Length -gt 36) {
        $sanitized = $sanitized.Substring($sanitized.Length - 36)
    }
    return "Fil_${sanitized}_$(Get-IdHash -Value $RelativePath)"
}

function Emit-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)][string]$RelativeDirectory,
        [Parameter(Mandatory = $true)][int]$IndentLevel,
        [Parameter(Mandatory = $true)][hashtable]$FilesByDirectory,
        [Parameter(Mandatory = $true)][hashtable]$ChildrenByDirectory
    )

    $indent = "  " * $IndentLevel
    $lines = New-Object System.Collections.Generic.List[string]

    $filesInDirectory = if ($FilesByDirectory.ContainsKey($RelativeDirectory)) { $FilesByDirectory[$RelativeDirectory] } else { @() }
    foreach ($entry in $filesInDirectory) {
        $componentId = Convert-ToComponentId -RelativePath $entry.RelativePath
        $fileId = Convert-ToFileId -RelativePath $entry.RelativePath
        $escapedSource = Escape-Xml -Value $entry.FullName
        $escapedName = Escape-Xml -Value $entry.Name

        $lines.Add("${indent}<Component Id=`"$componentId`" Guid=`"*`">") | Out-Null
        $lines.Add("${indent}  <File Id=`"$fileId`" Source=`"$escapedSource`" Name=`"$escapedName`" KeyPath=`"yes`" />") | Out-Null
        $lines.Add("${indent}</Component>") | Out-Null
    }

    $children = if ($ChildrenByDirectory.ContainsKey($RelativeDirectory)) { $ChildrenByDirectory[$RelativeDirectory] | Sort-Object } else { @() }
    foreach ($child in $children) {
        $directoryName = Split-Path -Path $child -Leaf
        $directoryId = Convert-ToDirectoryId -RelativePath $child
        $escapedName = Escape-Xml -Value $directoryName

        $lines.Add("${indent}<Directory Id=`"$directoryId`" Name=`"$escapedName`">") | Out-Null
        foreach ($line in Emit-DirectoryContents -RelativeDirectory $child -IndentLevel ($IndentLevel + 1) -FilesByDirectory $FilesByDirectory -ChildrenByDirectory $ChildrenByDirectory) {
            $lines.Add($line) | Out-Null
        }
        $lines.Add("${indent}</Directory>") | Out-Null
    }

    return $lines
}

$releaseDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\build\windows\x64\runner\Release"))
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

Copy-XstreamBridgeDll -ReleaseDir $releaseDir
Copy-XstreamVcRuntime -ReleaseDir $releaseDir
Copy-XstreamWintunDll -ReleaseDir $releaseDir

Ensure-WixCli

$version = Get-XstreamVersion
$projectRoot = Get-XstreamProjectRoot
$installerDir = Join-Path $projectRoot "build\windows\x64\installer"
$wxsPath = Join-Path $installerDir "xstream.wxs"
$msiPath = Join-Path $releaseDir "xstream-windows.msi"

if (Test-Path $installerDir) {
    Remove-Item -Recurse -Force $installerDir
}
New-Item -ItemType Directory -Force -Path $installerDir | Out-Null

$files = Get-ChildItem -Path $releaseDir -File -Recurse | Sort-Object FullName
if (-not $files) {
    throw "No files found in $releaseDir for MSI packaging."
}

$directorySet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$directorySet.Add("") | Out-Null
$filesByDirectory = @{}
$componentRefs = New-Object System.Collections.Generic.List[string]

foreach ($file in $files) {
    if ($file.Extension -ieq ".msi") {
        continue
    }

    $relativePath = [System.IO.Path]::GetRelativePath($releaseDir, $file.FullName)
    $relativeDirectory = [System.IO.Path]::GetDirectoryName($relativePath)
    if ($null -eq $relativeDirectory -or $relativeDirectory -eq ".") {
        $relativeDirectory = ""
    } else {
        $relativeDirectory = $relativeDirectory -replace '\\', '/'
    }

    if (-not $filesByDirectory.ContainsKey($relativeDirectory)) {
        $filesByDirectory[$relativeDirectory] = New-Object System.Collections.Generic.List[object]
    }
    $filesByDirectory[$relativeDirectory].Add([PSCustomObject]@{
        RelativePath = $relativePath
        FullName = $file.FullName
        Name = $file.Name
    }) | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($relativeDirectory)) {
        $segments = $relativeDirectory -split '/'
        $current = ""
        foreach ($segment in $segments) {
            if ([string]::IsNullOrWhiteSpace($segment)) {
                continue
            }
            $current = if ([string]::IsNullOrEmpty($current)) { $segment } else { "$current/$segment" }
            $directorySet.Add($current) | Out-Null
        }
    }

    $componentId = Convert-ToComponentId -RelativePath $relativePath
    $componentRefs.Add("      <ComponentRef Id=`"$componentId`" />") | Out-Null
}

$directories = $directorySet.ToArray() | Sort-Object
$childrenByDirectory = @{}
foreach ($directory in $directories) {
    if ([string]::IsNullOrEmpty($directory)) {
        continue
    }

    $parent = [System.IO.Path]::GetDirectoryName($directory.Replace('/', '\'))
    if ($null -eq $parent -or $parent -eq ".") {
        $parent = ""
    } else {
        $parent = $parent -replace '\\', '/'
    }

    if (-not $childrenByDirectory.ContainsKey($parent)) {
        $childrenByDirectory[$parent] = New-Object System.Collections.Generic.List[string]
    }
    $childrenByDirectory[$parent].Add($directory) | Out-Null
}

$directoryXml = Emit-DirectoryContents -RelativeDirectory "" -IndentLevel 3 -FilesByDirectory $filesByDirectory -ChildrenByDirectory $childrenByDirectory

$wxsContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package
    Name="XStream"
    Manufacturer="Xstream Team"
    Version="$version"
    UpgradeCode="D0F4C9A0-ED57-4F14-BB65-30B5CFC8CB0A"
    Scope="perMachine"
    InstallerVersion="500"
    Compressed="yes">
    <SummaryInformation Description="XStream Windows Installer" Manufacturer="Xstream Team" />
    <MajorUpgrade DowngradeErrorMessage="A newer version of XStream is already installed." />
    <MediaTemplate EmbedCab="yes" />

    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="INSTALLFOLDER" Name="XStream">
$($directoryXml -join [Environment]::NewLine)
      </Directory>
    </StandardDirectory>

    <Feature Id="MainFeature" Title="XStream" Level="1">
$($componentRefs -join [Environment]::NewLine)
    </Feature>
  </Package>
</Wix>
"@

Set-Content -Path $wxsPath -Value $wxsContent -Encoding UTF8

if (Test-Path $msiPath) {
    Remove-Item -Force $msiPath
}

wix build $wxsPath -arch x64 -out $msiPath

if (-not (Test-Path $msiPath)) {
    throw "Failed to create MSI package at $msiPath"
}

Write-Host "MSI created successfully: $msiPath"
