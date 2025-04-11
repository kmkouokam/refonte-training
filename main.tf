#----------------------------------------------------------
#
#
# Provision:
#  - VPC
#  - Internet Gateway
#  - XX Public Subnets
#  - XX Private Subnets
#  - XX NAT Gateways in Public Subnets to give Internet access from Private Subnets
#
# Developed by Ernestine D Motouom
#----------------------------------------------------------





data "aws_availability_zones" "available" {}

#-------------VPC and Internet Gateway------------------------------------------
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags       = merge(var.tags, { Name = "${var.env}-vpc" })
}


resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.env}-igw" })
}

#-------------Public Subnets and Routing----------------------------------------
resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "${var.env}-public-${count.index + 1}" })
}


resource "aws_route_table" "public_subnets" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(var.tags, { Name = "${var.env}-route-public-subnets" })
}


resource "aws_route_table_association" "public_routes" {
  count          = length(aws_subnet.public_subnets[*].id)
  route_table_id = aws_route_table.public_subnets.id
  subnet_id      = aws_subnet.public_subnets[count.index].id
}


#-----NAT Gateways with Elastic IPs--------------------------
resource "aws_eip" "nat" {
  count  = length(var.private_subnet_cidrs)
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.env}-nat-gw-${count.index + 1}" })
}


resource "aws_nat_gateway" "nat" {
  count         = length(var.private_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id
  tags          = merge(var.tags, { Name = "${var.env}-nat-gw-${count.index + 1}" })
}

#--------------Private Subnets and Routing-------------------------
resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = merge(var.tags, { Name = "${var.env}-private-${count.index + 1}" })
}


resource "aws_route_table" "private_subnets" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }
  tags = merge(var.tags, { Name = "${var.env}-route-private-subnet-${count.index + 1}" })
}


resource "aws_route_table_association" "private_routes" {
  count          = length(aws_subnet.private_subnets[*].id)
  route_table_id = aws_route_table.private_subnets[count.index].id
  subnet_id      = aws_subnet.private_subnets[count.index].id
}


# Backend SG

resource "aws_security_group" "backend" {

  name        = "backend"
  description = "Allow inbound traffic"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    #description = "TLS from VPC"
    for_each = ["3306", "5432", ]
    content {
      from_port = ingress.value
      to_port   = ingress.value
      protocol  = "tcp"

      cidr_blocks = ["0.0.0.0/0"]

    }

  }

  // allows traffic from the SG itself
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]

  }

  tags = {
    Name = "backend_sg"
  }
}




terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }

    random = {
      source = "hashicorp/random"
    }

    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}

# Generate password for mysql

resource "random_password" "mysql_password" {
  length           = 12
  special          = false
  override_special = "!#$%&*()-_+{}<>?"
}


# Store password
resource "aws_ssm_parameter" "mysql_password" {
  name        = "/production/mysql/password"
  description = "The parameter description"
  type        = "SecureString"
  value       = random_password.mysql_password.result

  tags = {
    environment = "production"
  }
}


# Retrieved Password
data "aws_ssm_parameter" "mysql_password" {
  name       = "/production/mysql/password"
  depends_on = [aws_ssm_parameter.mysql_password]
}

//DB subnet_group

resource "aws_db_subnet_group" "db_sub_group" {
  count       = length(var.private_subnet_cidrs)
  name_prefix = "db_sub_group"
  subnet_ids  = aws_subnet.private_subnets[*].id

  tags = {
    Name = "My DB subnet group-${count.index + 1}"
  }

  depends_on = [aws_subnet.private_subnets, aws_vpc.main]

}

#Mysql db

resource "aws_db_instance" "mysql_db" {
  count                = length(var.private_subnet_cidrs)
  allocated_storage    = 10
  db_name              = "accounts"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  skip_final_snapshot  = true
  apply_immediately    = true
  identifier           = "refonte-${count.index + 1}"
  username             = "admin"
  password             = random_password.mysql_password.result
  parameter_group_name = "default.mysql8.0"
  db_subnet_group_name = aws_db_subnet_group.db_sub_group[count.index].name

  vpc_security_group_ids = [
    aws_security_group.backend.id
  ]
  port = 3306


  tags = {
    Name = "mysql_db-${count.index + 1}"
  }
  depends_on = [aws_db_subnet_group.db_sub_group, aws_security_group.backend]

}


data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}



# IAM Role for Lambda
resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name = "iam_for_lambda"
  }
}

resource "aws_iam_policy_attachment" "lambda_basic_execution" {
  name       = "attach-basic-exec-policy"
  roles      = [aws_iam_role.iam_for_lambda.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy_attachment" "lambda_vpc_execution" {
  name       = "attach-basic-exec-policy"
  roles      = [aws_iam_role.iam_for_lambda.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_policy_attachment" "lambda_rds_execution" {
  name       = "attach-basic-exec-policy"
  roles      = [aws_iam_role.iam_for_lambda.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }


}

resource "aws_iam_role_policy" "vpc_access" {
  name = "LambdaVPCAccessPolicy"
  role = aws_iam_role.iam_for_lambda.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs",
          "ec2:getSecurityGroupsForVpc",
          "logs:DescribeLogGroups",
          "logs:StartLiveTail",
          "logs:StopLiveTail",


        ],
        Resource = "*",
        "Condition" : {
          "ArnEquals" : {
            "lambda:SourceFunctionArn" : [
              "arn:aws:lambda:us-east-1:435329769674:function:function.zip"
            ]
          }
        }
      }
    ]
  })
}


/*
resource "aws_iam_role" "ec2_role" {
  name               = "vpro-aws-elasticbeanstalk-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchFullAccess",
    "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier",
    "arn:aws:iam::aws:policy/AdministratorAccess-AWSElasticBeanstalk",
    "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkRoleSNS",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"

  ]


}



resource "aws_iam_instance_profile" "instance_profile" {

  name = "vpro-aws-elasticbeanstalk-ec2-role"
  role = aws_iam_role.ec2_role.name
}

*/

resource "aws_security_group" "lambda_sg" {
  name        = "lambda_sg"
  description = "Allow Lambda outbound"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Lambda_sg"
  }
}

resource "aws_lambda_function" "hello_world" {
  count            = length(var.private_subnet_cidrs)
  function_name    = "HelloWorldFunction-${count.index + 1}"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  filename         = "function.zip"
  source_code_hash = filebase64sha256("function.zip")

  vpc_config {
    subnet_ids         = [aws_subnet.private_subnets[count.index].id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

resource "aws_cloudwatch_log_group" "refonte_log_group" {
  retention_in_days = 14
  name              = "refonte_log_group"
}

resource "aws_cloudwatch_log_stream" "refonte_log_stream" {
  name           = "refonte_log_stream"
  log_group_name = aws_cloudwatch_log_group.refonte_log_group.name
}
