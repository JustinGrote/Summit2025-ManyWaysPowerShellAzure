[CmdletBinding()]
param(
	[Parameter(Mandatory)][string]$Name = $ENV:SOURCENAME ?? 'PowerShell',
	[string]$Message = $ENV:SOURCEMESSAGE ?? 'Hello from',
	#The resource group to add the tag to
	[string]$ResourceGroupName = $ENV:RESOURCEGROUPNAME ?? 'TheManyWaysToPowerShellInAzure',
	#Client ID and Client Secret. If not supplied, will try managed identity
	[PSCredential]$Credential,
	#Which Subscription the RG is in
	[string]$SubscriptionId = $ENV:AZURE_SUBSCRIPTION_ID ?? '52487fb1-7325-4ec9-9bb0-a9079e62d255',
	#Use this identity rather than the default managed identity
	[string]$UserManagedIdentityId = $ENV:USER_MANAGED_IDENTITY_CLIENT_ID,
	#Only output the requested string, do not do any API calls
	[switch]$OutputOnly
)
$ErrorActionPreference = 'Stop'
$ErrorView = 'DetailedView'

#Load Telemetry Trace Module
#This isn't sensitive, but replace it with your own, all you'll do is populate my demo data with your own garbage, and that's just not nice.
$ENV:APPLICATIONINSIGHTS_CONNECTION_STRING ??= 'InstrumentationKey=0356b9f6-5179-4cf9-8e90-8af16d76d0cd;IngestionEndpoint=https://westus3-1.in.applicationinsights.azure.com/;LiveEndpoint=https://westus3.livediagnostics.monitor.azure.com/;ApplicationId=f188e6a5-d7b2-45d6-9734-721cf455b494'
Invoke-WebRequest bit.ly/traceps | Invoke-Expression

Trace-AICommand -Name ("ManyWays-$Name" -replace ' ') {
	#region Troubleshooting Info

	#Log Environment Info
	if ($VerbosePreference -ne 'SilentlyContinue') {
		Write-Verbose '===POWERSHELL INFO==='
		($PSVersionTable | Format-Table -auto | Out-String).split("`n") | Write-Verbose
		Write-Verbose "PWSH Command Line: $([Environment]::CommandLine)"
		Write-Verbose "Machine Name: $([Environment]::MachineName)"
		Write-Verbose "CPU Cores: $([Environment]::ProcessorCount)"

		#Doesn't account for mac (GitHub Actions)
		if (!$isMacOS) {
			$memory = $isLinux ? (Get-Content /proc/meminfo | Select-String MemTotal, MemFree | Out-String) : ([uint]((gcim Win32_computersystem -Verbose:$false | ForEach-Object totalphysicalmemory) / 1MB))
			Write-Verbose "Memory: $memory"
		}

		Write-Verbose '===INVOCATION INFO==='
		($myinvocation.mycommand
		| Format-List name, commandtype, source, version, module, modulename, parameters, parametersets
		| Out-String).split("`n") | Write-Verbose
		Write-Verbose '===ENVIRONMENT VARIABLES==='
		(Get-ChildItem env: | Format-Table -auto | Out-String).split("`n") | Write-Verbose
		Write-Verbose '===POWERSHELL VARIABLES==='
		(Get-Variable | Format-Table -auto | Out-String).split("`n") | Write-Verbose
		Write-Verbose '===POWERSHELL MODULES==='

		#Suppress module loading messages when you do this
		$CurrentVerbosePreference = $VerbosePreference
		$VerbosePreference = 'SilentlyContinue'
		$modules = (Get-Module -ListAvailable -Verbose:$false | Format-Table -auto name, version, prerelease, moduletype, path | Out-String).split("`n")
		$VerbosePreference = $CurrentVerbosePreference
		$modules | Write-Verbose
		#endregion
	}

	$fullMessage = "$Message $Name"

	if ($OutputOnly) {
		return $fullMessage
	}

	try {
		#Modulefast quick install for Az and Graph. Typically don't do this, bundle your modules instead.
		Invoke-WebRequest bit.ly/modulefast | Invoke-Expression
		Install-ModuleFast -Scope CurrentUser -Update -NoPSModulePathUpdate -NoProfileUpdate -Specification @(
			'Az.Resources>=7.9',
			'Microsoft.Graph.Users>2.26',
			'Microsoft.Graph.Identity.DirectoryManagement>2.26'
		)

		Import-Module Az.Resources, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Users

		#region Azure Tag

		#Connect to Azure ARM API
		$azConnectParams = @{
			Subscription = $SubscriptionId
		}
		if ($Credential) {
			$azConnectParams.ServicePrincipal = $true
			$azConnectParams.Credential = $Credential
		} else {
			$azConnectParams.Identity = $true
		}
		if ($UserManagedIdentityId) {
			$azConnectParams.AccountId = $UserManagedIdentityId
		}
		$azContext = Connect-AzAccount @azConnectParams

		#Create the tag
		$resourceGroup = Get-AzResourceGroup $ResourceGroupName
		#Make a tag with the message as the name and a datestamp as the time

		$tags = @{}
		$tags.$fullMessage = (Get-Date)

		#This operation will upsert, updating the value if the tag already exist
		$newTag = New-AzTag -ResourceId $resourceGroup.ResourceId -Tag $tags

		Write-Verbose ('Created tag on {0} with name {1} and value {2}' -f $resourceGroup.ResourceId,
			($newtag.properties.tagsproperty.keys | Select-Object -First 1),
			($newtag.properties.tagsproperty.values | Select-Object -First 1)
		)

		#endregion


		#region Graph
		#Connect to Microsoft Graph API
		$connectParams = @{
			NoWelcome = $true
		}
		if ($Credential) {
			$connectParams.ClientId = $Credential.UserName
			$connectParams.ClientSecret = $Credential.GetNetworkCredential().Password
		} else {
			$connectParams.Identity = $true
		}
		if ($UserManagedIdentityId) {
			$connectParams.ClientId = $UserManagedIdentityId
		}
		$graphContext = Connect-MgGraph @connectParams -Verbose -Debug

		#Create a new user in Microsoft Graph
		$guid = New-Guid
		$defaultDomain = Get-MgDomain | Where-Object IsDefault -EQ $true | Select-Object -First 1 | ForEach-Object Id
		$uniqueName = "manyways_$guid"
		$newUserParams = @{
			DisplayName       = "Manyways $Name"
			MailNickname      = $uniqueName
			UserPrincipalName = "$uniqueName@$defaultDomain"
			CompanyName       = $fullMessage
			AccountEnabled    = $false
			PasswordProfile   = @{
				Password                      = (New-Guid)
				ForceChangePasswordNextSignIn = $true
			}
		}
		$newUser = New-MgUser @newUserParams

		Write-Verbose "Created new user: $($newUser.DisplayName) ($($newUser.UserPrincipalName))"
		#endregion
	} catch {
		#More universal error result output
		throw (Get-Error $PSItem | Out-String)
	} finally {
		Write-Verbose 'SCRIPT FINISHED'
		([Environment]::CpuUsage | Out-String).Split("`n") | Write-Verbose -Verbose
		"Memory Usage (at end of script, not during): $([uint]([System.GC]::GetTotalMemory($false) / 1MB))" | Write-Verbose -Verbose
	}
}