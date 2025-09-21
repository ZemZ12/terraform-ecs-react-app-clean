output "ecr_url" { value = aws_ecr_repository.app.repository_url }
output "alb_dns" { value = aws_lb.app.dns_name } 