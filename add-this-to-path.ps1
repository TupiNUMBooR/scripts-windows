# $tools = "$env:USERPROFILE\tools"
$tools = $PWD

[Environment]::SetEnvironmentVariable("Path", "$env:Path;$tools", "User")
Write-Host "Added to PATH: $tools"
