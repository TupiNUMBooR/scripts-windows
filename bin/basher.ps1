param(
    [Alias('b')]
    [switch]$Build
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkDir = (Get-Location).Path
$BasherDir = Join-Path $PSScriptRoot '..\..\basher'

$ComposeArgs = @('compose', 'run', '--rm')

if ($Build) {
    $ComposeArgs += '--build'
}

$ComposeArgs += @('--volume', "${WorkDir}:/workspace", 'basher')

Push-Location $BasherDir
try {
    docker @ComposeArgs
}
finally {
    Pop-Location
}
