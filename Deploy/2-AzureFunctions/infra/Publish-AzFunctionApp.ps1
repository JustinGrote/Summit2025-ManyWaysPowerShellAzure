
#requires -module Az.Functions

function Write-CmdletError {
	param($message, $cmdlet = $PSCmdlet)
	$cmdlet.ThrowTerminatingError(
		[Management.Automation.ErrorRecord]::new(
			$message,
			'CmdletError',
			'InvalidArgument',
			$null
		)
	)
}

filter Publish-AzFunctionApp {
	[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
	param(
		[Parameter(ParameterSetName = 'ByName', Mandatory)]
		[string]$Name,
		[Parameter(ParameterSetName = 'ByName', Mandatory)]
		[string]$ResourceGroupName,

		[Parameter(ParameterSetName = 'ByObject', ValueFromPipeline, Mandatory)]
		$InputObject,

		#Path to either the function app or a completed zip file
		[string]$Path = $PWD,

		#Flex deployment waits 60 seconds to recycle workers. Specify this to wait until that completes. Note you cannot redeploy until this cycle finishes
		[switch]$Wait,

		#Assign the deployment log output to this variable
		[string]$LogVariable
	)

	$ErrorActionPreference = 'Stop'
	$pr = @{
		Id       = (Get-Random)
		Activity = 'Publish-AzFunctionApp'
	}

	if (-not (Get-Command -Type Application -Name func -ErrorAction SilentlyContinue)) {
		Write-CmdletError 'Azure Functions Core Tools not found. Please install from https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local'
	}

	if ($PSCmdlet.ParameterSetName -eq 'ByName' ) {
		$InputObject = Get-AzFunctionApp -Name $Name -ResourceGroupName $ResourceGroupName -WarningAction SilentlyContinue
	} else {
		if (!$Name) { $Name = $InputObject.Name }
	}

	if (-not $InputObject.HostNameSslState -or -not $InputObject.StorageType) { throw 'This does not appear to be an App Function object' }

	if ($InputObject.StorageType -ne 'blobContainer') {
		Write-Warning 'This function app is not using blob storage, this has not been tested with anything but Flex Consumption Plan with blob storage backend.'
	}

	$scmHost = $inputobject.HostNameSslState.Where{ $_.HostType -EQ 'Repository' }.Name
	if (-not $scmHost) { throw 'SCM URI not found for the web app. This is only supported with Flex Consupmption.' }

	$resolvedPath = Resolve-Path $Path
	$zipPath = if ($resolvedPath -like '*.zip') {
		$resolvedPath
	} else {
		Write-Progress @pr -Status "Packing $resolvedPath to zip file using func pack" -PercentComplete 25
		$zipBase = (Join-Path (Get-Item Temp:) (New-Guid))
		func pack -o $zipBase $resolvedPath | Write-Debug

		#Output
		$zipBase + '.zip'
	}

	try {
		$context = @{
			Authentication = 'Bearer'
			Token          = (Get-AzAccessToken -AsSecureString -WarningAction SilentlyContinue).Token
			Verbose        = $false
		}
		$iwrParams = @{
			Uri         = "https://$scmHost/api/publish?RemoteBuild=false&Deployer=az_powershell"
			Method      = 'POST'
			ContentType = 'application/zip'
			InFile      = $zipPath
		}
		if (-not $PSCmdlet.ShouldProcess($Name, "Publish $Path")) {
			return
		}

		Write-Progress @pr -Status "Publishing zip to Function App $Name" -PercentComplete 50
		try {
			$result = Invoke-WebRequest @context @iwrParams
		} catch {
			Write-CmdletError "Failed to publish zip to Function App $Name. Status code: $($PSItem)"
		}
		if ($result.StatusCode -ne 202) {
			Write-CmdletError "Failed to publish zip to Function App $Name. Status code: $($result.StatusCode)"
		}
		Write-Verbose "Deployment accepted. Status code: $($result.StatusCode)"
		[string]$deploymentStatusLink = $result.Headers.Location ?? (throw 'No deployment status link found in response headers')
		if (-not $noWait) {
			$logIndex = 0
			do {
				Write-Progress @pr -Status 'Waiting for completion of deployment job. Details in -Debug' -PercentComplete 75
				Start-Sleep 0.1
				$status = Invoke-RestMethod @context -Uri $deploymentStatusLink

				$logContent = Invoke-RestMethod @context -Uri $status.log_url
				if ($logContent.count -gt $logIndex) {
					$logContent[$logIndex..($logContent.count - 1)]
					| ForEach-Object { "$($_.log_time): $($_.message)" }
					| ForEach-Object {
						if ($_ -like '*Deployment is partially successful from here*' -and -not $Wait) {
							$status.status = -777
							break
						}
					}
					| Write-Verbose
					$logIndex = $logContent.count
				}

				if ($status.status -gt 4) {
					break
				}
			} until ($status.complete)

			if ($status.status -gt 4) {
				Write-CmdletError "Deployment failed: [Code $($status.status)] $($status.status_text)"
			} elseif ($status.status -eq -777) {
				Write-Verbose "Deployment is partially complete and -Wait wasn't specified. Exiting."
			} else {
				if ($status.status -ne 4) {
					Write-CmdletError "Deployment had a non-success code: [Code $($status.status)] $($status.status_text)"
				}
				Write-Verbose "Deployment Id $($status.id) completed successfully at $($status.end_time). Total Duration: $([datetime]::Parse($status.end_time) - [datetime]::Parse($status.start_time))"
			}
		}
	} finally {
		if ($LogVariable) {
			$logContent ??= Invoke-RestMethod @context -Uri $status.log_url
			Set-Variable -Scope 1 -Name $LogVariable -Value $logContent
		}
		$LOCAL:WhatIfPreference = $false
		Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
		Write-Progress @pr -Completed
	}
}

