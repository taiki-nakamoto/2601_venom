provider "aws" {
  region = "ap-northeast-1"
}

# --- 1. Network: VPC, Subnets, IGW ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "woodpecker-test-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"
}

resource "aws_subnet" "private_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-northeast-1c"
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- 2. Security Groups ---
resource "aws_security_group" "ec2_sg" {
  name   = "woodpecker-ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # テスト用のため全解放
    description = "SSH"
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # テスト用のため全解放
    description = "Woodpecker UI"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name   = "woodpecker-db-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }
}

# --- 3. Aurora Serverless v2 (PostgreSQL 16.10) ---
resource "aws_db_subnet_group" "main" {
  name       = "woodpecker-db-subnet"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_c.id]
}

resource "aws_rds_cluster" "postgresql" {
  cluster_identifier      = "woodpecker-db-cluster"
  engine                  = "aurora-postgresql"
  engine_mode             = "provisioned" # Serverless v2はこのモード
  engine_version          = "16.10"       # 2025年最新安定版
  database_name           = "testdb"
  master_username         = "postgres"
  master_password         = "password123" # 検証用のため簡易設定
  skip_final_snapshot     = true
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db_sg.id]

  serverlessv2_scaling_configuration {
    max_capacity = 1.0
    min_capacity = 0.0 # 自動停止設定
  }
}

resource "aws_rds_cluster_instance" "postgresql_instance" {
  cluster_identifier = aws_rds_cluster.postgresql.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.postgresql.engine
  engine_version     = aws_rds_cluster.postgresql.engine_version
}

# --- 4. EC2 (Woodpecker Host) ---
# 最新のAmazon Linux 2023 AMIを取得
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_eip" "woodpecker_ip" {
  instance = aws_instance.woodpecker_server.id
}

resource "aws_instance" "woodpecker_server" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker git
              systemctl enable --now docker
              # Docker Composeインストール
              curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose
              EOF

  tags = { Name = "woodpecker-server" }
}

# --- 5. API Gateway (Mock) ---
resource "aws_api_gateway_rest_api" "mock_api" {
  name        = "woodpecker-mock-api"
  description = "Mock API for Venom testing"
}

# /users リソース
resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id
  parent_id   = aws_api_gateway_rest_api.mock_api.root_resource_id
  path_part   = "users"
}

# /users/{id} リソース
resource "aws_api_gateway_resource" "user_id" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id
  parent_id   = aws_api_gateway_resource.users.id
  path_part   = "{id}"
}

# GET /users/{id} メソッド
resource "aws_api_gateway_method" "get_user" {
  rest_api_id   = aws_api_gateway_rest_api.mock_api.id
  resource_id   = aws_api_gateway_resource.user_id.id
  http_method   = "GET"
  authorization = "NONE"
}

# Mock統合の設定
resource "aws_api_gateway_integration" "mock_integration" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id
  resource_id = aws_api_gateway_resource.user_id.id
  http_method = aws_api_gateway_method.get_user.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

# メソッドレスポンス（200 OK）
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id
  resource_id = aws_api_gateway_resource.user_id.id
  http_method = aws_api_gateway_method.get_user.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Content-Type" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# メソッドレスポンス（404 Not Found）
resource "aws_api_gateway_method_response" "response_404" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id
  resource_id = aws_api_gateway_resource.user_id.id
  http_method = aws_api_gateway_method.get_user.http_method
  status_code = "404"

  response_parameters = {
    "method.response.header.Content-Type" = true
  }
}

# 統合レスポンス（200 OK: ID 100の場合）
resource "aws_api_gateway_integration_response" "integration_response_200" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id
  resource_id = aws_api_gateway_resource.user_id.id
  http_method = aws_api_gateway_method.get_user.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  selection_pattern = ""

  response_templates = {
    "application/json" = jsonencode({
      id         = 100
      username   = "test_user_01"
      email      = "test@example.com"
      address    = "Tokyo, Japan"
      status     = "active"
      created_by = "setup_script"
      updated_by = "venom_test"
    })
  }

  response_parameters = {
    "method.response.header.Content-Type" = "'application/json'"
  }
}

# 統合レスポンス（404 Not Found: ID 100以外の場合）
resource "aws_api_gateway_integration_response" "integration_response_404" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id
  resource_id = aws_api_gateway_resource.user_id.id
  http_method = aws_api_gateway_method.get_user.http_method
  status_code = aws_api_gateway_method_response.response_404.status_code

  selection_pattern = "4\\d{2}"

  response_templates = {
    "application/json" = jsonencode({
      message = "User not found"
    })
  }

  response_parameters = {
    "method.response.header.Content-Type" = "'application/json'"
  }
}

# デプロイメント
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.mock_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.users.id,
      aws_api_gateway_resource.user_id.id,
      aws_api_gateway_method.get_user.id,
      aws_api_gateway_integration.mock_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.mock_integration,
    aws_api_gateway_integration_response.integration_response_200,
    aws_api_gateway_integration_response.integration_response_404,
  ]
}

# ステージ (dev)
resource "aws_api_gateway_stage" "dev" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.mock_api.id
  stage_name    = "dev"
}

# 出力: これを見てGitHub設定やDB接続を行う
output "woodpecker_public_ip" {
  value = aws_eip.woodpecker_ip.public_ip
}

output "db_endpoint" {
  value = aws_rds_cluster.postgresql.endpoint
}

output "ami_id" {
  description = "使用されたAmazon Linux 2023 AMI ID"
  value       = data.aws_ami.amazon_linux_2023.id
}

output "api_gateway_url" {
  description = "API Gateway Mock endpoint URL"
  value       = "${aws_api_gateway_stage.dev.invoke_url}/users"
}
