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

variable "my_ip_cidr" {
  type    = string
  default = "0.0.0.0/0" # tighten later
}

variable "container_port" {
  type    = number
  default = 80
}

# Tag you pushed to ECR (e.g., v3)
variable "image_tag" {
  type    = string
  default = "v3"
}
