$ErrorActionPreference = "Stop"

param(
  [Parameter(Mandatory = $true)]
  [string]$FlutterVersion
)

$installRoot = Join-Path $env:RUNNER_TEMP "flutter-sdk"
if (Test-Path $installRoot) {
  Remove-Item -Recurse -Force $installRoot
}
New-Item -ItemType Directory -Path $installRoot | Out-Null

$archive = Join-Path $installRoot "flutter-sdk.zip"
Invoke-WebRequest -Uri "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_${FlutterVersion}-stable.zip" -OutFile $archive
Expand-Archive -Path $archive -DestinationPath $installRoot -Force

"$installRoot\flutter\bin" | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
& "$installRoot\flutter\bin\flutter.bat" --version
