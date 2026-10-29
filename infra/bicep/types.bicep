@export()
@description('Resource tags.')
type Tags = { *: string }

@export()
@description('Approved model deployment. Capacity is allocation units, not a reservation.')
type Model = {
  name: string
  version: string
  skuName: string
  @minValue(1)
  capacity: int
}

@export()
@description('Fixed governed model aliases; deployments are shared by both projects.')
type Models = {
  'fast-chat': Model
  'advanced-chat': Model
  embeddings: Model
}

@export()
@description('Stable use-case subnet slot; never renumber an existing slot.')
type UseCase = {
  @minLength(3)
  @maxLength(31)
  name: string
  @minValue(1)
  @maxValue(31)
  subnetSlot: int
}

@export()
@description('Shared private DNS zone resource IDs indexed by service.')
type ZoneIds = { *: string }

@export()
@description('Monitoring resources registered with AMPLS.')
type Monitoring = {
  workspaceId: string
  appInsightsId: string
}

@export()
@description('Project-scoped Foundry identity and endpoint.')
type Project = {
  name: string
  id: string
  principalId: string
  endpoint: string
}

@export()
@description('Application backing resource identifiers and connection targets.')
type Backing = {
  storageId: string
  storageEndpoint: string
  searchId: string
  searchEndpoint: string
  cosmosId: string
  cosmosEndpoint: string
  vaultId: string
}

@export()
@description('Private endpoint deployment specification.')
type Endpoint = {
  name: string
  resourceId: string
  groupId: string
  zoneIds: string[]
}

@export()
@description('Approved existing networks; routing and DNS links are managed by the platform.')
type ExistingNetworks = {
  hub: {
    vnetId: string
    privateEndpointSubnetId: string
    apimSubnetId: string
    dnsZoneIds: ZoneIds
  }

  spokes: {
    vnetId: string
    privateEndpointSubnetId: string
    acaSubnetIds: { *: string }
    agentSubnetId: string
  }
}

@export()
@description('Application runtime identity.')
type RuntimeIdentity = {
  name: string
  id: string
  principalId: string
  clientId: string
}

@export()
@description('Named application backing services.')
type ApplicationBacking = {
  name: string
  services: Backing
}

@export()
@description('Named Azure resource.')
type NamedResource = { name: string, id: string }

@export()
@description('Approved operational contact and monthly budgets, in billing currency; alerts do not stop spending.')
type Operations = {
  @minLength(3)
  email: string
  @minLength(20)
  @maxLength(20)
  budgetStartDate: string
  monthlyBudgets: {
    @minValue(1)
    hubInfra: int
    @minValue(1)
    hubServices: int
    @minValue(1)
    spokesInfra: int
    @minValue(1)
    perApp: int
  }
}
