Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

New-Item -ItemType Directory -Force "$env:APPDATA\mpv"
Copy-Item "$PSScriptRoot\wsl\mpv.conf" "$env:APPDATA\mpv\mpv.conf" -Force

winget source update
winget import -i "$PSScriptRoot\wsl\packages.winget.json"
winget import -i "$PSScriptRoot\wsl\packages-full.winget.json"

wsl --update
wsl --install archlinux
wsl --set-default archlinux

Write-Host ''
Write-Host 'Update completed.'
