[CmdletBinding()]
param(
    [string]$InstallDir = "$env:ProgramFiles\platform-tools"
)

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host 'Requesting administrator privileges...'
    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $PSCommandPath)
        '-InstallDir'
        ('"{0}"' -f $InstallDir)
    )
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $process.ExitCode
}

$downloadUrl = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("platform-tools-{0}" -f [guid]::NewGuid())
$archivePath = Join-Path $tempDir 'platform-tools.zip'
$extractDir = Join-Path $tempDir 'extracted'

try {
    New-Item -ItemType Directory -Path $tempDir, $extractDir -Force | Out-Null

    Write-Host 'Downloading Android SDK Platform-Tools...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing

    Write-Host 'Extracting archive...'
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDir -Force

    $extractedToolsDir = Join-Path $extractDir 'platform-tools'
    if (-not (Test-Path (Join-Path $extractedToolsDir 'adb.exe') -PathType Leaf)) {
        throw 'The downloaded archive does not contain platform-tools\adb.exe.'
    }

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item -Path (Join-Path $extractedToolsDir '*') -Destination $InstallDir -Recurse -Force
    Write-Host "Installed to: $InstallDir"

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathEntries = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $normalizedInstallDir = $InstallDir.TrimEnd('\')
    $alreadyInPath = $pathEntries | Where-Object { $_.Trim().TrimEnd('\') -ieq $normalizedInstallDir }

    if (-not $alreadyInPath) {
        $newUserPath = (($pathEntries + $InstallDir) -join ';')
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        Write-Host 'Added platform-tools to the user PATH.'
    }
    else {
        Write-Host 'platform-tools is already in the user PATH.'
    }

    $processPathEntries = @($env:Path -split ';')
    if (-not ($processPathEntries | Where-Object { $_.Trim().TrimEnd('\') -ieq $normalizedInstallDir })) {
        $env:Path = "$env:Path;$InstallDir"
    }

    Write-Host "`nChecking adb..."
    & (Join-Path $InstallDir 'adb.exe') version
    if ($LASTEXITCODE -ne 0) {
        throw "adb check failed with exit code $LASTEXITCODE."
    }

    Write-Host "`nChecking fastboot..."
    & (Join-Path $InstallDir 'fastboot.exe') --version
    if ($LASTEXITCODE -ne 0) {
        throw "fastboot check failed with exit code $LASTEXITCODE."
    }

    Write-Host "`nPATH lookup:"
    Get-Command adb.exe, fastboot.exe | Select-Object Name, Source | Format-Table -AutoSize

    Write-Host 'Android SDK Platform-Tools are installed and working.' -ForegroundColor Green
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}
