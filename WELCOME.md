# Welcome to Your Terraform Module

This repository was scaffolded to help you build and publish a reusable Terraform module with a clean structure and CI-ready defaults.

## What's Included

- Module entry files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- Examples: `examples/basic` and `examples/complete`
- Validation and docs workflow in `.github/workflows`
- Formatting and editor standards via `.editorconfig` and `.gitattributes`

## Quick Start

1. Review and update module inputs in `variables.tf`
2. Implement resources in `main.tf`
3. Add outputs in `outputs.tf`
4. Test examples from `examples/basic` and `examples/complete`

## Useful Commands

```bash
terraform fmt -recursive
terraform init
terraform validate
```

## Next Steps

- Update GitHub secrets for CI:
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
- Create a release tag when ready to publish
- Keep README docs in sync with `terraform-docs`

Happy building.
