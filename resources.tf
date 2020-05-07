##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}

##################################################################################
# DATA
##################################################################################

data "aws_availability_zones" "available" {}

data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "template_file" "public_cidrsubnet" {
  count = var.subnet_public_count[terraform.workspace]

  template = "$${cidrsubnet(vpc_cidr,8,current_count)}"

  vars = {
    vpc_cidr      = var.network_address_space[terraform.workspace]
    current_count = count.index
  }
}

data "template_file" "private_cidrsubnet" {
  count = var.subnet_private_count[terraform.workspace]   
  template = "$${cidrsubnet(vpc_cidr,8,current_count+count_public)}"

  vars = {
    vpc_cidr      = var.network_address_space[terraform.workspace]
    current_count = count.index
    count_public = var.subnet_public_count[terraform.workspace]
  }
}

##################################################################################
# RESOURCES
##################################################################################

#Random ID
resource "random_integer" "rand" {
  min = 10000
  max = 99999
}

# NETWORKING #
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "${local.env_name}-vpc"
  version = "2.15.0"
  enable_nat_gateway = true
  cidr            = var.network_address_space[terraform.workspace]
  azs             = slice(data.aws_availability_zones.available.names, 0, var.subnet_public_count[terraform.workspace])
  public_subnets  = data.template_file.public_cidrsubnet[*].rendered
  private_subnets = data.template_file.private_cidrsubnet[*].rendered

  tags = local.common_tags
}

resource "aws_security_group" "ec2-sg" {
  name   = "ec2_sg"
  vpc_id = module.vpc.vpc_id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.env_name}-ec2_sg" })

}

# INSTANCES #
resource "aws_instance" "test-bastion" {
  count                  = var.instance_count[terraform.workspace]
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = var.instance_size[terraform.workspace]
  subnet_id              = module.vpc.public_subnets[count.index % var.subnet_public_count[terraform.workspace]]
  vpc_security_group_ids = [aws_security_group.ec2-sg.id]
  key_name               = var.key_name
  user_data = "${file("userdata.txt")}"
  tags = merge(local.common_tags, { Name = "${local.env_name}-instance-public-${count.index + 1}" })
}

# INSTANCES #
resource "aws_instance" "test" {
  count                  = var.instance_count[terraform.workspace]
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = var.instance_size[terraform.workspace]
  subnet_id              = module.vpc.private_subnets[count.index % var.subnet_private_count[terraform.workspace]]
  vpc_security_group_ids = [aws_security_group.ec2-sg.id]
  key_name               = var.key_name
  #user_data = "${file("userdata.txt")}"
  tags = merge(local.common_tags, { Name = "${local.env_name}-instance-private-${count.index + 1}" })
  
}
