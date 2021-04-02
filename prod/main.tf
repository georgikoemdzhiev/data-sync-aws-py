provider "aws" {
  profile = "Prod"
  region  = "us-west-2"
}

module "stopgap_cluster" {
  source    = "../modules/db_table_rep"
  vpc_id    = "vpc-id"
  region    = "us-west-2"
  subnet_id = "subnet-id"
  secrets = {
    # Secrets needed for Aurora rds_client (i.e. used in the python script to connect to the db). Do not change the key names!
    dbInstanceIdentifier = "prod-db"
    engine               = "aurora-postgresql"
    host                 = "destination-db-host-name"
    port                 = "5432"
    resourceId           = "destination-db-id"
    username             = "destination-db-username"
    password             = "destination-db-password"
    # Common secrets
    dbName              = "postgres"
    auroraArn           = "destination-db-arn"
    SourceServer        = "source-server-url-or-ip"
    SourceDatabase      = "source-db-name"
    SourceDbUsername    = "source-db-username"
    SourceDbPassword    = "source-db-password"
    dynamodb_table_name = "stopgap"
    snsTopicArn         = "sns-topic-arn"
    secretsArn          = "the-secrets-arn-here"
  }
  secret_name = "stopgap-secrets"
  common_tags = {
    Contact    = "an_email_address"
    Service    = "stopgap"
    DeployedBy = "Terraform"
  }
  ami_image     = "custom-ami-id"
  key_pair_name = "stopgap-prod"
  bucket_name   = "stopgap-prod"
}

