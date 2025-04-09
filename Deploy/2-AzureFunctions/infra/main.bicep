param location string = resourceGroup().location

module functionApp 'flexFunction.bicep' = {
  name: '${deployment().name}-flexapp'
  params: {
    EnvironmentName: deployment().name
    Location: location
    Tags: {}
  }
}

module miPermissions '../../managed-identity-permissions.bicep' =  {
  name: '${deployment().name}-miperms'
  params: {
    managedIdentityId: functionApp.outputs.AppManagedIdentityId
  }
}

output managedIdentityId string = functionApp.outputs.AppManagedIdentityId
