###<VPC>
resource "aws_vpc" "tf-vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true #DNS 사용 허용
  enable_dns_hostnames = true #퍼블릭IP를 가진 인스턴스가 퍼블릭DNS 이름을 자동으로 할당받도록 

  tags = { Name = "${var.project_name}-vpc" }
}




###<서브넷>
#퍼블릭 서브넷 (각 AZ당 하나씩)
resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.tf-vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index] #cidr 대역대는 퍼블릭 대역대 값이 하나씩 할당
  availability_zone = var.availability_zones[count.index]  #AZ 당 퍼블릭 서브넷이 하나씩  할당

  map_public_ip_on_launch = true #퍼블릭 서브넷에 인스턴스를 띄울 때 퍼블릭IP 자동할당

  tags = { Name = "${var.project_name}-public-subnet-${count.index + 1}" }
}

#프라이빗 서브넷 (각 AZ당 하나씩)
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.tf-vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index] #각각의 프라이빗 서브넷에 프라이빗 대역대가 지정
  availability_zone = var.availability_zones[count.index]   #프라이빗 서브넷이 각각의 AZ에 할당

  tags = { Name = "${var.project_name}-private-subnet-${count.index + 1}" }
}




###<인터넷 게이트웨이>
resource "aws_internet_gateway" "tf-igw" {
  vpc_id = aws_vpc.tf-vpc.id

  tags = { Name = "${var.project_name}-igw" }
}





###<NAT Gateway>
#NAT Gateway가 사용할 공인 eip 할당
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = { Name = "${var.project_name}-nat_eip" }
}

#NAT Gateway 생성
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[0].id #퍼블릭 서브넷에 배치

  tags = { Name = "${var.project_name}-nat_gateway" }

  depends_on = [aws_internet_gateway.tf-igw] #igw가 있어야 생성될 수 있다는 의존성 명시
}











###<라우팅테이블>
#퍼블릭 라우팅테이블    (외부로 나갈때는 IGW를 통하도록 설정)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.tf-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tf-igw.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

#퍼블릭 서브넷에 퍼블릭 라우팅테이블 연결
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


#프라이빗 라우팅테이블 (외부로 나갈때는 NAT GW를 통하도록 설정)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.tf-vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = { Name = "${var.project_name}-private-rt" }
}

#프라이빗 서브넷에 각 프라이빗 라우팅테이블 연결
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}







###<Security Group>
#ALB 보안그룹
resource "aws_security_group" "alb" {
  vpc_id = aws_vpc.tf-vpc.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#WEB 보안그룹 
resource "aws_security_group" "web" {
  vpc_id = aws_vpc.tf-vpc.id

  ingress {
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    security_groups = [aws_security_group.bastion.id] #사설망의 EC2 인스턴스에서 사용하는 SG (배스천 호스트에서만 접근 허용)
  }

  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    protocol        = "tcp"
    from_port       = 443
    to_port         = 443
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    protocol    = "-1" #모든 프로토콜 허용
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-web-sg" }
}

#배스천 호스트 보안그룹
resource "aws_security_group" "bastion" {
  vpc_id = aws_vpc.tf-vpc.id

  #사무실 IP
  ingress {
    protocol	= "tcp"
    from_port	= 22
    to_port	= 22
    cidr_blocks = ["106.246.242.226/32"] 
  }

  #Ansible 프록시 경유
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["121.78.197.103/32"] #러너 서버
  }

  #Prometheus + Grafana 
  ingress {
    protocol    = "tcp"
    from_port   = 9100
    to_port     = 9100
    cidr_blocks = ["121.78.197.103/32"] #러너 서버
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-bastion-sg" }
}

#DB 보안그룹
resource "aws_security_group" "rds" {
  vpc_id = aws_vpc.tf-vpc.id

  ingress {
    protocol        = "tcp"
    from_port       = 3306
    to_port         = 3306
    security_groups = [aws_security_group.web.id] # 웹서버 보안그룹에서의 접근 허용
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-rds-sg" }
}


#EFS 보안그룹
resource "aws_security_group" "efs" {
  vpc_id = aws_vpc.tf-vpc.id

  ingress {
    protocol        = "tcp"
    from_port       = 2049
    to_port         = 2049
    security_groups = [aws_security_group.web.id] #EC2에서만 접근 가능하게 함(마운트를 위해)
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-efs-sg" }
}






