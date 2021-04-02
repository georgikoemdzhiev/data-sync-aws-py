resource "aws_security_group" "allow_ssh_traffic_sg" {
  name        = "allow_ssh_traffic_sg"
  description = "Allow SSH Traffic"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH trafic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.common_tags
}

# S3 bucket
resource "aws_s3_bucket" "b" {
  bucket = var.bucket_name
  server_side_encryption_configuration {
    rule {
      # required by OCTO
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
  tags = var.common_tags
}
# uploads the python script into the s3 bucket
resource "aws_s3_bucket_object" "python_script" {
  key    = var.python_script_file_name
  bucket = aws_s3_bucket.b.id
  source = "${path.module}/scripts/${var.python_script_file_name}"
  etag   = filemd5("${path.module}/scripts/${var.python_script_file_name}")
}
# S3 bucket

# LAMBDA
resource "aws_lambda_function" "stopgap_ec2_launch" {
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = var.lambda_handler
  runtime          = var.lambda_runtime
  filename         = var.lambda_filename
  source_code_hash = data.archive_file.lambda_code.output_base64sha256

  tags = var.common_tags
}
# generates zip file (in the calling module path) containing the lambda function code
data "archive_file" "lambda_code" {
  type        = "zip"
  source_dir  = "${path.module}/scripts/lambda/" # source files to zip
  output_path = "${path.cwd}/create_ec2.zip" # path to the produced zip file (e.g. prod/create_ec2.zip)
}

# Role that will be assumed by the lambda function
data "aws_iam_policy_document" "instance_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "run_ec2_instance_policy" {
  name        = "allow-ec2-run"
  description = "Allow-ec2-run"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "iam:PassRole",
        "ec2:RunInstances",
        "ec2:CreateTags"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "lambda_exec_role" {
  name        = "stopgap_start_instance"
  description = "Allows Lambda Function to call AWS services on your behalf."

  assume_role_policy = data.aws_iam_policy_document.instance_assume_role_policy.json

  tags = var.common_tags
}

# Attach the run-instance-lambda-polity to the lambda role
resource "aws_iam_role_policy_attachment" "attach_run_instance_lambda_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.run_ec2_instance_policy.arn
}

# Reference the AWS managed AWSLambdaBasicExecutionRole policy
data "aws_iam_policy" "write_cloud_watch_logs" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach the AWSLambdaBasicExecutionRole to the lambda role
resource "aws_iam_role_policy_attachment" "attach-cloud_watch_write_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = data.aws_iam_policy.write_cloud_watch_logs.arn
}

# END OF LAMBDA

# EC2 / Launch Template
resource "aws_launch_template" "stopgap" {
  name          = "stopgap"
  image_id      = var.ami_image
  instance_type = var.instance_type

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = "true"
      encrypted             = "true"
      volume_size           = 8
      volume_type           = "gp2"
    }
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.stopgap.arn
  }
  network_interfaces {
    subnet_id       = var.subnet_id
    security_groups = [aws_security_group.allow_ssh_traffic_sg.id]
  }

  key_name = var.key_pair_name
  # vpc_security_group_ids = [aws_security_group.allow_ssh_traffic_sg.id]

  # security_group_names = [aws_security_group.allow_ssh_traffic_sg.name]
  instance_initiated_shutdown_behavior = "terminate"
  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags,
      map("ParentAMI", var.ami_image),
    map("Name", "TEMP Stopgap Instance"))
  }
  tags      = var.common_tags
  user_data = base64encode(data.template_file.user_data.rendered)
}

# Access 'userdata.sh' file and populate with variables
data "template_file" "user_data" {
  template = file("${path.module}/scripts/userdata.sh")
  vars = {
    bucket_name             = var.bucket_name,
    region                  = var.region,
    python_script_file_name = var.python_script_file_name
  }
}

resource "aws_iam_instance_profile" "stopgap" {
  name = "StopgapInstanceProfile"
  role = aws_iam_role.stopgap_ec2.name
}

# EC2 "Trust relationships" policy (necessary to allow the instance to assume a role)
data "aws_iam_policy_document" "trust_relationships_ec2_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM policy allowiing EC2 access to DynamoDB table
resource "aws_iam_policy" "access_to_stopgap" {
  name        = "AccessStopgapTable"
  description = "Stopgap. Policy allowing access to DynamoDB table"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "dynamodb:UpdateItem",
        "dynamodb:GetItem"
      ],
      "Effect": "Allow",
      "Resource": "${aws_dynamodb_table.stopgap.arn}"
    }
  ]
}
EOF
}


