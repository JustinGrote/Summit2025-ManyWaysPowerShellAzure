// main.bicep - Get an existing Azure Arc-enabled machine
param machineName string = 'tinycloud'

// Get an existing Azure Arc-enabled machine resource
resource arcEnabledMachine 'Microsoft.HybridCompute/machines@2023-06-20-preview' existing = {
  name: machineName
}

module miPerms '../managed-identity-permissions.bicep' = {
  name: 'miPerms'
  params: {
    managedIdentityId: arcEnabledMachine.identity.principalId
  }
}
