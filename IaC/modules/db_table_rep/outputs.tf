output "secrets_arn" {
  value       = aws_secretsmanager_secret.secret.arn
  description = "Update the secrets 'secretsArn' variable in 'vars.tf' with that arn value"
}

output "sns_topic_arn" {
  value       = aws_sns_topic.stopgap.arn
  description = "Update the secrets 'snsTopicArn' variable in 'vars.tf' with that arn value"
}
