output "rds_endpoint" {
  value = aws_db_instance.mysql_db[*].endpoint
}

output "database_name" {
  value = aws_db_instance.mysql_db[*].db_name
}

output "lambda_function_name" {
  value = aws_lambda_function.hello_world[*].function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.hello_world[*].arn
}
