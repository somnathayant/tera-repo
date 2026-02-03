terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# ---------------------------
# AWS Provider (us-east-1)
# ---------------------------
provider "aws" {
  region = "us-east-1"
}

# ---------------------------
# IAM Role for Lambda
# ---------------------------
resource "aws_iam_role" "lambda_role" {
  name = "api-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# ---------------------------
# Basic Lambda Execution Logs
# ---------------------------
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------
# Custom S3 Access Policy
# ---------------------------
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda-s3-access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::*",
          "arn:aws:s3:::*/*"
        ]
      }
    ]
  })
}

# ---------------------------
# Dummy Lambda package
# ---------------------------
data "archive_file" "dummy" {
  type        = "zip"
  output_path = "dummy-lambda.zip"

  source {
    filename = "index.js"
    content  = <<EOF
exports.handler = async () => {
  return {
    statusCode: 200,
    body: "Hello from Lambda via API Gateway (us-east-1)"
  };
};
EOF
  }
}

# ---------------------------
# Lambda Function
# ---------------------------
resource "aws_lambda_function" "api_lambda" {
  function_name = "test-api-lambda"
  role          = aws_iam_role.lambda_role.arn

  runtime = "java17"
  handler = "com.example.Handler::handleRequest"

  filename         = data.archive_file.dummy.output_path
  source_code_hash = data.archive_file.dummy.output_base64sha256

  timeout     = 30
  memory_size = 512
}

# ---------------------------
# API Gateway (HTTP API)
# ---------------------------
resource "aws_apigatewayv2_api" "http_api" {
  name          = "test-http-api"
  protocol_type = "HTTP"
}

# ---------------------------
# Lambda Integration
# ---------------------------
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                  = aws_apigatewayv2_api.http_api.id
  integration_type        = "AWS_PROXY"
  integration_uri         = aws_lambda_function.api_lambda.invoke_arn
  payload_format_version  = "2.0"
}

# ---------------------------
# Route
# ---------------------------
resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# ---------------------------
# Stage
# ---------------------------
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# ---------------------------
# Permission for API Gateway
# ---------------------------
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# ---------------------------
# Output Public URL
# ---------------------------
output "api_gateway_url" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}
