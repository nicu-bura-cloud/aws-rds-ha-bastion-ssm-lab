terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-south-1"
}

variable "db_username" {}
variable "db_password" {
  sensitive = true
}

# NUOVO: CHIAVE SSH
resource "aws_key_pair" "lab2_key" {
  key_name   = "lab2-bastion-key"
  public_key = file("~/.ssh/lab2-key.pub")
}


resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "lab2-vpc" }
}
# SUBNET PRIVATA 1 - se non ce l'hai già
resource "aws_subnet" "privata_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-south-1a"
  tags = { Name = "subnet-privata-1-rds" }
}

# SUBNET PRIVATA 2 - RDS vuole 2 AZ
resource "aws_subnet" "privata_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-south-1b"
  tags = { Name = "subnet-privata-2-rds" }
}

# DB SUBNET GROUP - Recinto per RDS
resource "aws_db_subnet_group" "rds_privato" {
  name       = "rds-privato-subnet-group"
  subnet_ids = [aws_subnet.privata_1.id, aws_subnet.privata_2.id]
  tags = { Name = "DB subnet group solo private" }
}

# SECURITY GROUP BASTION - se non ce l'hai già
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg-lab"
  description = "SSH da casa mia"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Dopo metti il tuo IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SECURITY GROUP RDS - Parla solo col Bastion
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg-postgres-privato"
  description = "Consenti 5432 solo da Bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL da Bastion"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = { Name = "rds-sg-postgres-privato" }
}

# RDS POSTGRESQL PRIVATO
resource "aws_db_instance" "postgres" {
  identifier     = "dba-lab-postgres"
  engine         = "postgres"
  engine_version = "15.17"
  instance_class = "db.t3.micro"
  
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true
  
  db_name  = "labdb"
  username = var.db_username
  password = var.db_password
  
  db_subnet_group_name   = aws_db_subnet_group.rds_privato.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  
  publicly_accessible       = false
  backup_retention_period   = 0
  skip_final_snapshot       = true
  
  tags = { Name = "RDS-Postgres-Privato-Lab" }
}


# SUBNET PUBBLICA PER BASTION
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-south-1a"
  map_public_ip_on_launch = true
  tags = { Name = "subnet-pubblica-bastion" }
}

# INTERNET GATEWAY
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "igw-lab" }
}

# ROUTE TABLE PUBBLICA
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "rt-pubblica" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

# EC2 BASTION
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.ubuntu.id  # Prende sempre l'ultima
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = "bura-udine-lab"        # Metti il nome giusto della tua key
  
  tags = { Name = "bastion-lab" }
}

output "bastion_ip" {
  value       = aws_instance.bastion.public_ip
  description = "IP pubblico del Bastion per tunnel SSH"
}

output "rds_endpoint" {
  value       = aws_db_instance.postgres.address
  description = "Endpoint RDS per connessione"
}