extension microsoftGraph

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: 'westus3'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    containers: [
      {
        name: deployment().name
        properties: {
          image: 'ghcr.io/justingrote/manywayspowershell'
          environmentVariables: [
            {
              name: 'SOURCENAME'
              value: 'AzureContainerInstances'
            }
          ]
          resources: {
            requests: {
              cpu: 2
              memoryInGB: 4
            }
          }
        }
      }
    ]

    osType: 'Linux'
    restartPolicy: 'Never'
  }
}


module miPermissions '../managed-identity-permissions.bicep' =  {
  name: '${deployment().name}-miperms'
  params: {
    managedIdentityId: containerGroup.identity.principalId
  }
}

output Id string = containerGroup.id
