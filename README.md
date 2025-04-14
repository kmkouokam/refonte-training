This module spin up a vpc on AWS with all its components:
1- 2 pulic & pricate Subnets
2- 2 public & private route tables
public & private route table association
2 internet gateways
2 Elastic IPs
2 Nat gateways
2 providers AWS & Ramdom
Aws system parameter to store mysql password
subnet group for mysql
mysql server
db security group
Lambda aws_security_group
iam role for lambda
iam role for rds monitoring
RDS iam role monitoring attachment
aws_iam_policy_attachment
Lambda aws_iam_role_policy for vpc access
aws_lambda_function
Create a cloudWatch metric , cloudWatch log group & cloudWatch log stream


Just needs to run terraform plan  & apply

Author
Ernestine D Motouom