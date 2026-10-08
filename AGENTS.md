# Repository Guidance

## Project

This repository is a Terraform module for deploying and experimenting with Azure resources. The root module is organized primarily as one `resource-*.tf` file per resource area; shared inputs, locals, data sources, generic outputs, and tags live in `variables.tf`, `locals.tf`, `data.tf`, `outputs.tf`, and `tags.tf` respectively. Examples are under `examples/`.

Create dedicated files for any new resource, as this repositoroy serves as the basis for specialist terraform modules, where the resource-*.tf file can simply be deleted, so resources specifc outputs should appear in the resource-tf file not in `outputs.tf` file.

Leverage AVM (Azure Verified Modules), where possible with azurerm as a fallback and azapi as a last resorce.

Where possible, leverage the msgraph provider in prefernce to the azuread provider.

## Editing

- Keep changes focused on the owning resource file and follow nearby naming, formatting, and module patterns. Reuse existing shared variables and locals where appropriate.
- Treat Terraform plans and outputs as user-facing interfaces: keep generated command examples clear and accurate, especially resource names, resource groups, and prerequisites.
- `README.md` contains a `terraform-docs` generated section between `BEGIN_TF_DOCS` and `END_TF_DOCS`. Edit the source Terraform documentation, then regenerate that section; do not hand-edit generated content.
- Do not commit credentials, secrets, state files, plans, or local `.tfvars` files. Never run `terraform apply` or make live Azure changes unless explicitly requested.
- Keep changes small and resource-scoped. Recent history favors focused resource updates, clarity fixes, and separate generated-doc updates.

## Validation

The repository CI runs these checks from the repository root:

```sh
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

The documentation workflow also runs `terraform-docs` and updates the generated README section. There is no configured Go test module or active Go test suite evident in the repository; `tests/main_test.go` currently contains only a commented command.

## Relase

As this is experimental, commit changes directly to the main branch and publish changes as per the process outlined in .github\workflows\module-release.yml

## Every 

End every reply with 'Checked against AGENTS.md'

