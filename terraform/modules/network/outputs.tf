output "vpc_id"                 { value = aws_vpc.main.id }
output "vpc_cidr"               { value = aws_vpc.main.cidr_block }
output "public_subnet_ids"      { value = aws_subnet.public[*].id }
output "igw_id"                 { value = aws_internet_gateway.main.id }
