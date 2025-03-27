#Azure Automation

#Log Environment Info
Write-Verbose "===POWERSHELL INFO==="
$PSVersionTable | Format-Table -auto | Out-String | Write-Verbose
Write-Verbose "===INVOCATION INFO==="
$MyInvocation.MyCommand | Format-Table -auto | Out-String | Write-Verbose
Write-Verbose "===ENVIRONMENT VARIABLES==="
Get-ChildItem env: | Format-Table -auto | Out-String | Write-Verbose
Write-Verbose '===POWERSHELL VARIABLES==='
Get-Variable | Format-Table -auto | Out-String | Write-Verbose
Write-Verbose '===POWERSHELL MODULES==='
Get-Module -ListAvailable | Format-Table -auto | Out-String | Write-Verbose