Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# update.ps1

#region Variables

$WslDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'wsl'
$WslUpdateScript = Join-Path $PSScriptRoot 'wsl-update.sh'
$Distro = 'archlinux'

$WingetImportArgs = @(
    '--no-upgrade'
    '--accept-package-agreements'
    '--accept-source-agreements'
)

#endregion

#region PowerShell

if ((Get-ExecutionPolicy -Scope CurrentUser) -ne 'RemoteSigned') {
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
}

#endregion

#region PATH

$ToolsDir = $PSScriptRoot
$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$UserPathEntries = @(
    $UserPath -split ';' |
        Where-Object { $_ }
)

if ($ToolsDir -notin $UserPathEntries) {
    $NewUserPath = (@($UserPathEntries) + $ToolsDir) -join ';'

    [Environment]::SetEnvironmentVariable(
        'Path',
        $NewUserPath,
        'User'
    )

    Write-Host "Added to PATH: $ToolsDir"
}

if ($ToolsDir -notin ($env:Path -split ';')) {
    $env:Path += ";$ToolsDir"
}

#endregion

#region Windows configuration

$MpvDir = Join-Path $env:APPDATA 'mpv'

New-Item -ItemType Directory -Force $MpvDir | Out-Null
Copy-Item "$WslDir\mpv.conf" "$MpvDir\mpv.conf" -Force

#endregion

#region Windows packages

winget source update
winget import -i "$WslDir\packages.winget.json" @WingetImportArgs

# winget import -i "$WslDir\packages-full.winget.json" @WingetImportArgs

#endregion

#region Git

$GitUserName = git config --global user.name
$GitUserEmail = git config --global user.email

if (-not $GitUserName) {
    $GitUserName = Read-Host 'Git user.name'
    git config --global user.name $GitUserName
}

if (-not $GitUserEmail) {
    $GitUserEmail = Read-Host 'Git user.email'
    git config --global user.email $GitUserEmail
}

git config --global init.defaultBranch dev
git config --global push.autoSetupRemote true
git config --global core.autocrlf input

$WindowsGitConfig = Join-Path $env:USERPROFILE '.gitconfig'

#endregion

#region WSL installation

wsl --update
if (-not ((wsl --list --quiet) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $Distro })) {
    wsl --install $Distro
}
wsl --set-default $Distro

# Initialize the distro before configuring it.
wsl -d $Distro -u root -- true

#endregion

#region WSL configuration

Get-Content "$WslDir\wsl.conf" -Raw |
    wsl -d $Distro -u root -- tee /etc/wsl.conf |
    Out-Null

if (Test-Path $WindowsGitConfig) {
    Get-Content $WindowsGitConfig -Raw |
        wsl -d $Distro -u root -- tee /root/.gitconfig |
        Out-Null
}
else {
    Write-Warning "Windows Git config not found: $WindowsGitConfig"
}

#endregion

#region WSL packages and configuration

$WslUpdateScriptWindowsPath = $WslUpdateScript -replace '\\', '/'
$WslUpdateScriptPath = (& wsl -d $Distro -- wslpath -u $WslUpdateScriptWindowsPath).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Could not resolve the WSL update script path.'
}

wsl -d $Distro -- bash $WslUpdateScriptPath
if ($LASTEXITCODE -ne 0) {
    throw "WSL update failed with exit code $LASTEXITCODE."
}

#endregion

#region Finish

wsl --shutdown

Write-Host ''
Write-Host 'Update completed.'

#endregion
