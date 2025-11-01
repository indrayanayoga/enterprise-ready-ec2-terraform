provider "aws" {
    region = "ap-southeast-3"
}

data "aws_availability_zones" "azs" {
    state = "available"
}

resource "aws_vpc" "vpc-explore" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "vpc-explore"
        Indrayana = "true"
        Env = "explore"
    }
}

resource "aws_subnet" "private-subnet" {
    count = 2
    vpc_id = aws_vpc.vpc-explore.id
    cidr_block = cidrsubnet(aws_vpc.vpc-explore.cidr_block, 4, count.index)
    availability_zone = data.aws_availability_zones.azs.names[count.index]
    tags = {
        Name = "vpc-explore-private-subnet-${count.index + 1}"
        Indrayana = "true"
        Env = "explore"
        Type = "private"
    }
}

resource "aws_subnet" "public-subnet" {
    count = 2
    vpc_id = aws_vpc.vpc-explore.id
    cidr_block = cidrsubnet(aws_vpc.vpc-explore.cidr_block, 4, count.index + 2)
    availability_zone = data.aws_availability_zones.azs.names[count.index]
    map_public_ip_on_launch = true
    tags = {
        Name = "vpc-explore-public-subnet-${count.index + 1}"
        Indrayana = "true"
        Env = "explore"
        Type = "public"
    }
}

resource "aws_internet_gateway" "vpc-explore-igw" {
    vpc_id = aws_vpc.vpc-explore.id
    tags = {
        Name = "vpc-explore-igw"
        Indrayana = "true"
        Env = "explore"
    }
}

resource "aws_eip" "ip-nat" {
    count = 2
    tags = {
        Name = "vpc-explore-eip-${count.index + 1}"
        Indrayana = "true"
        Env = "explore"
    }
}

resource "aws_nat_gateway" "vpc-explore-nat-gateway" {
    count = 2
    subnet_id = aws_subnet.public-subnet[count.index].id
    allocation_id = aws_eip.ip-nat[count.index].id
    tags = {
        Name = "vpc-explore-nat-gateway-${count.index + 1}"
        Indrayana = "true"
        Env = "explore"
    }
}

resource "aws_route_table" "private_route_table" {
    count = 2
    vpc_id = aws_vpc.vpc-explore.id
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.vpc-explore-nat-gateway[count.index].id
    }
    tags = {
        Indrayana = "true"
        Env = "explore"
    }
}

resource "aws_route_table_association" "private_route_table_assoc" {
    count = 2
    subnet_id = aws_subnet.private-subnet[count.index].id
    route_table_id = aws_route_table.private_route_table[count.index].id
}

resource "aws_route_table" "public_route_table" {
    count = 2
    vpc_id = aws_vpc.vpc-explore.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.vpc-explore-igw.id
    }
    tags = {
        Indrayana = "true"
        Env = "explore"
    }
}

resource "aws_route_table_association" "public_route_table_assoc" {
    count = 2
    subnet_id = aws_subnet.public-subnet[count.index].id
    route_table_id = aws_route_table.public_route_table[count.index].id
}

