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
  public_subnets   = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  private_subnets  = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
  database_subnets = ["10.0.30.0/24", "10.0.31.0/24", "10.0.32.0/24"]


  create_database_subnet_route_table    = true
  create_elasticache_subnet_route_table = false
  create_redshift_subnet_route_table    = false

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
  vpc_security_group_ids = [module.security_group_ec2.security_group_id]
  subnet_id              = element(module.vpc.public_subnets, 0)

  tags = {
    Terraform   = "true"
    Environment = "playground"
  }
}

module "security_group_ec2" {
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

################################################################################
# RDS Module
################################################################################

module "security_group_rds" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "${local.name}-security-group-rds"
  description = "Security group for RDS example"
  vpc_id      = module.vpc.vpc_id

  #ingress_cidr_blocks = "10.0.0.0/16"

  ingress_with_cidr_blocks = [
    {
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      description = "Ingress-sg"
      cidr_blocks = "10.0.0.0/16"
    }]
   egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      description = "Egress-sg"
      cidr_blocks = "0.0.0.0/0"
    }]

  tags = local.tags
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier = local.name

  # All available versions: http://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_MySQL.html#MySQL.Concepts.VersionMgmt
  engine               = "mysql"
  engine_version       = "8.0"
  family               = "mysql8.0" # DB parameter group
  major_engine_version = "8.0"      # DB option group
  instance_class       = "db.t2.micro"

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = "completeMysql"
  username = "complete_mysql"
  port     = 3306

  multi_az               = true
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.security_group_ec2.security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["general"]
  create_cloudwatch_log_group     = false
  blue_green_update = {
    enabled = true
  }

  skip_final_snapshot = true
  deletion_protection = false

  performance_insights_enabled          = false
  performance_insights_retention_period = 7
  create_monitoring_role                = false
  monitoring_interval                   = 60

  parameters = [
    {
      name  = "character_set_client"
      value = "utf8mb4"
    },
    {
      name  = "character_set_server"
      value = "utf8mb4"
    }
  ]

  tags = local.tags
  db_instance_tags = {
    "Sensitive" = "high"
  }
  db_option_group_tags = {
    "Sensitive" = "low"
  }
  db_parameter_group_tags = {
    "Sensitive" = "low"
  }
  db_subnet_group_tags = {
    "Sensitive" = "high"
  }
}
