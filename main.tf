terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
  default_tags {
    tags = {

      Project = "terrafirma"
    }
  }
}


resource "aws_vpc" "terra_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "terra_vpc"

  }
}

resource "aws_subnet" "pub_1a" {
  vpc_id            = aws_vpc.terra_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-central-1a"
  tags = {
    Name = "terra_pub-1a"

  }

}

resource "aws_subnet" "pub_1b" {
  vpc_id            = aws_vpc.terra_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1b"
  tags = {
    Name = "terra_pub-1b"

  }
}

resource "aws_internet_gateway" "terra_igw" {

  vpc_id = aws_vpc.terra_vpc.id
  tags = {

    Name = "terra_igw"
  }

}

resource "aws_route_table" "terra_pub_rt" {
  vpc_id = aws_vpc.terra_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terra_igw.id
  }



}
resource "aws_route_table_association" "tr_pub1" {
  subnet_id      = aws_subnet.pub_1a.id
  route_table_id = aws_route_table.terra_pub_rt.id
}
resource "aws_route_table_association" "tr_pub2" {
  subnet_id      = aws_subnet.pub_1b.id
  route_table_id = aws_route_table.terra_pub_rt.id
}

############################



resource "aws_subnet" "prv_1a" {
  vpc_id            = aws_vpc.terra_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "eu-central-1a"
  tags = {
    Name = "terra_prv_1a"

  }

}

resource "aws_subnet" "prv_1b" {
  vpc_id            = aws_vpc.terra_vpc.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "eu-central-1b"
  tags = {
    Name = "terra_prv-1b"

  }
}

resource "aws_eip" "terra_eip" {

  domain = "vpc"
  tags = {
    Name = "terra_eip"

  }
}

resource "aws_nat_gateway" "terra_nat" {

  subnet_id     = aws_subnet.pub_1a.id
  allocation_id = aws_eip.terra_eip.allocation_id
  tags = {

    Name = "terra_NAT"
  }

}

resource "aws_route_table" "terra_prv_rt" {
  vpc_id = aws_vpc.terra_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.terra_nat.id
  }
  tags = {
    Name = "terra_prv_rt"

  }


}
resource "aws_route_table_association" "tr_prv1" {
  subnet_id      = aws_subnet.prv_1a.id
  route_table_id = aws_route_table.terra_prv_rt.id

}
resource "aws_route_table_association" "tr_prv2" {
  subnet_id      = aws_subnet.prv_1b.id
  route_table_id = aws_route_table.terra_prv_rt.id

}

resource "aws_key_pair" "terra_key" {
  key_name   = "terra-lab"
  public_key = file("~/.ssh/terra-lab.pub")
  tags = {
    Name = "terra_key"

  }
}
variable "my_ip" {
  description = "Public IP allowed to SSH to the bastion"
  type        = string
}
resource "aws_security_group" "pub_sec_group" {
  vpc_id = aws_vpc.terra_vpc.id
  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "pub_sec_group"

  }
}

resource "aws_security_group" "prv_sec_group" {
  vpc_id = aws_vpc.terra_vpc.id
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.pub_sec_group.id]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "prv_sec_group"

  }
}

resource "aws_instance" "ec2_pub" {

  ami                         = "ami-0303e2e4a29f041a3"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.pub_1a.id
  key_name                    = aws_key_pair.terra_key.key_name
  vpc_security_group_ids      = [aws_security_group.pub_sec_group.id]
  associate_public_ip_address = true
  tags = {
    Name = "ec2_pub"

  }
}
resource "aws_instance" "ec2_prv" {

  ami                    = "ami-0303e2e4a29f041a3"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.prv_1a.id
  key_name               = aws_key_pair.terra_key.key_name
  vpc_security_group_ids = [aws_security_group.prv_sec_group.id]
  iam_instance_profile   = aws_iam_instance_profile.scanner_profile.name
  depends_on             = [aws_nat_gateway.terra_nat]
  user_data = <<-EOF
  #!/bin/bash
  set -e
  echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
  apt-get update
  apt-get install -y docker.io
  systemctl start docker
  apt-get install -y awscli
  aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin 418272772312.dkr.ecr.eu-central-1.amazonaws.com
  docker pull ${aws_ecr_repository.scanner.repository_url}
  docker run -e AWS_REGION=eu-central-1 ${aws_ecr_repository.scanner.repository_url}

EOF

  tags = {
    Name = "ec2_prv"

  }
}
resource "aws_ecr_repository" "scanner" {
  name                 = "scanner"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }

}
output "ecr_url" {
  value = aws_ecr_repository.scanner.repository_url

}

resource "aws_iam_role" "scanner_role" {
  name = "scanner_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "scanner_role"
  }
}

resource "aws_iam_role_policy" "scanner_policy" {
  name = "scanner_policy"
  role = aws_iam_role.scanner_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["ec2:DescribeAddresses", "ec2:DescribeSecurityGroups", "ec2:DescribeNetworkInterfaces", "ec2:DescribeVolumes", "ec2:DescribeInstances", "ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer"]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}


resource "aws_iam_instance_profile" "scanner_profile" {
  name = "scanner_profile"
  role = aws_iam_role.scanner_role.name
}

