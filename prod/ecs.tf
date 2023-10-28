resource "aws_ecs_cluster" "nagaza-cluster-prod" {
  name = "nagaza-cluster-prod"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_secretsmanager_secret" "nagaza-ecs-secret" {
  name = "nagaza-ecs-secret"
}

resource "aws_secretsmanager_secret_version" "nagaza-ecs-secret-version" {
  secret_id     = aws_secretsmanager_secret.nagaza-ecs-secret.id
  secret_string = jsonencode({
    "DB_URL" = local.db_url
    "DB_PASSWORD" = local.db_password
    "DB_USERNAME" = local.db_username
    "AUTH_SECRET" = local.jwt_secret
  })

#  lifecycle {
#    ignore_changes = [
#      secret_string
#    ]
#  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/"

  tags = {
    Environment = "production"
    Application = "ecs"
  }
}

resource "aws_ecs_task_definition" "nagaza-backend" {
  family = "nagaza-backend-prod"
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  depends_on = [aws_cloudwatch_log_group.ecs, aws_secretsmanager_secret_version.nagaza-ecs-secret-version]
  lifecycle {
    ignore_changes = [

    ]
  }
  container_definitions = jsonencode([
    {
      name      = "api"
      image     = local.ecs_image_url
      cpu       = 1024
      memory    = 2048
      essential = true
      portMappings = [
        {
          containerPort = local.container_port
          hostPort      = local.container_port
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/"
          "awslogs-region"        = "ap-northeast-2"
          "awslogs-stream-prefix" = "ecs"
        }
      }
      secrets = [
        {
          name      = "DB_URL"
          valueFrom = aws_secretsmanager_secret_version.nagaza-ecs-secret-version.arn
        },
        {
          name      = "DB_USERNAME"
          valueFrom = aws_secretsmanager_secret_version.nagaza-ecs-secret-version.arn
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = aws_secretsmanager_secret_version.nagaza-ecs-secret-version.arn
        },
        {
          name      = "AUTH_SECRET"
          valueFrom = aws_secretsmanager_secret_version.nagaza-ecs-secret-version.arn
        }
      ]
    }
  ])
}

data "aws_iam_policy_document" "ecs_task_execution_role" {
  version = "2012-10-17"
  statement {
    sid     = ""
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}


resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs-prod-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "ecs_secret_manager_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy     = data.aws_iam_policy_document.secret_manager_policy.json
}

data "aws_iam_policy_document" "secret_manager_policy" {
  statement {
    effect = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.nagaza-ecs-secret.arn]
  }
}


resource "aws_ecs_service" "nagaza-backend" {
  name            = "nagaza-backend"
  cluster         = aws_ecs_cluster.nagaza-cluster-prod.id
  task_definition = aws_ecs_task_definition.nagaza-backend.arn
  desired_count   = 2

  launch_type     = "FARGATE"
  #depends_on      = [aws_iam_role_policy.foo]
  depends_on = [aws_lb_listener.http_to_https, aws_lb_listener.https_forward, aws_iam_role_policy_attachment.ecs_task_execution_role]
  network_configuration {
    security_groups  = [aws_security_group.nagaza-prod-ecs-sg.id]
    subnets          = aws_subnet.private[*].id
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.nagaza-prod.arn
    container_name   = "api"
    container_port   = local.container_port
  }
}


data "aws_iam_policy_document" "instance_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs-role" {
  name               = "nagaza-backend-ecs-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role_policy.json # (not shown)

  inline_policy {
    name   = "nagaza-backend-ecs-policy"
    policy = data.aws_iam_policy_document.inline_policy.json
  }
}

resource "aws_iam_role_policy_attachment" "sto-readonly-role-policy-attach" {
  role       = aws_iam_role.ecs-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

data "aws_iam_policy_document" "inline_policy" {
  statement {
    actions   = ["ec2:DescribeAccountAttributes"]
    resources = ["*"]
  }
}
resource "aws_security_group" "nagaza-prod-ecs-sg" {
  name        = "nagaza-prod-ecs-sg"
  description = "Prod ECS Security Group"
  vpc_id      = aws_vpc.nagaza-vpc.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    security_groups = [aws_security_group.nagaza-prod-alb-sg.id]
    from_port       = local.container_port
    to_port         = local.container_port
    protocol        = "tcp"
  }

  tags = {
    Name = "nagaza-prod-ecs-sg"
  }
}

