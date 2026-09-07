$ErrorActionPreference = 'Stop'

$bin = Join-Path $PSScriptRoot 'bin'
$oldTools = $PSScriptRoot
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$normalizedBin = $bin.TrimEnd('\')

$entries = @($entries | Where-Object {
    $_.Trim().TrimEnd('\') -ine $oldTools.TrimEnd('\') -and
    $_.Trim().TrimEnd('\') -ine $normalizedBin
})
$entries += $bin
[Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')

Write-Host "Removed from PATH: $oldTools"
Write-Host "Added to PATH: $bin"
