provider "aws" {
  region = local.region
}

locals {
  name              = "playground-${replace(basename(path.cwd), "_", "-")}"
  region            = "us-east-2"
  availability_zone = "${local.region}a"

  tags = {
    Example     = local.name
    Owner       = "carlos-cuellar-maravilla"
    Environment = "playground"
  }

}
################################################################################
# VPC Module
################################################################################


module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = local.name
  cidr = "10.0.0.0/16"

  azs              = ["${local.region}a", "${local.region}b", "${local.region}c"]
  public_subnets   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets  = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]


  create_database_subnet_route_table    = true
  create_elasticache_subnet_route_table = true
  create_redshift_subnet_route_table    = true

  enable_ipv6 = false

  enable_nat_gateway = true
  single_nat_gateway = false

  public_subnet_tags = {
    Name = "public-subnet"
  }

  public_subnet_tags_per_az = {
    "${local.region}a" = {
      "availability-zone" = "${local.region}a"
    }
  }

  tags = local.tags

  vpc_tags = {
    Name = "vpc-playground"
  }
}

################################################################################
# EC2 Module
################################################################################


module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 3.0"

  name = "ec2-playground"

  ami                    = "ami-02238ac43d6385ab3"
  instance_type          = "t2.micro"
  key_name               = "carlos-cuellar-maravilla"
  monitoring             = false
  vpc_security_group_ids = [module.security_group.security_group_id]
  subnet_id              = element(module.vpc.public_subnets, 0)

  tags = {
    Terraform   = "true"
    Environment = "playground"
  }
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = local.name
  description = "Security group for example usage with EC2 instance"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp", "all-icmp"]
  egress_rules        = ["all-all"]

  tags = local.tags
}

resource "aws_volume_attachment" "this" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.this.id
  instance_id = module.ec2_instance.id
}

resource "aws_ebs_volume" "this" {
  availability_zone = local.availability_zone
  size              = 1

  tags = local.tags
}