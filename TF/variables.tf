data "aws_caller_identity" "current" {}

data "aws_region" "current" {}


locals {
  user_data        = fileexists("./config.yaml") ? yamldecode(file("./config.yaml")) : jsondecode(file("./config.json"))
  REGION           = local.user_data.Parameters.Region
  DEPLOYMENTPREFIX = local.user_data.Parameters.DeploymentPrefix
  AUTHTAGS         = local.user_data.Parameters.AuthTags
  UPDATED_CIDR     = local.user_data.Parameters.Updated_CIDR
  MODIFY_OR_DELETE = local.user_data.Parameters.Modify_or_Delete
  SHIELD_TAG       = local.user_data.Parameters.ShieldTag
}
