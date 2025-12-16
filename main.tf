locals {
  vpc_cidr    = "10.0.0.0/16"
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
  tags = {
    ManagedBy = "Terraform"
    Terraform = "true"
    Environment = "dev"
  }
}

data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "available" {}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "alb-vpc"
  cidr = local.vpc_cidr
  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]

  tags = local.tags
}

module "blog-asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.0.2"

  name     = "blog-asg"
  min_size = 1
  max_size = 2

  vpc_zone_identifier         = module.blog_vpc.public_subnets
  security_groups             = [module.blog_sg.security_group_id]
  
  traffic_source_attachments = {
    blog-alb = {
      traffic_source_identifier = module.blog_alb.target_groups["ex-asg"].arn
      traffic_source_type       = "elbv2" # default
    }
  }

  image_id      = data.aws_ami.app_ami.id
  instance_type = var.instance_type
  tags = local.tags
}

module "blog_alb" {
  source = "terraform-aws-modules/alb/aws"

  name            = "blog-alb"
  vpc_id          = module.blog_vpc.vpc_id
  subnets         = module.blog_vpc.public_subnets
  security_groups = [module.blog_sg.security_group_id]
  enable_deletion_protection = false
  
  listeners = {
    ex-http = {
      port               = 80
      protocol           = "HTTP"
      forward            = {
        target_group_key = "ex-asg"
      }
    }
  }

  target_groups = {
    ex-asg = {
      name_prefix      = "blog-"
      protocol         = "HTTP"
      port             = 80
      vpc_id           = module.blog_vpc.vpc_id
      create_attachment = false
    }
  }

  tags = local.tags
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1"
  name    = "blog"

  vpc_id = module.blog_vpc.vpc_id

  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}
