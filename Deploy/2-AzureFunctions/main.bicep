param location string = resourceGroup().location

module functionApp 'br/public:avm/res/web/site:0.15.1' = {
  name: '${deployment().name}-funcApp'
  params: {
    // Required parameters
    kind: 'functionapp'
    location: location
    name: 'manywayspowershell-functionapp'
    serverFarmResourceId: farm.id
    // Non-required parameters
    // appInsightResourceId: '<appInsightResourceId>'
    appSettingsKeyValuePairs: {
      FUNCTIONS_EXTENSION_VERSION: '~4'
      FUNCTIONS_WORKER_RUNTIME: 'powershell'
    }
    siteConfig: {
      // Consumption plan cannot use alwaysOn
      alwaysOn: false
      linuxFxVersion: 'powershell|7.4'
    }
    managedIdentities: {
      systemAssigned: true
    }

    storageAccountResourceId: funcStorageAccount.outputs.resourceId
    storageAccountUseIdentityAuthentication: true
  }
}

// Azure Verified Module does not support Consumption plan (cannot set Tier to Dynamic)
resource farm 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: deployment().name
  location: location
  kind: 'linux'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
}

module funcStorageAccount 'br/public:avm/res/storage/storage-account:0.19.0' = {
  name: '${deployment().name}-storage'
  params: {
    // Required parameters
    name: 'manywaysapp${uniqueString(deployment().name,resourceGroup().id)}'
    location: location
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    // Non-required parameters
    // accessTier: 'Hot'
    // enableHttpsTrafficOnly: true
    // minTlsVersion: 'TLS1_2'
  }
}


// Graph permissions

// Sadly, deployment stacks not supported with Graph extensions as of March 2025
extension microsoftGraph

var tagContributorRoleId = '4a9ae827-6dc8-4573-8ac7-8239d42aa03f'

// Grant tag contributor rights to the resource group for the Managed Identity
resource tagContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  scope: resourceGroup()
  name: guid(functionApp.name, resourceGroup().name, tagContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', tagContributorRoleId)
    principalId: functionApp.outputs.?systemAssignedMIPrincipalId ?? 'ERROR-NO-AA-PRINCIPAL-ID'
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
  principalId: functionApp.outputs.?systemAssignedMIPrincipalId ?? 'ERROR-NO-AA-PRINCIPAL-ID'
  resourceId: GraphWellKnownServicePrincipal.id
}]

output automationAccountId string = functionApp.outputs.systemAssignedMIPrincipalId!
