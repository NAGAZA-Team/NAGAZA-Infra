resource "aws_rds_cluster" "common_prod" {
  cluster_identifier     = "nagaza-prod"
  db_subnet_group_name   = aws_db_subnet_group.prod-db-subnet.name
  vpc_security_group_ids = [
    aws_security_group.prod_db_sg.id
  ]
  engine_mode                     = "provisioned"
  enable_http_endpoint            = false
  master_username                 = "admin"
  master_password                 = random_password.rng-prod.result
  backup_retention_period         = 3
  engine                          = "aurora-mysql"
  engine_version                  = "8.0.mysql_aurora.3.03.1"
  skip_final_snapshot = true

  serverlessv2_scaling_configuration {
    max_capacity = 4
    min_capacity = 0.5
  }

  lifecycle {
    ignore_changes = [
      engine_version,
      availability_zones,
      master_username,
      master_password,
    ]
  }

  tags = {
    Environment = "prod"
    Name        = "nagaza-prod"
  }
}

resource "aws_rds_cluster_instance" "common_prod_1" {
  identifier         = "nagaza-instance-prod-1"
  cluster_identifier = aws_rds_cluster.common_prod.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.common_prod.engine
  engine_version     = aws_rds_cluster.common_prod.engine_version
}

resource "random_password" "rng-prod" {
  length  = 16
  special = false

  keepers = {
    cluster_identifier = "nagaza-prod"
  }
}

resource "aws_db_subnet_group" "prod-db-subnet" {
  name       = "nagaza-rds-prod-subnet"
  subnet_ids = aws_subnet.private.*.id

  tags = {
    Name = "DB subnet group"
  }
}

resource "aws_security_group" "prod_db_sg" {
  name        = "prod-db-sg"
  description = "Security group for prod db"
  vpc_id      = aws_vpc.nagaza-vpc.id

  tags = {
    Name = "Prod DB SG"
  }
}


resource "aws_security_group_rule" "prod_db_sg" {
  security_group_id = aws_security_group.prod_db_sg.id
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description              = "from repository client prod"
}

output "common_prod_passwd" {
  value     = random_password.rng-prod.result
  sensitive = true
}
