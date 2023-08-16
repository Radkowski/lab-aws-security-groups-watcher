data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


variable "DEPLOYMENTPREFIX" {}
variable "REGION" {}
variable "AUTHTAGS" {}
variable "UPDATED_CIDR" {}
variable "MODIFY_OR_DELETE" {}
variable "SHIELD_TAG" {}


locals {
  SHIELD_TAG_AS_STRING = join(",",
    [var.SHIELD_TAG["Active"] ? "True" : "False",
      var.SHIELD_TAG["Key"],
  var.SHIELD_TAG["Value"]])
  MODIFY_OR_DETELE_AS_BOOL = var.MODIFY_OR_DELETE ? "True" : "False"
}


resource "aws_iam_role" "lambda-role" {
  name = join("", [var.DEPLOYMENTPREFIX, "-lambda-role"])
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
  inline_policy {
    name = join("", [var.DEPLOYMENTPREFIX, "-lambda-policy"])

    policy = jsonencode({
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "log0",
          "Effect" : "Allow",
          "Action" : "logs:CreateLogGroup",
          "Resource" : join("", ["arn:aws:logs:", data.aws_region.current.name, ":", data.aws_caller_identity.current.account_id, ":*"])
        },
        {
          "Sid" : "log1",
          "Effect" : "Allow",
          "Action" : [
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          "Resource" : [
            join("", ["arn:aws:logs:", data.aws_region.current.name, ":", data.aws_caller_identity.current.account_id, ":", "log-group:/aws/lambda/", var.DEPLOYMENTPREFIX, "-SG-watcher:*"])
          ]
        },
        {
          "Sid" : "secgroups",
          "Effect" : "Allow",
          "Action" : [
            "ec2:DescribeSecurityGroups",
            "ec2:DescribeSecurityGroupRules",
            "ec2:ModifySecurityGroupRules",
            "ec2:RevokeSecurityGroupIngress"
          ],
          "Resource" : "*"
        }
      ]
    })
  }
}


data "archive_file" "lambda-code" {
  type        = "zip"
  output_path = "lambda-code.zip"
  source {
    content  = <<EOF
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def detect_rules (sec_group_id):
    ec2_client = boto3.client('ec2')
    response = ec2_client.describe_security_group_rules(
    Filters=[{'Name': 'group-id','Values': [sec_group_id]}])
    id_with_pub_access=[]
    for x in response['SecurityGroupRules']:
        try:
            if x['CidrIpv4'] == '0.0.0.0/0' and x['IsEgress'] == False:
                id_with_pub_access.append(x)
                logger.info ('Find ingress rule open to the world: '+ x['SecurityGroupRuleId'])
        except:
            pass
    return (id_with_pub_access)


def modify_rule(rule_info,new_cidr):
    ec2_client = boto3.client('ec2')
    rule_info['CidrIpv4'] = new_cidr
    try:
        response = ec2_client.modify_security_group_rules(
            GroupId=rule_info['GroupId'],
            SecurityGroupRules=[
                {
                    'SecurityGroupRuleId': rule_info['SecurityGroupRuleId'],
                    'SecurityGroupRule': {
                        'IpProtocol': rule_info['IpProtocol'],
                        'FromPort': rule_info['FromPort'],
                        'ToPort': rule_info['ToPort'],
                        'CidrIpv4': new_cidr,
                        'Description': 'some desc'
                                        }
                }])
        logger.info ('CHANGING: '+ str(rule_info['SecurityGroupRuleId']))
    except Exception as e: 
        logger.info('Cannot modify the rule '+ str(rule_info['SecurityGroupRuleId']))  
        return False
    return True


def delete_rule(rule_info):
    try:
        ec2_client = boto3.client('ec2')
        response = ec2_client.revoke_security_group_ingress(
            GroupId=rule_info['GroupId'],
            SecurityGroupRuleIds=[rule_info['SecurityGroupRuleId']])
        logger.info ('DELETING: '+ rule_info['SecurityGroupRuleId'])
    except Exception as e: 
        logger.error('Cannot delete the rule: '+ str(e))
        return False


def rule_commander(sec_group_id, new_cidr,modify_or_delete):
    for x in detect_rules(sec_group_id):
        if not (modify_rule(x,new_cidr)):
           if modify_or_delete:  
                delete_rule(x)
           else:
               logger.info (sec_group_id + ' cannot be deleted, modify_or_delete feature is not active')
    return 0


def tag_shield(sec_group_id,shield_tag):
    ec2_client = boto3.client('ec2')
    response = ec2_client.describe_security_groups(
    Filters=[
        {
            'Name': str('tag:'+shield_tag['key']),
            'Values': [
                str(shield_tag['value'])
            ]
        }
    ],
        GroupIds=[sec_group_id]
    )
    if (response['SecurityGroups']):
        logger.info (sec_group_id + ' is protected by ShieldTag. No changes are made.')
        return True
    else:
        logger.info (sec_group_id + ' is NOT protected by ShieldTag')
        return False


def id_selector (event):
    try:
        if event['detail']['eventName'] == "ModifySecurityGroupRules":
            return (event['detail']['requestParameters']['ModifySecurityGroupRulesRequest']['GroupId'])
        else:
            return (event['detail']['requestParameters']['groupId'])
    except Exception as e: 
        logger.error('Cannot get security group ID: '+ str(e))
        return False


def detect_self_actions (event):
    sts_client = boto3.client('sts')
    response = sts_client.get_caller_identity()
    if event['detail']['userIdentity']['arn'] == response['Arn']:
        logger.info('Self action detected, quitting ...')
        return True
    return False


def transform_param(input_param):
    result =  (input_param.split(','))
    shield_tag = {'active': False,
                'key':'alfa',
                'value': 'beta'}
    try:
        if ((result[0]) in ['True', 'False']):
            shield_tag['active'] = eval(result[0])
            logger.info('Running in ShieldTag mode: '+ str(shield_tag['active'])) 
        shield_tag['key'] = result[1]
        shield_tag['value'] = result[2]
    except Exception as e: 
        logger.error('Cannot transform security tag: '+ str(e))
        return False
    return (shield_tag)



def lambda_handler(event, context):
 
    new_cidr = os.environ['UPDATED_CIDR']
    modify_or_delete = eval(os.environ['MODIFY_OR_DELETE'])
    shield_tag = transform_param(os.environ['SHIELD_TAG'])
    
    if detect_self_actions(event):
        return 0

    security_group_id = id_selector(event)
    logger.info ('Change has been detected on ' + security_group_id + '. Progressing ...')

    if shield_tag['active']:
        if tag_shield(security_group_id,shield_tag):
            return 0

    rule_commander(security_group_id, new_cidr,modify_or_delete)
    return 0


EOF
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "lambda" {
  description      = "Lambda function to detect 0.0.0.0/0 ingress rules and modify/delete it."
  architectures    = ["arm64"]
  filename         = data.archive_file.lambda-code.output_path
  source_code_hash = data.archive_file.lambda-code.output_base64sha256
  role             = aws_iam_role.lambda-role.arn
  function_name    = join("", [var.DEPLOYMENTPREFIX, "-SG-watcher"])
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  timeout          = 60
  memory_size      = 128
  tags             = var.AUTHTAGS
  environment {
    variables = {
      UPDATED_CIDR     = var.UPDATED_CIDR
      MODIFY_OR_DELETE = local.MODIFY_OR_DETELE_AS_BOOL
      SHIELD_TAG       = local.SHIELD_TAG_AS_STRING
    }
  }
}



output "LAMBDA_DETAILS" {
  value = aws_lambda_function.lambda
}