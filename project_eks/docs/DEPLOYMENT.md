# VirusProtect Cloud - Deployment Guide

Complete guide for deploying VirusProtect on AWS EKS with OpenSearch-powered search capabilities.

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Infrastructure Deployment](#infrastructure-deployment)
4. [Kubernetes Configuration](#kubernetes-configuration)
5. [Application Deployment](#application-deployment)
6. [OpenSearch Setup](#opensearch-setup)
7. [Verification](#verification)
8. [Troubleshooting](#troubleshooting)
9. [Monitoring](#monitoring)
10. [Scaling](#scaling)

---

## Prerequisites

### Required Tools

Install the following tools before starting:

```powershell
# Using Chocolatey (Windows)
choco install awscli kubernetes-cli eksctl terraform docker-desktop nodejs git -y

# Verify installations
aws --version          # Should be v2.x
kubectl version --client
eksctl version
terraform version      # Should be v1.6+
docker --version
node --version         # Should be v20+
```

### AWS Account Requirements

- AWS Account with admin or appropriate IAM permissions
- Sufficient service quotas:
  - EKS: 1 cluster
  - EC2: 10 instances (for nodes)
  - EBS: 1 TB storage
  - S3: 3 buckets
  - RDS: 1 PostgreSQL instance
  - OpenSearch: 1 domain
  - ElastiCache: 1 Redis cluster

### Required Secrets

Prepare these values before deployment:

1. **VirusTotal API Key**: Get from https://www.virustotal.com/gui/my-apikey
2. **AWS Credentials**: Access Key ID and Secret Access Key
3. **Database Password**: Strong password for RDS (auto-generated if not provided)
4. **OpenSearch Password**: Strong password for OpenSearch (auto-generated if not provided)

---

## Initial Setup

### 1. Configure AWS CLI

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Default region: us-east-1
# Default output format: json
```

### 2. Set Environment Variables

```bash
# Windows (PowerShell)
$env:TF_VAR_vt_api_key="your_virustotal_api_key"
$env:AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Linux/Mac
export TF_VAR_vt_api_key="your_virustotal_api_key"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

### 3. Create Terraform State Backend

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://virusprotect-terraform-state --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket virusprotect-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name virusprotect-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

---

## Infrastructure Deployment

### 1. Initialize Terraform

```bash
cd infrastructure

terraform init
```

### 2. Review Infrastructure Plan

```bash
terraform plan -out=tfplan
```

Review the plan carefully. It will create:
- VPC with public/private subnets
- EKS cluster with 2 node groups
- RDS PostgreSQL database
- OpenSearch domain
- ElastiCache Redis cluster
- S3 buckets (uploads, quarantine, reports)
- SQS queues
- SNS topics
- IAM roles and policies

### 3. Apply Infrastructure

```bash
# This takes 20-30 minutes
terraform apply tfplan
```

### 4. Save Outputs

```bash
terraform output > ../outputs.txt
```

---

## Kubernetes Configuration

### 1. Update kubeconfig

```bash
aws eks update-kubeconfig --name virusprotect-cluster --region us-east-1

# Verify connection
kubectl get nodes
```

### 2. Install Required Controllers

#### AWS Load Balancer Controller

```bash
# Download IAM policy
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

# Create IAM policy
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json

# Install using Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=virusprotect-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::${AWS_ACCOUNT_ID}:role/virusprotect-aws-load-balancer-controller
```

#### Cluster Autoscaler

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

# Annotate service account
kubectl annotate serviceaccount cluster-autoscaler \
  -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/virusprotect-cluster-autoscaler
```

### 3. Create Namespace and RBAC

```bash
cd ../kubernetes

kubectl apply -f namespace-rbac.yaml
```

### 4. Create Secrets

```bash
# Get credentials from Terraform outputs or AWS Secrets Manager
DATABASE_URL="postgresql://username:password@rds-endpoint:5432/virusprotect"
OPENSEARCH_PASSWORD="your_opensearch_password"

# Create Kubernetes secret
kubectl create secret generic app-secrets \
  --from-literal=VT_API_KEY="${TF_VAR_vt_api_key}" \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --from-literal=OPENSEARCH_USERNAME="admin" \
  --from-literal=OPENSEARCH_PASSWORD="${OPENSEARCH_PASSWORD}" \
  --from-literal=JWT_SECRET="$(openssl rand -base64 32)" \
  -n virusprotect
```

### 5. Update ConfigMaps

Edit `configmaps/app-config.yaml` with actual values from Terraform outputs:

```yaml
# Update these values:
REDIS_HOST: "<redis-endpoint-from-terraform>"
OPENSEARCH_ENDPOINT: "https://<opensearch-endpoint-from-terraform>"
SQS_QUEUE_URL: "<sqs-url-from-terraform>"
S3_UPLOAD_BUCKET: "<upload-bucket-from-terraform>"
# ... etc
```

Apply ConfigMaps:

```bash
kubectl apply -f configmaps/app-config.yaml -n virusprotect
```

---

## Application Deployment

### 1. Create ECR Repositories

```bash
for service in scan-api scan-worker search-indexer; do
  aws ecr create-repository --repository-name virusprotect/$service --region us-east-1
done
```

### 2. Build and Push Docker Images

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com

# Build and push scan-api
cd ../services/scan-api
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/virusprotect/scan-api:latest .
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/virusprotect/scan-api:latest

# Build and push scan-worker
cd ../scan-worker
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/virusprotect/scan-worker:latest .
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/virusprotect/scan-worker:latest

# Build and push search-indexer
cd ../search-indexer
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/virusprotect/search-indexer:latest .
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/virusprotect/search-indexer:latest
```

### 3. Update Kubernetes Manifests

Replace `<AWS_ACCOUNT_ID>` in all deployment files:

```bash
cd ../../kubernetes

# Linux/Mac
find . -name "*.yaml" -type f -exec sed -i "s/<AWS_ACCOUNT_ID>/${AWS_ACCOUNT_ID}/g" {} +

# Windows (PowerShell)
Get-ChildItem -Path . -Filter *.yaml -Recurse | ForEach-Object {
    (Get-Content $_.FullName) -replace '<AWS_ACCOUNT_ID>', $env:AWS_ACCOUNT_ID | Set-Content $_.FullName
}
```

### 4. Deploy Services

```bash
# Deploy scan-api
kubectl apply -f scan-api/ -n virusprotect

# Deploy scan-worker
kubectl apply -f scan-worker/ -n virusprotect

# Deploy search-indexer
kubectl apply -f search-indexer/ -n virusprotect

# Verify deployments
kubectl get pods -n virusprotect -w
```

---

## OpenSearch Setup

### 1. Initialize Indices

```bash
# Run the init script from search-indexer pod
kubectl exec -it deployment/search-indexer -n virusprotect -- npm run init-indices
```

### 2. Access OpenSearch Dashboards

```bash
# Get OpenSearch endpoint
OPENSEARCH_ENDPOINT=$(terraform output -raw opensearch_endpoint)

echo "OpenSearch Dashboards: https://${OPENSEARCH_ENDPOINT}/_dashboards"
```

Login with:
- Username: `admin`
- Password: From Secrets Manager or Terraform output

### 3. Import Dashboards (Optional)

Navigate to Dashboards → Management → Saved Objects → Import

---

## Verification

### 1. Check All Pods

```bash
kubectl get pods -n virusprotect

# All pods should be Running with 1/1 Ready
```

### 2. Check Services

```bash
kubectl get svc -n virusprotect

# Note the EXTERNAL-IP for scan-api-service
```

### 3. Test Health Endpoints

```bash
API_URL=$(kubectl get svc scan-api-service -n virusprotect -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl http://${API_URL}/health
curl http://${API_URL}/ready
```

### 4. Test File Upload

```bash
# Create a test file
echo "test content" > test.txt

# Upload for scanning
curl -X POST http://${API_URL}/api/scan/file \
  -F "file=@test.txt" \
  -H "x-user-id: test-user"
```

### 5. Check Logs

```bash
# API logs
kubectl logs -f deployment/scan-api -n virusprotect

# Worker logs
kubectl logs -f deployment/scan-worker -n virusprotect

# Search indexer logs
kubectl logs -f deployment/search-indexer -n virusprotect
```

---

## Troubleshooting

### Pods Not Starting

```bash
kubectl describe pod <pod-name> -n virusprotect
kubectl logs <pod-name> -n virusprotect
```

### Database Connection Issues

```bash
# Test from pod
kubectl exec -it deployment/scan-api -n virusprotect -- sh
# Inside pod:
# curl -v telnet://<rds-endpoint>:5432
```

### OpenSearch Connection Issues

```bash
# Test from pod
kubectl exec -it deployment/search-indexer -n virusprotect -- sh
# Inside pod:
# curl -u admin:password https://<opensearch-endpoint>/_cluster/health
```

### SQS Not Processing

```bash
# Check queue
aws sqs get-queue-attributes \
  --queue-url <queue-url> \
  --attribute-names All

# Check worker logs
kubectl logs -f deployment/scan-worker -n virusprotect
```

---

## Monitoring

### CloudWatch Dashboards

```bash
# Create custom dashboard
aws cloudwatch put-dashboard \
  --dashboard-name VirusProtect \
  --dashboard-body file://cloudwatch-dashboard.json
```

### View Metrics

```bash
# API metrics
kubectl port-forward deployment/scan-api 9090:9090 -n virusprotect
# Visit http://localhost:9090/metrics
```

---

## Scaling

### Manual Scaling

```bash
# Scale API
kubectl scale deployment scan-api --replicas=10 -n virusprotect

# Scale workers
kubectl scale deployment scan-worker --replicas=20 -n virusprotect
```

### Adjust HPA

```bash
# Edit HPA
kubectl edit hpa scan-worker-hpa -n virusprotect

# Change maxReplicas, target CPU, etc.
```

---

## Cleanup

To destroy all resources:

```bash
# Delete Kubernetes resources
kubectl delete namespace virusprotect

# Destroy infrastructure
cd infrastructure
terraform destroy -auto-approve
```

---

## Next Steps

- Configure custom domain with Route 53
- Set up CloudFront CDN
- Enable AWS WAF
- Configure SNS email notifications
- Set up monitoring alerts
- Implement backup strategy

---

For support, see [README.md](../README.md) or open an issue.
