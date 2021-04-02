output "secrets_arn" {
  value       = module.stopgap_cluster.secrets_arn
  description = "Update the secrets 'secretsArn' variable in 'vars.tf' with that arn value"
}

output "sns_topic_arn" {
  value       = module.stopgap_cluster.sns_topic_arn
  description = "Update the secrets 'snsTopicArn' variable in 'vars.tf' with that arn value"
}

