# Builds an AzCopy runner entirely within ACR. The Dockerfile and task YAML
# are Terraform locals so no external Git context or access token is required.
locals {
  dab_image_repository = "${var.container_registry_login_server}/dab-broker"

  ## Environment variables:
  ##   dab_MSI_CLIENT_ID must be defined
  ##   SOURCE_URL must be defined, can be Blob or Azure Files
  ##   DESTINATION_URL must be defined can be Blob or Azure Files
  dab_entrypoint_script = <<-BASH
#!/usr/bin/env bash
set -euo pipefail
echo "Starting Azure Database API Builder..."
if [ -z "$${DATABASE_CONNECTION_STRING:-}" ]; then
  echo "FAILED:Environment variable: 'DATABASE_CONNECTION_STRING' is not set"
  exit 1
fi
if [ ! -f "dab-config.json" ]; then
  echo "WARNING:Configuration file 'dab-config.json' is not found"
  dab auto-config ${var.prefix} \
	--template.rest.enabled true \
	--template.graphql.enabled true \
	--template.cache.enabled true \
	--template.cache.ttl-seconds 30 \
	--template.cache.level L1L2 \
 	--permissions "anonymous:read"
  exec DAB_ENVIRONMENT=${var.prefix} dab start
  exit 0
else
  echo "INFO:Configuration file dab-config.json found"
  exec DAB_ENVIRONMENT=${var.prefix} dab start
fi
BASH

  dab_dockerfile = <<-DOCKERFILE
ARG BASE_IMAGE=mcr.microsoft.com/azure-databases/data-api-builder:latest
FROM $${BASE_IMAGE}
ENV DATABASE_CONNECTION_STRING=${local.sql_database_connection_free_encrypted}
COPY dab-config.json /App/dab-config.json
RUN
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
DOCKERFILE

  dab_task_yaml = yamlencode({
    version = "v1.1.0"
    steps = [
      {
        cmd = "bash -c \"printf '%s' '${base64encode(trimspace(local.dab_entrypoint_script))}' | base64 --decode > entrypoint.sh\""
      },
      {
        cmd = "bash -c \"printf '%s' '${base64encode(trimspace(local.dab_dockerfile))}' | base64 --decode > Dockerfile\""
      },
      {
        build = "-t ${local.dab_image_repository}:{{.Run.ID}} -t ${local.dab_image_repository}:latest -f Dockerfile ."
      },
      {
        push = ["${local.dab_image_repository}:{{.Run.ID}}", "${local.dab_image_repository}:latest"]
      }
    ]
  })
}

resource "azurerm_role_assignment" "registry_push" {
  scope                = var.container_registry_id
  role_definition_name = "ACRPush"
  principal_id         = azurerm_user_assigned_identity.environment.id
  description          = local.iac_message
}

resource "azurerm_container_registry_task" "dab_build" {
  name                  = "build-azcopy-runner"
  container_registry_id = var.container_registry_id

  enabled = true
  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.environment.id
    ]
  }

  platform {
    os = "Linux"
  }

  encoded_step {
    task_content = base64encode(local.dab_task_yaml)
  }

  # Rebuild weekly on Sunday at 00:00 UTC to pick up base-image and package updates.
  timer_trigger {
    name     = "weekly-dab-runner-build"
    schedule = "0 0 * * 0"
    enabled  = true
  }

  timeout_in_seconds = 900
  tags               = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  depends_on = [
    azurerm_role_assignment.registry_push
  ]
}

# Changes on every plan so the immediate-run resource is recreated on every apply.
resource "terraform_data" "dab_build_apply_trigger" {
  triggers_replace = [timestamp()]
}

# Triggers a build on every Terraform apply.
resource "azurerm_container_registry_task_schedule_run_now" "dab_build_now" {
  container_registry_task_id = azurerm_container_registry_task.dab_build.id
  lifecycle {
    replace_triggered_by = [terraform_data.dab_build_apply_trigger]
  }
}

/*
REST: http://localhost:5000/api/Book
GraphQL: http://localhost:5000/graphql
Swagger: http://localhost:5000/swagger
Health: http://localhost:5000/health
*/


/*
dab auto-config my-def \
	--patterns.include "dbo.%" \
	--patterns.exclude "dbo.internal%" \
	--patterns.name "{schema}_{object}" \
	--permissions "anonymous:read"

dab auto-config my-def \
	--template.rest.enabled true \
	--template.graphql.enabled true \
	--template.cache.enabled true \
	--template.cache.ttl-seconds 30 \
	--template.cache.level L1L2
*/
