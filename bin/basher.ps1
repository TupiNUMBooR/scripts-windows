Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Image = 'ghcr.io/tupinumboor/basher:latest'
$EnvFile = Join-Path $PSScriptRoot '..\.env'

docker pull $Image
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Could not pull the image; using the local image if available."
}

$DockerArgs = @(
    'run', '--rm', '--interactive', '--tty',
    '--volume', "$(Get-Location):/workspace",
    '--env-file', $EnvFile
)

docker @DockerArgs $Image
exit $LASTEXITCODE
