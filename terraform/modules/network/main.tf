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

  tags = { Name = "${var.project_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

#프라이빗 서브넷 (각 AZ당 하나씩)
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.tf-vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index] #각각의 프라이빗 서브넷에 프라이빗 대역대가 지정
  availability_zone = var.availability_zones[count.index]   #프라이빗 서브넷이 각각의 AZ에 할당

  tags = { Name = "${var.project_name}-private-subnet-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  }
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
  count  = length(var.availability_zones)

  tags = { Name = "${var.project_name}-nat_eip-${count.index + 1}" }
}

#NAT Gateway 생성
resource "aws_nat_gateway" "nat_gateway" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id     = aws_subnet.public[count.index].id #퍼블릭 서브넷에 배치

  tags = { Name = "${var.project_name}-nat_gateway-${count.index + 1}" }

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
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.tf-vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway[count.index].id
  }

  tags = { Name = "${var.project_name}-private-rt-${count.index + 1}" }
}

#프라이빗 서브넷에 각 프라이빗 라우팅테이블 연결
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
