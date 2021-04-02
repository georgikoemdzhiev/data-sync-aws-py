variable "vpc_id" {
  description = "The id of the VPC"
  type        = string
}
variable "region" {
  description = "The region"
  type        = string
}
variable "subnet_id" {
  description = "The sugnet (id) where the cluster will be created"
  type        = string
}

variable "secrets" {
  description = "Secrets map"
  type        = map(any)
}

variable "secret_name" {
  #   default = "stopgap-secrets"
  description = "The name of the Secrets Manager's Secret"
  type        = string
}

# LAMBDA VARIABLES
variable "lambda_function_name" {
  default     = "start-stopgap-ec2"
  description = "The name of the 'Start stopgap' lambda function"
  type        = string
}
variable "lambda_handler" {
  default     = "create_ec2.handler"
  description = "The region"
  type        = string
}
variable "lambda_runtime" {
  default = "python3.7"
}
variable "lambda_filename" {
  default = "create_ec2.zip"
}

variable "instance_type" {
  default = "t2.large"
}

variable "common_tags" {
  description = "Common tag list applied to all appropriate resources"
  type        = map(any)
}

variable "ami_image" {
  # Custom image AMI 'stopgap' PreProd
  description = "The AMI to be used by the EC2 instance"
  type        = string
}

variable "key_pair_name" {
  #   default = "stopgap-prod"
  description = "The key pair to be used to access the EC2 instance"
  type        = string
}

# S3 bucket containing the python script
variable "bucket_name" {
  #   default = "stopgap-prod"
  description = "The name of the bucket to store the python script"
  type        = string
}

variable "python_script_file_name" {
  default = "main.py"
}

variable "sns_topic_name" {
  default = "stopgap"
}

variable "cloudwatch_event_name" {
  default = "launch-stopgap-ec2-instance"
}

variable "run_schedule" {
  # run every day at 10 am GMT time
  default = "0 10 * * ? *"
}


