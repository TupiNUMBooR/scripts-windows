[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallDir = "$env:ProgramFiles\platform-tools"
)

$ErrorActionPreference = 'Stop'

$resolvedInstallDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')

if (-not (Test-Path -LiteralPath $resolvedInstallDir -PathType Container)) {
    Write-Host "Platform-Tools directory not found: $resolvedInstallDir"
    exit 0
}

$adbPath = Join-Path $resolvedInstallDir 'adb.exe'
$fastbootPath = Join-Path $resolvedInstallDir 'fastboot.exe'

if (-not (Test-Path -LiteralPath $adbPath -PathType Leaf) -and
    -not (Test-Path -LiteralPath $fastbootPath -PathType Leaf)) {
    throw "Directory does not look like Android Platform-Tools: $resolvedInstallDir"
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathEntries = @(
    $userPath -split ';' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

$filteredPathEntries = @(
    $pathEntries |
        Where-Object { $_.Trim().TrimEnd('\') -ine $resolvedInstallDir }
)

if ($filteredPathEntries.Count -ne $pathEntries.Count) {
    if ($PSCmdlet.ShouldProcess('User PATH', "Remove $resolvedInstallDir")) {
        [Environment]::SetEnvironmentVariable('Path', ($filteredPathEntries -join ';'), 'User')
        Write-Host "Removed from user PATH: $resolvedInstallDir"
    }
}

if ($PSCmdlet.ShouldProcess($resolvedInstallDir, 'Remove Android Platform-Tools directory')) {
    Remove-Item -LiteralPath $resolvedInstallDir -Recurse -Force
    Write-Host "Removed: $resolvedInstallDir"
}

