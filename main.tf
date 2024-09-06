provider "aws" {
  region = "ap-northeast-2"
}

# VPC 생성
resource "aws_vpc" "main" {
  cidr_block = "192.170.0.0/16"

  tags = {
    Name = "pingpong-vpc"
  }
}

# 퍼블릭 서브넷 생성
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.170.1.0/24"
  availability_zone = "ap-northeast-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-pingpong"
  }
}

# 프라이빗 서브넷 생성
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.170.2.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name = "private-subnet-pingpong"
  }
}

# 인터넷 게이트웨이 생성
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw-pingpong"
  }
}

# 퍼블릭 라우트 테이블 생성
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# 퍼블릭 서브넷과 라우트 테이블 연결
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# NAT 인스턴스 정의
resource "aws_instance" "nat_instance" {
  ami           = "ami-0e0ce674db551c1a5"  # NAT 인스턴스에 사용할 AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public.id
  key_name      = "my-ec2-keypair"
  associate_public_ip_address = true

  # 소스/대상 확인 비활성화
  source_dest_check = false  # NAT 인스턴스에서 패킷 포워딩을 허용

  tags = {
    Name = "NAT Instance-pingpong"
  }
}

# 프라이빗 라우트 테이블 정의
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block              = "0.0.0.0/0"
    network_interface_id     = aws_instance.nat_instance.primary_network_interface_id  # NAT 인스턴스의 네트워크 인터페이스 ID
  }

  tags = {
    Name = "private-route-table-pingpong"
  }
}

# 프라이빗 서브넷과 라우트 테이블 연결
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# IAM 역할 및 정책 생성 (SSM 접근을 위한)
resource "aws_iam_role" "ssm_role" {
  name = "jenkins-ssm-role-pingpong"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 보안 그룹 생성
resource "aws_security_group" "main" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "main-sg-pingpong"
  }
}

# Jenkins 인스턴스 (프라이빗 서브넷에 배치, SSM 연결 가능)
resource "aws_instance" "jenkins" {
  ami           = "ami-062cf18d655c0b1e8"
  instance_type = "t2.medium"
  key_name      = "my-ec2-keypair" # key_name.pem
  subnet_id     = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.main.id]
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  tags = {
    Name = "Jenkins-pingpong"
  }
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "jenkins-ssm-instance-profile-pingpong"
  role = aws_iam_role.ssm_role.name
}

# 백엔드 서버 (프라이빗 서브넷에 배치)
resource "aws_instance" "backend" {
  ami           = "ami-062cf18d655c0b1e8"
  instance_type = "t2.micro"
  key_name      = "my-ec2-keypair" # key_name.pem
  subnet_id     = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.main.id]

  tags = {
    Name = "Backend-pingpong"
  }
}

# 프론트엔드 서버 (퍼블릭 서브넷에 배치)
resource "aws_instance" "frontend" {
  ami           = "ami-062cf18d655c0b1e8"
  instance_type = "t2.micro"
  key_name      = "my-ec2-keypair" # key_name.pem
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.main.id]

  tags = {
    Name = "Frontend-pingpong"
  }
}

# 모니터링 서버 (퍼블릭 서브넷에 배치)
resource "aws_instance" "monitoring" {
  ami           = "ami-062cf18d655c0b1e8"
  instance_type = "t2.micro"
  key_name      = "my-ec2-keypair" # key_name.pem
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.main.id]

  tags = {
    Name = "Monitoring-pingpong"
  }
}


output "instance_ips" {
  value = [
    aws_instance.frontend.public_ip,
  ]
}