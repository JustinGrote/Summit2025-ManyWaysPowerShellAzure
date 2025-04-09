@description('The location for the resources')
param location string = resourceGroup().location

@description('Base name for the resources')
param baseName string = deployment().name ?? 'manyways-acajobs'

@description('Container image to use for the job')
param containerImage string = 'ghcr.io/justingrote/manywayspowershell:latest'

@description('Environment variables for the container')
param environmentVariables array = [
  {
    name: 'SOURCENAME'
    value: 'ACA Jobs'
  }
]

@description('CPU cores allocated to a single container instance')
param cpuCores int = 2

@description('Memory allocated to a single container instance')
param memorySize string = '4.0Gi'

@description('Maximum retry count for the job')
param maxRetryCount int = 1

@description('The replica timeout in seconds')
param replicaTimeout int = 300

// Log Analytics workspace for container insights
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: baseName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Container App Environment
resource environment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: baseName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// Container App Job
resource containerJob 'Microsoft.App/jobs@2024-10-02-preview' = {
  name: baseName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: environment.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: replicaTimeout
      registries: []
      secrets: []
      replicaRetryLimit: maxRetryCount
    }
    template: {
      containers: [
        {
          image: containerImage
          name: 'main'
          resources: {
            cpu: cpuCores
            memory: memorySize
          }
          env: environmentVariables
        }
      ]
    }
  }
}


module miPermissions '../managed-identity-permissions.bicep' =  {
  name: '${deployment().name}-miperms'
  params: {
    managedIdentityId: containerJob.identity.principalId
  }
}

@description('The name of the container app job')
output jobName string = containerJob.name

@description('The name of the container app environment')
output envName string = environment.name

@description('The resource ID of the container app job')
output jobId string = containerJob.id
