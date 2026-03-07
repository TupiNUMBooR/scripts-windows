Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

winget source update
winget import -i "$PSScriptRoot\wsl\packages-winget.json"

New-Item -ItemType Directory -Force "$env:APPDATA\mpv"
Copy-Item "$PSScriptRoot\wsl\mpv.conf" "$env:APPDATA\mpv\mpv.conf" -Force

Write-Host ''
Write-Host 'Update completed.'
