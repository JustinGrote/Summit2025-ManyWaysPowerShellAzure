@minLength(3)
@maxLength(63)
@description('Name of the the environment which is used as the base name for all resources')
param EnvironmentName string = resourceGroup().name

@minLength(1)
@description('Primary location for all resources')
param Location string = resourceGroup().location

@description('Optional Tags to apply to all resources. Provide a single object with name-value pairs')
param Tags object = {}

@description('Additional App Settings to apply to the function app. Provide an array with objects that have name and value properties')
param AppSettings array = []

@description('Name of the Azure Function App, if different than the environment name')
param FunctionAppName string = EnvironmentName
@description('Name of the Azure Function Plan, if different than the environment name')
param FunctionPlanName string = EnvironmentName
@description('The storage account name. Must contain only lowercase letters and numbers. Must be between 3 and 24 characters in length.')
@minLength(3)
@maxLength(20)
param StorageAccountName string = '__DEFAULT__'
@description('Name of the storage account conatiner where the Flex Function content will be published, if different than the environment name')
param DeploymentStorageContainerName string = '__DEFAULT__'
@description('Name of the Log Analytics Worksace, if different than the environment name')
param LogAnalyticsName string = EnvironmentName
@description('Name of the Application Insights instance, if different than the environment name')
param AppInsightsName string = EnvironmentName
@description('The version of PowerShell to use for the function app runtime. Default is 7.4.')
param PowerShellVersion string = '7.4'
@minValue(40)
@maxValue(1000)
@description('The maximum number of instances that the function app can scale out to. Default is 100.')
param MaximumInstanceCount int = 100

@allowed([2048,4096])
@description('The size of the function app instances in MB. Default is 2048, 4096 is also supported. You get 2 vCPUs in the 2048 instance, and 4 vCPUs in the 4096 instance.')
param InstanceSizeMB int = 2048

@description('How long to retain previous versions of the function app in container storage, acting as a de-facto backup. Default is 7 days.')
param deploymentStorageRetentionDays int = 7

var functionAppRuntime = 'powerShell'

// Generate a unique token to be used in naming resources.
var resourceToken = toLower(uniqueString(resourceGroup().id, Location, EnvironmentName))
var storageAccountName = StorageAccountName == '__DEFAULT__' ? 'flexfuncapp${take(resourceToken,12)}' : StorageAccountName
var deploymentStorageContainerName = DeploymentStorageContainerName == '__DEFAULT__' ? 'flexfuncapp${take(resourceToken,12)}' : DeploymentStorageContainerName

var tags = shallowMerge([
  {
    Environment: EnvironmentName
  }

  Tags
])

var appSettings = concat(
  [
    {
      name: 'AzureWebJobsStorage__accountName'
      value: storage.name

    }
    {
      name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
      value: appInsights.properties.ConnectionString
    }
  ],
  AppSettings
)

resource flexFuncApp 'Microsoft.Web/sites@2023-12-01' = {
  name: FunctionAppName
  location: Location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: flexFuncPlan.id
    siteConfig: {
      appSettings: appSettings
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentStorageContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: MaximumInstanceCount
        instanceMemoryMB: InstanceSizeMB
      }
      runtime: {
        name: functionAppRuntime
        version: PowerShellVersion
      }
    }
  }
}

resource flexFuncPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: FunctionPlanName
  location: Location
  tags: Tags
  kind: 'functionapp'
  sku: {
    tier: 'FlexConsumption'
    name: 'FC1'
  }
  properties: {
    reserved: true
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: storageAccountName
  location: Location
  tags: shallowMerge([Tags, { FunctionApp: FunctionAppName }])
  kind: 'StorageV2'
  sku: {name: 'Standard_LRS'}
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: true
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    dnsEndpointType: 'Standard'
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
  }

  resource blobServices 'blobServices' = {
    name: 'default'
    properties: {
      deleteRetentionPolicy: {
        days: deploymentStorageRetentionDays
        enabled: true
      }
    }
    resource container 'containers' = {
      name: deploymentStorageContainerName
    }
  }
}


// Allow access from function app to storage account using a managed identity
// The delegatedManagedIdentiyResourceId is required for Azure Lighthouse scenarios and you must have permissions to assign rights on behalf of the delegated managed identity as part of your Azure Lighthouse configuration

var storageBlobDataOwnerRoleId  = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' //Storage Blob Data Owner role well known GUID
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(flexFuncApp.id, storage.id, storageBlobDataOwnerRoleId)
  scope: storage
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: flexFuncApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: LogAnalyticsName
  location: Location
  tags: Tags
  properties: {
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: AppInsightsName
  location: Location
  tags: Tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

output AppId string = flexFuncApp.id
output AppName string = flexFuncApp.name
output AppManagedIdentityId string = flexFuncApp.identity.principalId

output AppInsightsConnectionString string = appInsights.properties.ConnectionString
