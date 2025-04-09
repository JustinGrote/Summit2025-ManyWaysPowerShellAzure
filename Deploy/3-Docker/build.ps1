#Because Docker is finicky about symlinks
Copy-Item $PSScriptRoot/../../Scripts/main.ps1 $PSScriptRoot/main.staged.ps1 -Force
docker build -t manywayspowershell $PSScriptRoot