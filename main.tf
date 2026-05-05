provider "aws" {
     region = "eu-central-1"         
}
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "lab-mattina-vpc"
  }
}