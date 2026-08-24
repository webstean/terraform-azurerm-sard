# terraform-azurerm-sard

Simple Azure Resources Deployment

## Usage

```hcl
module "sard" {
  source  = "webstean/sard/azurerm"
  version = "~> 1.0"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~>2.0, < 3.0 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | ~>3.0, < 4.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~>4.0, < 5.0 |
| <a name="requirement_msgraph"></a> [msgraph](#requirement\_msgraph) | ~> 0.0, < 1.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~>3.0, < 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~>4.0, < 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_resource_provider_feature_registration.encryption_at_host](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_provider_feature_registration) | resource |

## Inputs

No inputs.

## Outputs

No outputs.
<!-- END_TF_DOCS -->

## Examples

- [Basic](./examples/basic)
- [Complete](./examples/complete)

## Contributing

Contributions welcome. Please open an issue or PR.

## License

MIT
