# terraform-ecs-react-app-clean

**Infrastructure-as-Code + Containerized React App on AWS using Terraform & ECS Fargate**

---

## Table of Contents

1. [Project Overview](#project-overview)  
2. [Architecture Diagram](#architecture-diagram)  
3. [Getting Started](#getting-started)  
4. [Deployment Steps](#deployment-steps)  
5. [Error Log & Resolutions](#error-log--resolutions)  
6. [Thought Process & Design Decisions](#thought-process--design-decisions)  
7. [Monitoring & Reliability](#monitoring--reliability)  
8. [Cleanup / Teardown](#cleanup--teardown)  
9. [Future Improvements](#future-improvements)  
10. [Contributors / License](#contributors--license)

---

## Project Overview

This project demonstrates deploying a **React frontend** (Dockerized) on AWS ECS Fargate, managed via Terraform. The infrastructure is set up as a **three-tier architecture** including:

- VPC, public and private subnets  
- Internet Gateway, NAT Gateway  
- Security groups  
- ECS cluster, task definitions, and services  
- Application Load Balancer (ALB) in front of the React app  
- Logging & health checks (via AWS CloudWatch + ALB)  

This repo is structured as:


---

## Architecture Diagram

*(Add a diagram image here if available)*

- Public subnet(s) hosting the ALB  
- Private subnet(s) for ECS tasks  
- NAT Gateway (if needed)  
- Security group rules: ALB → ECS tasks on port 80/3000  
- Load balancer health checks  
- IAM roles & permissions for ECS, ECR, etc.

---

## Getting Started

### Prerequisites

- AWS CLI configured with appropriate credentials & region  
- Terraform (version ≥ 1.x)  
- Docker  
- Node.js / npm or yarn  
- Git  

### Clone & Initialize
```bash
git clone https://github.com/ZemZ12/terraform-ecs-react-app-clean.git
cd terraform-ecs-react-app-clean
```

## Deployment Steps

1. **Build React app and Docker image**
```
   cd app
   npm install
   npm run build
   docker build -t my-react-app:latest .
aws ecr create-repository --repository-name my-react-app || true
$(aws ecr get-login --no-include-email)
docker tag my-react-app:latest <AWS_ACCOUNT_ID>.dkr.ecr.<region>.amazonaws.com/my-react-app:latest
docker push <AWS_ACCOUNT_ID>.dkr.ecr.<region>.amazonaws.com/my-react-app:latest

cd infra
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

## Error Log & Resolutions

Here are the main errors we encountered and how we solved them during development and deployment:

| Issue | Description / Error Message | Root Cause | Fix / Resolution |
|---|---|---|---|
| **Task fails to start; “CannotPullContainerError”** | ECS reports it cannot pull the container | ECR image not properly tagged, or IAM policy missing | Ensure correct ECR URI tag, and attach `AmazonEC2ContainerRegistryReadOnly` permission to the task execution role |
| **ALB health checks constantly failing** | ECS tasks deemed unhealthy and replaced | Health check path / port misconfigured, or app not listening on that port | Adjust ALB health check path (e.g. `/`) and port to match container’s exposed port; confirm container’s server startup |
| **Terraform “cycle” or dependency error** | Terraform plan/apply complains about cyclic dependencies or missing references | Incorrect resource dependencies or ordering | Use `depends_on` or refactor modules so dependencies are explicit |
| **Subnet or IGW networking errors** | No internet access or “Subnet is not public” errors | Missing route for public subnet or missing Internet Gateway attachment | Add proper `route_table` entries to public subnets, ensure IGW is attached |
| **Docker build context issues** | Docker build failing to COPY build artifacts | Wrong `WORKDIR` or missing `.dockerignore` rules | Adjust Dockerfile COPY paths and confirm context |




