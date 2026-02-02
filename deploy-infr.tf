terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# ---------------------------
# VPC
# ---------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "test-vpc"
  }
}

# ---------------------------
# Public Subnet
# ---------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-1a"

  tags = {
    Name = "test-public-subnet"
  }
}

# ---------------------------
# Internet Gateway
# ---------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "test-igw"
  }
}

# ---------------------------
# Route Table
# ---------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "test-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------
# IAM Role for Lambda
# ---------------------------
resource "aws_iam_role" "lambda_role" {
  name = "test-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role      = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------
# Dummy Lambda Package
# ---------------------------
data "archive_file" "dummy" {
  type        = "zip"
  output_path = "dummy-lambda.zip"

  source {
    content  = "exports.handler = async () => ({ statusCode: 200, body: 'OK' });"
    filename = "index.js"
  }
}

# ---------------------------
# Lambda Function
# ---------------------------
resource "aws_lambda_function" "test_lambda" {
  function_name = "test-lambda"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "java17" # you will replace code later
  handler       = "com.example.Handler::handleRequest"

  filename         = data.archive_file.dummy.output_path
  source_code_hash = data.archive_file.dummy.output_base64sha256

  timeout = 30
  memory_size = 512

  tags = {
    Name = "test-lambda"
  }
}

# ---------------------------
# PUBLIC Lambda URL (NO AUTH)
# ---------------------------
resource "aws_lambda_function_url" "public_url" {
  function_name      = aws_lambda_function.test_lambda.function_name
  authorization_type = "NONE"
}

# ---------------------------
# Permission for public invoke
# ---------------------------
resource "aws_lambda_permission" "public_invoke" {
  statement_id  = "AllowPublicInvoke"
  action        = "lambda:InvokeFunctionUrl"
  function_name = aws_lambda_function.test_lambda.function_name
  principal     = "*"
  function_url_auth_type = "NONE"
}

# ---------------------------
# Output
# ---------------------------
output "lambda_public_url" {
  value = aws_lambda_function_url.public_url.function_url
}
