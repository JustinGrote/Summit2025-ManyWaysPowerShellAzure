@description('Location for all resources.')
param location string = resourceGroup().location

@description('Timestamp used to uniquely identify the deployment')
param timestamp string = utcNow()

resource deploymentScriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: deployment().name
  location: location
}

module miPerms '../managed-identity-permissions.bicep' = {
  name: 'miPerms'
  params: {
    managedIdentityId: deploymentScriptIdentity.properties.principalId
  }
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  dependsOn: [
    miPerms
  ]
  name: deployment().name
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentScriptIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '13.3'
    timeout: 'PT5M'
    retentionInterval: 'P1D'
    cleanupPreference: 'OnSuccess'
    scriptContent: loadTextContent('../../Scripts/main.ps1')
    // You can also use forceUpdateTag to ensure the script runs on each deployment
    forceUpdateTag: timestamp
    environmentVariables: [
      {
        name: 'SOURCENAME'
        value: 'AzureDeploymentScript'
      }
    ]
  }
}

// Output the principal ID of the system-assigned managed identity
output deploymentScriptPrincipalId string = deploymentScript.identity.userAssignedIdentities[deploymentScriptIdentity.id].principalId
output deploymentScriptResults object = deploymentScript.properties.status
