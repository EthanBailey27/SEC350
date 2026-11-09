terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  # Point at my floci (Student B, port 4567) instead of real AWS
  endpoints {
    s3       = "http://localhost:4567"
    dynamodb = "http://localhost:4567"
    lambda   = "http://localhost:4567"
    iam      = "http://localhost:4567"
    ec2      = "http://localhost:4567"
    rds      = "http://localhost:4567"
  }

  # Use dummy credentials for local testing
  access_key = "test"
  secret_key = "test"

  # Skip real AWS validation
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # Required for S3 path-style access
  s3_use_path_style = true
}

# Create the S3 bucket
resource "aws_s3_bucket" "website" {
  bucket        = "my-course-website"
  force_destroy = true # my addition: destroy can empty the bucket first
}

# Enable versioning
resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure static website hosting
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "error.html"
  }
}

# Upload the local files to the bucket
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  source       = "${path.module}/site/index.html"
  source_hash  = filemd5("${path.module}/site/index.html")
  content_type = "text/html"
  depends_on   = [aws_s3_bucket_versioning.website] # my addition: wait for versioning
}

# The website configuration points error_document at this key
resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.website.id
  key          = "error.html"
  source       = "${path.module}/site/error.html"
  source_hash  = filemd5("${path.module}/site/error.html")
  content_type = "text/html"
  depends_on   = [aws_s3_bucket_versioning.website] # my addition: wait for versioning
}

# DynamoDB Table
resource "aws_dynamodb_table" "items" {
  name         = "CourseItems"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# IAM role for the Lambda execution
resource "aws_iam_role" "lambda" {
  name = "lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Lambda Function
resource "aws_lambda_function" "api" {
  function_name = "items-api"
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "lambda_function.lambda_handler"
  filename      = "${path.module}/lambda.zip"
}

# Look up the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-kernel-*-x86_64"]
  }
}

resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Allow HTTP"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.lab.key_name

  tags = {
    Name = "test-web"
  }
}

# Extra output (not in the lab) so I can find this instance's container
output "web_instance_id" {
  value = aws_instance.web.id
}

resource "aws_key_pair" "lab" {
  key_name   = "lab-key"
  public_key = file("${path.module}/lab-key.pub")
}

# Create a PostgreSQL database
resource "aws_db_instance" "postgres" {
  identifier     = "student-postgres"
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  db_name           = "appdb"
  username          = "admin"
  password          = "StudentPass123!"

  skip_final_snapshot = true
}

# Output the endpoint so you know where to connect
output "db_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

resource "aws_instance" "php" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web.id]

  # user_data runs inside the container at boot
  user_data = <<-EOF
              #!/bin/bash
              dnf install -y httpd php php-mysqlnd
              cat > /var/www/html/index.php <<'PHP'
              <?php
              echo "<h1>Hello from PHP " . phpversion() . " on Apache</h1>";
              ?>
              PHP
              mkdir -p /run/php-fpm
              /usr/sbin/php-fpm --nodaemonize &
              sleep 1
              sed -i 's/^Listen 80$/Listen 8080/' /etc/httpd/conf/httpd.conf
              /usr/sbin/httpd
              echo "PHP-APP-READY" > /tmp/php-ready
              EOF

  tags = {
    Name = "php-web"
  }
}

# Extra output (not in the lab) so I can find this instance's container
output "php_instance_id" {
  value = aws_instance.php.id
}
