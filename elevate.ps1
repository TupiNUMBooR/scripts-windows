Start-Process powershell -Verb RunAs -ArgumentList "-NoExit", "-Command", "Set-Location '$((Get-Location).Path)'"
