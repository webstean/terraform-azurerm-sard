locals {
  ## A maximum of 15 tags are allowed with keys no longer than 512 and 
  ## values no longer than 256 characters.
  permanent_tags = {
    customer    = var.customer
    prefix      = var.prefix
    type        = "permanent" ## permanent, temporary (can be safely deleted and recreated, to save cost)
    owner_email = var.owner_email
    ## Personal Identifiable Data
    data_PII = var.data_pii
    ## Personal Health Information
    data_PHI = var.data_phi
    #    env         = var.environment_name
    #    criticality = var.environment_crticiality
    createdby = "terraform"
    ## 24-7         : 24x7 monitoring
    ## 8-5          : business hours
    ## not-monitored: not monitored
    monitoring = "not monitored"
    created    = formatdate("DD/MM/YYYY", timestamp())
    //    terraform_version = data.local_file.terraform_version.content
  }

  temporary_tags = {
    customer    = var.customer
    prefix      = var.prefix
    type        = "temporary" ## permanent, temporary (can be safely deleted and recreated, to save cost)
    owner_email = var.owner_email
    ## Personal Identifiable Data
    data_PII = var.data_pii
    ## Personal Health Information
    data_PHI = var.data_phi
    #    env         = var.environment_name
    #    criticality = var.environment_crticiality
    createdby = "terraform"
    ## 24-7         : 24x7 monitoring
    ## 8-5          : business hours
    ## not-monitored: not monitored
    monitoring = "not monitored"
    created    = formatdate("DD/MM/YYYY", timestamp())
    //    terraform_version = data.local_file.terraform_version.content
  }
}

locals {
  ## DNS SOE Record tags
  dns_tags_private = {
    type = "private" ## private, public
    use  = "private-eendpoints"
  }
}

/*
 tags = merge(
    local.temporary_tags_default,
    {
      ## Monitoring
      ## 24-7         : 24x7 monitoring
      ## 8-5          : business hours
      ## not-monitored: not monitored
      monitoring = "not-monitored"

      ## Data Goverance
      ## Public Data
      data_public = "no"
      ## Personal Identifiable Data
      data_PII = "yes"
      ## Personal Health Information
      data_PHI = "no"
    },
  )
  lifecycle {
    ignore_changes = [tags.created]
  }
*/
