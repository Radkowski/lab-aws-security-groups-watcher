variable "DEPLOYMENTPREFIX" {}
variable "REGION" {}
variable "LAMBDA_DETAILS" {}


resource "aws_cloudwatch_event_rule" "detect-SG-changes" {
  name        = join("", [var.DEPLOYMENTPREFIX, "-rule"])
  description = "Invoke lambda once security group change is detected"
  event_pattern = jsonencode({
    "source" : ["aws.ec2"],
    "detail-type" : ["AWS API Call via CloudTrail"],
    "detail" : {
      "eventSource" : ["ec2.amazonaws.com"],
      "eventName" : ["AuthorizeSecurityGroupIngress", "ModifySecurityGroupRules"]
  } })
}


resource "aws_cloudwatch_event_target" "invokelambda" {
  rule      = aws_cloudwatch_event_rule.detect-SG-changes.name
  target_id = join("", [var.DEPLOYMENTPREFIX, "-invokelambda"])
  arn       = var.LAMBDA_DETAILS.arn
}


resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowInvocationFromEventbridge"
  action        = "lambda:InvokeFunction"
  function_name = var.LAMBDA_DETAILS.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.detect-SG-changes.arn
}


resource "aws_cloudwatch_log_group" "lambda-log-group" {
  name              = join("", ["/aws/lambda/", var.DEPLOYMENTPREFIX, "-SG-watcher"])
  retention_in_days = 14
}
