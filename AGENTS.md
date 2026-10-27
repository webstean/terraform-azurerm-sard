# Repository Guidance

## Project

This repository is a Terraform module for deploying and experimenting with Azure resources. The root module is organized primarily as one `resource-*.tf` file per resource area; shared inputs, locals, data sources, generic outputs, and tags live in `variables.tf`, `locals.tf`, `data.tf`, `outputs.tf`, and `tags.tf` respectively. Examples are under `examples/`. When adding or changing a resource, update the matching example under `examples/` if one exists, and do not create new examples unless requested.

Create a dedicated `resource-*.tf` file for each new resource. Keep changes to an existing resource focused on its owning file; do not put a new resource in an unrelated existing resource file. This repository serves as the basis for specialist Terraform modules, where a `resource-*.tf` file can simply be deleted, so resource-specific outputs should appear in that resource file, not in `outputs.tf`.

For each resource, first use the AVM module if one exists for that resource type. If none exists, use a native azurerm resource. Use azapi only when the resource or property is not supported by azurerm.

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

If `terraform fmt -check` fails, run `terraform fmt -recursive` and check again. If `terraform validate` fails, fix the reported errors in the owning resource file and rerun the full validation sequence. Do not suppress errors or skip checks.

The documentation workflow also runs `terraform-docs` and updates the generated README section. There is no configured Go test module or active Go test suite evident in the repository; `tests/main_test.go` currently contains only a commented command.

## Release

As this is experimental, commit changes directly to the main branch. Publish changes by following the steps in `.github/workflows/module-release.yml`. Summarize the steps you will perform before running any publish command, and do not trigger a release unless the user asks for one.

## AVM Documentation

For AVM module inputs, outputs, and usage, fetch and read https://azure.github.io/Azure-Verified-Modules/llms.txt (llms.txt format). Use it as the source of truth for AVM parameter names and defaults.

## Every

End every reply with '✅ Checked against AGENTS.md'
