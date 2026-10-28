targetScope = 'subscription'

import { Tags } from '../types.bicep'

@description('Resource group names owned by this deployment.')
param names string[]
@description('Approved Azure region.')
param location string
@description('Ownership and workload tags.')
param tags Tags
@description('Additional tags by resource-group name, for use-case ownership.')
param groupTags { *: Tags } = {}

resource groups 'Microsoft.Resources/resourceGroups@2024-03-01' = [
  for name in names: {
    name: name
    location: location
    tags: union(tags, groupTags[?name] ?? {})
  }
]
