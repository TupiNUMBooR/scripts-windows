Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
[switch]$IncludeOptional,
[switch]$SkipUpgrade
)

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this script from an elevated PowerShell window.'
}

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host '[step] Installing winget (App Installer)'

  $bundlePath = "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
  Invoke-WebRequest 'https://aka.ms/getwinget' -OutFile $bundlePath
  Add-AppxPackage -Path $bundlePath
}

$wingetArgs = @(
  '--source', 'winget',
  '--accept-package-agreements',
  '--accept-source-agreements',
  '--silent',
  '--disable-interactivity'
)

Write-Host '[step] Refreshing winget sources'
winget source update

$basePackages = Get-Content "$PSScriptRoot\packages-winget-base.txt"
$optionalPackages = Get-Content "$PSScriptRoot\packages-winget-optional.txt"

Write-Host '[step] Installing base packages'
foreach ($id in $basePackages) {
  winget install --exact --id $id @wingetArgs
}

if ($IncludeOptional) {
  Write-Host '[step] Installing optional packages'
  foreach ($id in $optionalPackages) {
    winget install --exact --id $id @wingetArgs
  }
}
else {
  Write-Host '[skip] Optional packages were skipped'
}

if (-not $SkipUpgrade) {
  Write-Host '[step] Upgrading installed packages'
  winget upgrade --all --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
}
else {
  Write-Host '[skip] Package upgrade was skipped'
}

New-Item -ItemType Directory -Force "$env:APPDATA\mpv" | Out-Null
Copy-Item "$PSScriptRoot\mpv.conf" "$env:APPDATA\mpv\mpv.conf" -Force

Write-Host ''
Write-Host 'Update completed.'
