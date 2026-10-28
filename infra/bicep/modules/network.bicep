import { Tags, UseCase } from '../types.bicep'

@description('Virtual network name.')
param name string
@description('Approved Azure region.')
param location string
@description('Ownership tags.')
param tags Tags
@description('Non-overlapping IPv4 /16 address range.')
param addressPrefix string
@description('Hub or spokes subnet layout.')
@allowed(['hub', 'spokes'])
param role string
@description('Stable dedicated ACA subnet slots.')
param useCases UseCase[]

var acaSubnets = [
  for app in useCases: {
    name: 'snet-aca-${app.name}'
    prefix: cidrSubnet(addressPrefix, 23, app.subnetSlot)
    service: 'Microsoft.App/environments'
  }
]
var subnets = concat(
  [
    {
      name: 'snet-private-endpoints'
      prefix: cidrSubnet(addressPrefix, 26, 0)
      service: ''
    }
  ],
  role == 'hub'
    ? [
        {
          name: 'snet-apim-outbound'
          prefix: cidrSubnet(addressPrefix, 27, 2)
          service: 'Microsoft.Web/serverFarms'
        }
      ]
    : concat(
        [
          {
            name: 'snet-foundry-agent'
            prefix: cidrSubnet(addressPrefix, 24, 192)
            service: 'Microsoft.App/environments'
          }
        ],
        acaSubnets
      )
)

resource nsgs 'Microsoft.Network/networkSecurityGroups@2024-05-01' = [
  for subnet in subnets: {
    name: 'nsg-${subnet.name}'
    location: location
    tags: tags
    properties: {}
  }
]

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressPrefix] }
    subnets: [
      for (subnet, i) in subnets: {
        name: subnet.name
        properties: {
          addressPrefix: subnet.prefix
          privateEndpointNetworkPolicies: 'Enabled'
          networkSecurityGroup: { id: nsgs[i].id }
          delegations: empty(subnet.service)
            ? []
            : [
                {
                  name: 'delegation'
                  properties: { serviceName: subnet.service }
                }
              ]
        }
      }
    ]
  }
}

output id string = vnet.id
output name string = vnet.name
output privateEndpointSubnetId string = '${vnet.id}/subnets/snet-private-endpoints'
output apimSubnetId string = '${vnet.id}/subnets/snet-apim-outbound'
output agentSubnetId string = '${vnet.id}/subnets/snet-foundry-agent'
output acaSubnetIds { *: string } = toObject(
  useCases,
  app => app.name,
  app => '${vnet.id}/subnets/snet-aca-${app.name}'
)
