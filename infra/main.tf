terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#####################################
# Variables (multi-line, safe style)
#####################################
variable "project" {
  type    = string
  default = "wisam-webapp"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.10.1.0/24", "10.10.2.0/24"]
}

variable "key_name" {
  type    = string
  default = "wisam-key"
}

variable "my_ip_cidr" {
  type    = string
  default = "0.0.0.0/0" # replace with YOUR.IP/32 for SSH
}

variable "app_image" {
  type    = string
  default = "nginxdemos/hello:latest"
}

variable "container_port" {
  type    = number
  default = 80
}

variable "container_env" {
  type    = map(string)
  default = { ENV = "prod" }
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "desired_cap" {
  type    = number
  default = 2
}

variable "min_cap" {
  type    = number
  default = 2
}

variable "max_cap" {
  type    = number
  default = 4
}

provider "aws" {
  region = var.aws_region
}

############################
# VPC + public subnets
############################
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "public" {
  for_each                = { a = var.public_subnets[0], b = var.public_subnets[1] }
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}${each.key}"
  tags                    = { Name = "${var.project}-public-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

############################
# Security groups
############################
resource "aws_security_group" "alb_sg" {
  name   = "${var.project}-alb-sg"
  vpc_id = aws_vpc.this.id

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

  tags = { Name = "${var.project}-alb-sg" }
}

resource "aws_security_group" "ec2_sg" {
  name   = "${var.project}-ec2-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    description     = "App from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-ec2-sg" }
}

############################
# ALB + target group + listener
############################
resource "aws_lb" "app" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for s in aws_subnet.public : s.id]
  tags               = { Name = "${var.project}-alb" }
}

resource "aws_lb_target_group" "app_tg" {
  name        = "${var.project}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id

  health_check {
    path                = "/"
    port                = var.container_port
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
    matcher             = "200-399"
  }

  tags = { Name = "${var.project}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

############################
# Launch template (Docker)
############################
data "aws_ami" "al2023" {
  owners      = ["137112412989"] # Amazon
  most_recent = true
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

locals {
  env_exports = join("\n", [for k, v in var.container_env : "export ${k}='${v}'"])
}

resource "aws_launch_template" "lt" {
  name_prefix            = "${var.project}-lt-"
  image_id               = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf -y update
    dnf -y install docker
    systemctl enable --now docker

    ${local.env_exports}

    docker run -d --restart=always \
      -p ${var.container_port}:${var.container_port} \
      --name app "${var.app_image}"
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project}-app" }
  }
}

############################
# Auto Scaling Group
############################
resource "aws_autoscaling_group" "asg" {
  name                = "${var.project}-asg"
  max_size            = var.max_cap
  min_size            = var.min_cap
  desired_capacity    = var.desired_cap
  vpc_zone_identifier = [for s in aws_subnet.public : s.id]
  health_check_type   = "EC2"
  target_group_arns   = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-app"
    propagate_at_launch = true
  }
}

############################
# Outputs
############################
output "alb_dns_name" {
  description = "Public URL of the load balancer"
  value       = aws_lb.app.dns_name
}
