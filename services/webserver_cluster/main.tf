locals {
  http_port    = 80
  any_port     = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips      = ["0.0.0.0/0"]
}



# terraform {
#   backend "s3" {
#     bucket = "git-terraform-up-and-running-state"
#     key    = "stage/services/webserver-cluster/terrafrom.tfstate"
#     # region = "eu-central-1"
#     region = "us-east-2"

#     dynamodb_table = "terraform-up-and-running-locks"
#     encrypt        = true
#   }
# }

# provider "aws" {
#   profile = "default"
#   # region  = "eu-central-1"
#   region = "us-east-2"
# }

resource "aws_launch_configuration" "test" {
  image_id        = "ami-0c55b159cbfafe1f0"
  instance_type   = var.instance_type
  security_groups = [aws_security_group.nginx_web_ssh.id]

  user_data = data.template_file.user_data.rendered

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_key_pair" "example" {
  key_name   = "azertac-aws"
  public_key = file("~/.ssh/azertac-aws.pem.pub")
}


resource "aws_security_group" "nginx_web_ssh" {
  name        = "${var.cluster_name}-nginx_web_ssh"
  description = "Allow ssh, http, https inboud and everything outbound"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
    "Terraform" : "true"
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.test.name
  vpc_zone_identifier  = data.aws_subnet_ids.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"
  min_size          = var.min_size
  max_size          = var.max_size

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-asg"
    propagate_at_launch = true
  }
}



# ALB (Application Load Balancer)
resource "aws_lb" "example" {
  name               = "${var.cluster_name}-alb"
  load_balancer_type = "application"
  subnets            = data.aws_subnet_ids.default.ids
  security_groups    = [aws_security_group.alb.id]
}

# ALB Listener 
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = local.http_port
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

# ALB Listener Rule
resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    field  = "path-pattern"
    values = ["*"]
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}


# ALB Security Group
resource "aws_security_group" "alb" {
  name = "${var.cluster_name}-alb"
}

# ALB Target Group
resource "aws_lb_target_group" "asg" {
  name     = "terraform-asg-example"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    # bucket = "git-terraform-up-and-running-state"
    # key    = "stage/data-stores/mysql/terrafrom.tfstate"

    bucket = "${var.db_remote_state_bucket}"
    key    = "${var.db_remote_state_key}"
    # region = "eu-central-1"
    region = "us-east-2"
  }
}

data "template_file" "user_data" {
  template = file("${path.module}/user-data.sh")

  vars = {
    server_port = var.server_port
    db_address  = data.terraform_remote_state.db.outputs.address
    db_port     = data.terraform_remote_state.db.outputs.port
  }
}



resource "aws_security_group_rule" "allow_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port   = local.http_port
  to_port     = local.http_port
  protocol    = local.tcp_protocol
  cidr_blocks = local.all_ips
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id

  from_port   = local.http_port
  to_port     = local.http_port
  protocol    = local.tcp_protocol
  cidr_blocks = local.all_ips
}