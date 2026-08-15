resource "aws_ecr_repository" "foo" {
  name                 = "ecr_repository"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecs_cluster" "foo" {
  name = "white-hart"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_service" "mongo" {
  name        = "mongodb"
  launch_type = "FARGATE"
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }
  cluster         = aws_ecs_cluster.foo.id
  task_definition = aws_ecs_task_definition.service.arn
  desired_count   = 1
  depends_on      = [aws_iam_role_policy_attachment.ecs_execution, aws_lb_listener.front_end]

  load_balancer {
    target_group_arn = aws_lb_target_group.foo.arn
    container_name   = "flask-app"
    container_port   = 5001
  }
}

resource "aws_cloudwatch_log_group" "flask_app" {
  name              = "/ecs/flask-app"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "service" {
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  family                   = "service"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.foo.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name  = "flask-app"
      image = "${aws_ecr_repository.foo.repository_url}:latest"
      environment = [
        { name = "DB_HOST", value = aws_db_instance.reflection.address },
        { name = "DB_NAME", value = aws_db_instance.reflection.db_name },
        { name = "DB_USER", value = aws_db_instance.reflection.username },
        { name = "DB_PASSWORD", value = var.db_password },
        { name = "API_KEY", value = var.gemini_api_key }
      ]
      #Secret managerを使うべきだが、金がかかる。
      essential = true
      portMappings = [
        {
          containerPort = 5001
          hostPort      = 5001
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.flask_app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "flask-app"
        }
      }
    }
  ])
  volume {
    name = "service-storage"
  }
}

resource "aws_iam_role" "foo" {
  name = "an_example_role_name"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.foo.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_lb" "test" {
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = data.aws_subnets.default.ids

  enable_deletion_protection = true

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_target_group" "foo" {
  name        = "tf-example-lb-tg"
  port        = 5001
  target_type = "ip"
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  health_check {
    path = "/health"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.test.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    # type = "redirect"

    # redirect {
    #   port        = "443"
    #   protocol    = "HTTPS"
    #   status_code = "HTTP_301"
    # }
    type             = "forward"
    target_group_arn = aws_lb_target_group.foo.arn
  }
}
