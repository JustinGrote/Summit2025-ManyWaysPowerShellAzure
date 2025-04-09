param name string = deployment().name
param location string = resourceGroup().location

@description('The user identity for the deployment script.')
resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: name
  location: location
}

resource script 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: name
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '12.2.0'
    retentionInterval: 'P1H'
    cleanupPreference: 'OnSuccess'
  }
}
