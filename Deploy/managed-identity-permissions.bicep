extension microsoftGraph
param managedIdentityId string


var tagContributorRoleId = '4a9ae827-6dc8-4573-8ac7-8239d42aa03f'

// Grant tag contributor rights to the resource group for the Managed Identity
resource tagContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  scope: resourceGroup()
  name: guid(managedIdentityId, tagContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', tagContributorRoleId)
    principalId: managedIdentityId
  }
}

// Thanks: https://gotoguy.blog/2024/05/23/add-graph-application-permissions-to-managed-identity-using-bicep-graph-extension/
// Get the Resource Id of the well known Graph Service Principal in order to validate the scopes
resource GraphWellKnownServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: '00000003-0000-0000-c000-000000000000'
}

// Looping through the App Roles and assigning them to the Managed Identity
param appRoles array = [
  // Used to create a user in the tenant
  'User.ReadWrite.All'
  // Used to read the primary domain to generate a user
  'Domain.Read.All'
  'Directory.Read.All'
]

resource assignAppRole 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for appRole in appRoles: {
  // Fancy way to get the available Graph scopes, filter to the app role we are working with above, and get the role GUID
  appRoleId: (filter(GraphWellKnownServicePrincipal.appRoles, role => role.value == appRole)[0]).id
  principalId: managedIdentityId
  resourceId: GraphWellKnownServicePrincipal.id
}]

output graph string = assignAppRole[0].id