# IAM policy allowiing EC2 access to Aurora db
resource "aws_iam_policy" "access_to_aurora_stopgap" {
  name        = "AccessStopgapAuroraDB"
  description = "Stopgap. Policy allowing access to AuroraDB"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "rds-data:ExecuteStatement",
        "rds-data:BeginTransaction",
        "rds-data:RollbackTransaction",
        "rds-data:BatchExecuteStatement",
        "rds-data:CommitTransaction"
      ],
      "Effect": "Allow",
      "Resource": "${lookup(var.secrets, "auroraArn")}"
    }
  ]
}
EOF
}

# IAM policy allowiing EC2 access to S3 bucket
resource "aws_iam_policy" "access_to_s3_bucket" {
  name        = "AccessStopgapBucket"
  description = "Stopgap. Policy allowing access to S3 bucket"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.b.arn}"
    },
    {
      "Action": [
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.b.arn}/*"
    }
  ]
}
EOF
}

# IAM policy allowing EC2 to public to SNS topic
resource "aws_iam_policy" "access_to_sns_stopgap" {
  name        = "AccessStopgapSNS"
  description = "Stopgap. Policy allowing access to SNS topic"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "sns:Publish"
      ],
      "Effect": "Allow",
      "Resource": "${aws_sns_topic.stopgap.arn}"
    }
  ]
}
EOF
}


# IAM policy allowing EC2 to access Secret Manager 
resource "aws_iam_policy" "access_to_secret_stopgap" {
  name        = "AccessStopgapSecret"
  description = "Stopgap. Policy allowing access to Secret"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Effect": "Allow",
      "Resource": "${aws_secretsmanager_secret.secret.arn}"
    }
  ]
}
EOF
}

# Attach the DynamoDB policy to the EC2 Role
resource "aws_iam_role_policy_attachment" "attach_dynamodb_table_policy" {
  role       = aws_iam_role._stopgap_ec2.name
  policy_arn = aws_iam_policy.access_to_stopgap.arn
}

# Attach the AuroraDB policy to the EC2 Role
resource "aws_iam_role_policy_attachment" "attach_auroradb_policy" {
  role       = aws_iam_role._stopgap_ec2.name
  policy_arn = aws_iam_policy.access_to_aurora_stopgap.arn
}

# Attach the S3 policy to the EC2 Role
resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role._stopgap_ec2.name
  policy_arn = aws_iam_policy.access_to_s3_bucket.arn
}

# Attach the SNS policy to the EC2 Role
resource "aws_iam_role_policy_attachment" "attach_sns_policy" {
  role       = aws_iam_role._stopgap_ec2.name
  policy_arn = aws_iam_policy.access_to_sns_stopgap.arn
}

# Attach the Secret policy to the EC2 Role
resource "aws_iam_role_policy_attachment" "attach_secret_policy" {
  role       = aws_iam_role._stopgap_ec2.name
  policy_arn = aws_iam_policy.access_to_secret_stopgap.arn
}

resource "aws_iam_role" "_stopgap_ec2" {
  name               = "StopgapRole"
  assume_role_policy = data.aws_iam_policy_document.trust_relationships_ec2_policy.json
  tags               = var.common_tags
}

# End of EC2 

# CloudWatch
resource "aws_cloudwatch_event_rule" "console" {
  name                = var.cloudwatch_event_name
  description         = "Launches stopgap ec2 instances on schedule"
  schedule_expression = "cron(${var.run_schedule})"

  # TODO set to true when ready
  is_enabled = false
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.console.name
  arn  = aws_lambda_function.stopgap_ec2_launch.arn
}
# End of CloudWatch

# DynamoDB table with hash key 'ItemKey'

resource "aws_dynamodb_table" "_stopgap" {
  name             = lookup(var.secrets, "dynamodb_table_name")
  read_capacity    = 1
  write_capacity   = 5
  hash_key         = "ItemKey"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "ItemKey"
    type = "S"
  }

  tags = var.common_tags
}

# SNS Topic
resource "aws_sns_topic" "stopgap" {
  name = var.sns_topic_name
  tags = var.common_tags
}
# End of SNS Topic & Subscription

# Secrets Manager Secret
resource "aws_secretsmanager_secret" "secret" {
  name        = var.secret_name
  description = "Stopgap secret"
  # do not schedule for deletion (i.e. force delete of this secret when destroying the resource)
  recovery_window_in_days = 0
}
# Add list of secrets to the 'Secret'
resource "aws_secretsmanager_secret_version" "secrets" {
  secret_id     = aws_secretsmanager_secret.secret.id
  secret_string = jsonencode(var.secrets)
}
# End of Secret
