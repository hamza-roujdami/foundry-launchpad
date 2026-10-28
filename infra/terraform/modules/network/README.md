# Network

A VNet, delegated subnets and NSGs for either the `ai_hub` or `ai_spokes` profile.
The hub owns shared private DNS zones; spokes reference those zones rather than
creating another authority. ACA subnet slots are stable and keyed by use case.

Cross-subscription peering and DNS links are composed in the root. Existing-network
mode skips this module entirely. See [inputs](variables.tf),
[outputs](outputs.tf) and the [root guide](../../README.md).
