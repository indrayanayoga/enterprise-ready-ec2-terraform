
provider "aws" {
    region = "ap-southeast-3"
}

#Fetch VPC Configurations
data "aws_vpc" "current-vpc" {
    filter {
        name = "tag:Name"
        values = ["vpc-explore"]
    }
    filter {
        name = "tag:Env"
        values = ["explore"]
    }
}

data "aws_subnets" "current-private-subnets" {
    filter {
        name = "tag:Type"
        values = ["private"]
    }
    filter {
        name = "vpc-id"
        values = [data.aws_vpc.current-vpc.id]
    }
}

data "aws_subnets" "current-public-subnets" {
    filter {
        name = "tag:Type"
        values = ["public"]
    }
    filter {
        name = "vpc-id"
        values = [data.aws_vpc.current-vpc.id]
    }
}

#=====IAM RESOURCES=====
#Allow Assume Role, and attach Cloudwatch Agent and SSM role policies

resource "aws_iam_role" "nginx-role" {
  name = "nginx-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
    tags = {
        Name = "Nginx Role"
        Indrayana = "true"
        Env = "explore"
    }
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
    policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    role = aws_iam_role.nginx-role.id 
}

resource "aws_iam_role_policy_attachment" "ssm" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    role = aws_iam_role.nginx-role.id
}

resource "aws_iam_instance_profile" "nginx-profile" {
    name = "nginx-instance-profile"
    role = aws_iam_role.nginx-role.id
    tags = {
        Name = "Nginx Instance Profile"
        Indrayana = "true"
        Env = "explore"
    }
}

#=====NETWORKING RESOURCES=====

#Create Security Group for LB
#Allow traffic from internet to LB on port 80
resource "aws_security_group" "lb_security_group" {
    name = "allow-http"
    vpc_id = data.aws_vpc.current-vpc.id
    ingress {
        from_port = "80"
        to_port = "80"
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/16"]
    }

    tags = {
        Name = "Nginx Load Balancer Security Group"
        Indrayana = "true"
        Env = "explore"
    }
}

#External Application Load Balancer
#State the public subnets, as this is an external LB
resource "aws_lb" "nginx-lb" {
    name = "nginx-lb"
    internal = false
    load_balancer_type = "application"
    security_groups = [aws_security_group.lb_security_group.id]
    subnets = data.aws_subnets.current-public-subnets.ids
    tags = {
        Name = "Nginx Load Balancer"
        Indrayana = "true"
        Env = "explore"
    }
}

#Listener
#Forward the traffic from LB to target group, choose which port the LB receives traffic from
resource "aws_lb_listener" "nginx-listener" {
    load_balancer_arn = aws_lb.nginx-lb.arn
    port = 80
    protocol = "HTTP"
    default_action {
      type = "forward"
      target_group_arn = aws_lb_target_group.nginx-target-group.arn
    }
    tags = {
        Name = "Nginx Listener"
        Indrayana = "true"
        Env = "explore"
    }
}

#Target Group
#State the port and protocol which the LB will forward traffic to
#State the healthcheck method
resource "aws_lb_target_group" "nginx-target-group" {
    name = "nginx-target-group"
    port = 80
    protocol = "HTTP"
    vpc_id = data.aws_vpc.current-vpc.id
    health_check {
      path = "/"
      interval = 5
      timeout = 3
      healthy_threshold = 2
      unhealthy_threshold = 3
      matcher = "200"
    }
    tags = {
        Name = "Nginx Target Group"
        Indrayana = "true"
        Env = "explore"
    }
}


#===== COMPUTE RESOURCES =====

#Fetch latest AMI
data "aws_ami" "current-ami" {
    most_recent = true
    owners      = ["amazon"]
    name_regex  = "^al2023-ami-2023.*-x86_64"
}

#Configure environment variable
variable "word" {
    type = string
    default = "explore"
}

#Security Group for EC2
#Allow only HTTP connection from LB
resource "aws_security_group" "nginx_security_group" {
    name = "nginx-security-group"
    vpc_id = data.aws_vpc.current-vpc.id
    ingress {
        from_port = "80"
        to_port = "80"
        protocol = "tcp"
        security_groups = [aws_security_group.lb_security_group.id]
    }
    egress {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
        Name = "Nginx Security Group"
        Indrayana = "true"
        Env = "explore"
    }
}

#Launch Template
#Define name, image, user data
resource "aws_launch_template" "nginx" {
    name_prefix = "nginx"
    image_id = data.aws_ami.current-ami.id
    instance_type = "t3.small"

    user_data = base64encode(templatefile("user-data.sh", {
        word = var.word
    }))
    
    iam_instance_profile {
      name = aws_iam_instance_profile.nginx-profile.id
    }

    network_interfaces {
      security_groups = [aws_security_group.nginx_security_group.id]
    }
    tags = {
        Name = "Nginx Launch Template"
        Indrayana = "true"
        Env = "explore"
    }
}


#Autoscaling Group
#Define Min, Max, and the Target Group
resource "aws_autoscaling_group" "nginx-autoscaling-group" {
    name = "nginx-autoscaling-group"
    min_size = 2
    max_size = 4
    launch_template {
      id = aws_launch_template.nginx.id
      version = "$Latest"
    }

    vpc_zone_identifier = data.aws_subnets.current-private-subnets.ids

    health_check_type = "ELB"
    health_check_grace_period = 360

    target_group_arns = [aws_lb_target_group.nginx-target-group.arn]

    instance_refresh {
      strategy = "Rolling"
      preferences {
        min_healthy_percentage = 90
      }
    }

    tag {
      key = "Name"
      value = "nginx"
      propagate_at_launch = true
    }

    tag {
        key = "Env"
        value = "explore"
        propagate_at_launch = true
    }
    tag {
        key = "Indrayana"
        value = "true"
        propagate_at_launch = true
    }

}

resource "aws_autoscaling_policy" "nginx-autoscaling-policy" {
    name = "nginx-autoscaling-policy"
    autoscaling_group_name = aws_autoscaling_group.nginx-autoscaling-group.name
    policy_type = "TargetTrackingScaling"
    target_tracking_configuration {
        predefined_metric_specification {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
        target_value = 70
    }   
}

