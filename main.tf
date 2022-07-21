provider "aws" {
}

variable "bot_token" {
  type = string
  sensitive = true
}

resource "random_id" "id" {
  byte_length = 8
}

resource "aws_ssm_parameter" "value" {
  name  = "parameter_${random_id.id.hex}"
  type  = "String"
  value = var.bot_token
}

resource "aws_iam_role" "appsync" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "appsync.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "appsync" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
  statement {
    actions = [
      "ssm:GetParameter"
    ]
    resources = [
			aws_ssm_parameter.value.arn
    ]
  }
}

resource "aws_iam_role_policy" "appsync" {
  role   = aws_iam_role.appsync.id
  policy = data.aws_iam_policy_document.appsync.json
}

resource "aws_appsync_graphql_api" "appsync" {
  name                = "appsync_test"
  schema              = file("schema.graphql")
  authentication_type = "AWS_IAM"
  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync.arn
    field_log_level          = "ALL"
  }
}

resource "aws_cloudwatch_log_group" "loggroup" {
  name              = "/aws/appsync/apis/${aws_appsync_graphql_api.appsync.id}"
  retention_in_days = 14
}

data "aws_arn" "ssm_parameter" {
  arn = aws_ssm_parameter.value.arn
}

resource "aws_appsync_datasource" "parameter_store" {
  api_id           = aws_appsync_graphql_api.appsync.id
  name             = "ssm"
  service_role_arn = aws_iam_role.appsync.arn
  type             = "HTTP"
	http_config {
		endpoint = "https://ssm.${data.aws_arn.ssm_parameter.region}.amazonaws.com"
		authorization_config {
			authorization_type = "AWS_IAM"
			aws_iam_config {
				signing_region = data.aws_arn.ssm_parameter.region
				signing_service_name = "ssm"
			}
		}
	}
}

resource "aws_appsync_datasource" "telegram" {
  api_id           = aws_appsync_graphql_api.appsync.id
  name             = "telegram"
  type             = "HTTP"
	http_config {
		endpoint = "https://api.telegram.org"
	}
}

# resolvers
resource "aws_appsync_function" "get_secret" {
  api_id      = aws_appsync_graphql_api.appsync.id
  data_source = aws_appsync_datasource.parameter_store.name
  name = "getSecret"
	request_mapping_template = <<EOF
{
	"version": "2018-05-29",
	"method": "POST",
	"params": {
		"headers": {
			"Content-Type" : "application/x-amz-json-1.1",
			"X-Amz-Target" : "AmazonSSM.GetParameter"
		},
		"body": {
			"Name": "${aws_ssm_parameter.value.name}",
			"WithDecryption": true
		}
	},
	"resourcePath": "/"
}
EOF

	response_mapping_template = <<EOF
#if ($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
#if ($ctx.result.statusCode < 200 || $ctx.result.statusCode >= 300)
	$util.error($ctx.result.body, "StatusCode$ctx.result.statusCode")
#end
$util.toJson($util.parseJson($ctx.result.body).Parameter.Value)
EOF
}

resource "aws_appsync_function" "send_message" {
  api_id      = aws_appsync_graphql_api.appsync.id
  data_source = aws_appsync_datasource.telegram.name
  name = "sendMessage"
	request_mapping_template = <<EOF
{
	"version": "2018-05-29",
	"method": "POST",
	"params": {
		"headers": {
			"Content-Type" : "application/json"
		},
		"body": {
			"chat_id": $util.toJson($ctx.args.chat_id),
			"text": $util.toJson($ctx.args.message)
		}
	},
	"resourcePath": "/bot$ctx.prev.result/sendMessage"
}
EOF

	response_mapping_template = <<EOF
#if ($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
#if ($ctx.result.statusCode < 200 || $ctx.result.statusCode >= 300)
	$util.error($ctx.result.body, "StatusCode$ctx.result.statusCode")
#end
#if (!$util.parseJson($ctx.result.body).ok)
	$util.error($ctx.result.body)
#end
$util.toJson($util.parseJson($ctx.result.body).result.message_id)
EOF
}

resource "aws_appsync_function" "get_me" {
  api_id      = aws_appsync_graphql_api.appsync.id
  data_source = aws_appsync_datasource.telegram.name
  name = "getMe"
	request_mapping_template = <<EOF
{
	"version": "2018-05-29",
	"method": "POST",
	"params": {
		"headers": {
			"Content-Type" : "application/json"
		},
		"body": {
		}
	},
	"resourcePath": "/bot$ctx.prev.result/getMe"
}
EOF

	response_mapping_template = <<EOF
#if ($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
#if ($ctx.result.statusCode < 200 || $ctx.result.statusCode >= 300)
	$util.error($ctx.result.body, "StatusCode$ctx.result.statusCode")
#end
#if (!$util.parseJson($ctx.result.body).ok)
	$util.error($ctx.result.body)
#end
$util.toJson($util.parseJson($ctx.result.body).result)
EOF
}

resource "aws_appsync_resolver" "Mutation_sendMessage" {
  api_id      = aws_appsync_graphql_api.appsync.id
  type        = "Mutation"
  field       = "sendMessage"
  request_template  = "{}"
  response_template = "$util.toJson($ctx.result)"
  kind              = "PIPELINE"
  pipeline_config {
    functions = [
      aws_appsync_function.get_secret.function_id,
      aws_appsync_function.send_message.function_id,
    ]
  }
}

resource "aws_appsync_resolver" "Query_me" {
  api_id      = aws_appsync_graphql_api.appsync.id
  type        = "Query"
  field       = "me"
  request_template  = "{}"
  response_template = "$util.toJson($ctx.result)"
  kind              = "PIPELINE"
  pipeline_config {
    functions = [
      aws_appsync_function.get_secret.function_id,
      aws_appsync_function.get_me.function_id,
    ]
  }
}
