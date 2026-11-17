resource "aws_elastic_beanstalk_application" "web" {
  name = "${local.prefix}-web"
  description = "ApertureBridge image portal - Flask on Python AL2023"
}
resource "aws_elastic_beanstalk_environment" "web" {
  name = "${local.prefix}-web"
  application = aws_elastic_beanstalk_application.web.name
  solution_stack_name = var.eb_solution_stack_name
  wait_for_ready_timeout = "30m"
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name = "EnvironmentType"
    value = "LoadBalanced"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name = "LoadBalancerType"
    value = "application"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name = "ServiceRole"
    value = aws_iam_role.eb_service.name
  }
  setting {
    namespace = "aws:ec2:vpc"
    name = "VPCId"
    value = aws_vpc.main.id
  }
  setting {
    namespace = "aws:ec2:vpc"
    name = "Subnets"
    value = join(",", aws_subnet.app[*].id)
  }
  setting {
    namespace = "aws:ec2:vpc"
    name = "ELBSubnets"
    value = join(",", aws_subnet.public[*].id)
  }
  setting {
    namespace = "aws:ec2:vpc"
    name = "AssociatePublicIpAddress"
    value = "false"
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name = "IamInstanceProfile"
    value = aws_iam_instance_profile.eb.name
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name = "SecurityGroups"
    value = aws_security_group.web.id
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name = "InstanceType"
    value = var.eb_instance_type
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name = "DisableIMDSv1"
    value = "true"
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name = "MinSize"
    value = tostring(var.eb_min_instances)
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name = "MaxSize"
    value = tostring(var.eb_max_instances)
  }
  setting {
    namespace = "aws:elbv2:loadbalancer"
    name = "SecurityGroups"
    value = aws_security_group.alb.id
  }
  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs"
    name = "StreamLogs"
    value = "true"
  }
  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs"
    name = "DeleteOnTerminate"
    value = "false"
  }
  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs"
    name = "RetentionInDays"
    value = "14"
  }
  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name = "HealthCheckPath"
    value = "/healthz"
  }
  dynamic "setting" {
    for_each = var.lab_http_mode ? [] : [1]
    content {
      namespace = "aws:elbv2:listener:443"
      name = "ListenerEnabled"
      value = "true"
    }
  }
  dynamic "setting" {
    for_each = var.lab_http_mode ? [] : [1]
    content {
      namespace = "aws:elbv2:listener:443"
      name = "Protocol"
      value = "HTTPS"
    }
  }
  dynamic "setting" {
    for_each = var.lab_http_mode ? [] : [1]
    content {
      namespace = "aws:elbv2:listener:443"
      name = "SSLCertificateArns"
      value = var.acm_certificate_arn
    }
  }
  dynamic "setting" {
    for_each = var.lab_http_mode ? [1] : []
    content {
      namespace = "aws:elbv2:listener:80"
      name = "ListenerEnabled"
      value = "true"
    }
  }
  dynamic "setting" {
    for_each = var.lab_http_mode ? [] : [1]
    content {
      namespace = "aws:elbv2:listener:80"
      name = "ListenerEnabled"
      value = "false"
    }
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name = "AWS_REGION"
    value = var.aws_region
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name = "APP_BUCKET"
    value = aws_s3_bucket.assets.id
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name = "DB_HOST"
    value = aws_rds_cluster.aurora.endpoint
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name = "DB_NAME"
    value = var.db_name
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name = "DB_SECRET_ARN"
    value = aws_secretsmanager_secret.app.arn
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name = "S3_ACCELERATE"
    value = "true"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name = "DB_TLS_CA"
    value = "shared/certs/global-bundle.pem"
  }
  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name = "LOCAL_UPLOAD_PROXY"
    value = "false"
  }
  lifecycle {
    precondition {
      condition = var.lab_http_mode || length(var.acm_certificate_arn) > 0
      error_message = "Production HTTPS mode requires an ACM certificate ARN."
    }
  }
  depends_on = [aws_iam_role_policy_attachment.eb_managed, aws_iam_role_policy_attachment.eb_health,
                aws_iam_role_policy_attachment.eb_updates, aws_iam_role_policy.eb_app,
                aws_iam_role_policy_attachment.eb_ssm, aws_vpc_endpoint.s3]
}
