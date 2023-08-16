module "LAMBDA" {
  source           = "./lambda"
  DEPLOYMENTPREFIX = local.DEPLOYMENTPREFIX
  AUTHTAGS         = local.AUTHTAGS
  REGION           = local.REGION
  UPDATED_CIDR     = local.UPDATED_CIDR
  MODIFY_OR_DELETE = local.MODIFY_OR_DELETE
  SHIELD_TAG       = local.SHIELD_TAG
}


module "EVENT_BRIDGE" {
  source           = "./event_bridge"
  depends_on       = [module.LAMBDA]
  DEPLOYMENTPREFIX = local.DEPLOYMENTPREFIX
  REGION           = local.REGION
  LAMBDA_DETAILS   = module.LAMBDA.LAMBDA_DETAILS
}



output "DETAILS" {
  value = {
    lambda_arn = module.LAMBDA.LAMBDA_DETAILS["arn"]
    variables  = module.LAMBDA.LAMBDA_DETAILS["environment"]
  }
}

