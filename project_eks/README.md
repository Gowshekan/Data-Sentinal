# VirusProtect Cloud - AWS EKS Edition

**Cloud-native security scanning platform built on AWS EKS with OpenSearch-powered search capabilities**

<div align="center">

![AWS](https://img.shields.io/badge/AWS-EKS-orange)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28-blue)
![OpenSearch](https://img.shields.io/badge/OpenSearch-2.11-purple)
![Node.js](https://img.shields.io/badge/Node.js-20-green)

</div>

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      AWS Cloud Infrastructure                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐    ┌────────────────────────────────┐        │
│  │ CloudFront   │───▶│  S3 (React Frontend)           │        │
│  │ (CDN)        │    └────────────────────────────────┘        │
│  └──────────────┘                                               │
│                                                                   │
│  ┌──────────────┐    ┌────────────────────────────────┐        │
│  │ Route 53     │───▶│  Application Load Balancer     │        │
│  │ (DNS)        │    └──────────┬─────────────────────┘        │
│  └──────────────┘               │                               │
│                                  ▼                               │
│         ┌────────────────────────────────────────┐              │
│         │        EKS Cluster (K8s 1.28)          │              │
│         │  ┌──────────────────────────────────┐  │              │
│         │  │  Microservices:                  │  │              │
│         │  │  • scan-api (REST API)           │  │              │
│         │  │  • scan-worker (Queue processor) │  │              │
│         │  │  • secret-detector               │  │              │
│         │  │  • web-monitor                   │  │              │
│         │  │  • ai-analyzer                   │  │              │
│         │  │  • report-generator              │  │              │
│         │  │  • search-indexer (OpenSearch)   │  │              │
│         │  └──────────────────────────────────┘  │              │
│         │                                         │              │
│         │  Auto-scaling: 2-50 pods (HPA + CA)    │              │
│         └────────────────────────────────────────┘              │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Data Layer                            │   │
│  │  • RDS PostgreSQL (Metadata, users, history)            │   │
│  │  • OpenSearch 2.11 (Full-text search, analytics) ⭐     │   │
│  │  • ElastiCache Redis (Caching, rate limiting)           │   │
│  │  • DynamoDB (Session storage, fast lookups)             │   │
│  │  • S3 Buckets (File uploads, quarantine, reports)       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Queue & Event Processing                    │   │
│  │  • SQS (Async scan queue, dead-letter queue)            │   │
│  │  • SNS (Notifications, alerts)                           │   │
│  │  • EventBridge (Scheduled scans, automation)            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Security & Monitoring                       │   │
│  │  • Cognito (Authentication, user management)             │   │
│  │  • Secrets Manager (API keys, credentials)              │   │
│  │  • CloudWatch (Logs, metrics, alarms)                   │   │
│  │  • X-Ray (Distributed tracing)                           │   │
│  │  • AWS WAF (DDoS protection)                             │   │
│  │  • GuardDuty (Threat detection)                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Key Cloud Features

### ⚡ Distributed Scanning System
- **Horizontal scaling**: 2-50 worker pods based on SQS queue depth
- **Parallel processing**: Handle 1000+ concurrent scans
- **Smart caching**: Redis-cached hash lookups (99% hit rate)
- **Async architecture**: Upload → S3 → Lambda → SQS → EKS workers

### 🔍 OpenSearch-Powered Search Engine ⭐
The core search feature of the cloud version:

- **Full-text search** across all scan history, threats, and AI analysis
- **Advanced filtering**: Date ranges, threat levels, file types, users
- **Real-time analytics**: Threat trends, risk distributions, statistics
- **Semantic search**: Vector embeddings with AWS Bedrock Titan
- **Kibana dashboards**: Visual threat intelligence
- **Auto-complete**: Smart suggestions for queries
- **Faceted search**: Multi-dimensional filtering

### 🌐 Multi-Tenancy
- User workspaces with isolated data
- Organization-level permissions
- API key management per user
- Usage quotas and billing integration

### 🤖 Enhanced AI Integration
- **AWS Bedrock**: Claude, Titan models without API key management
- **SageMaker**: Custom malware detection models
- **Batch processing**: Cost-optimized AI analysis
- **Model versioning**: A/B testing for threat analysis

### 📊 Real-Time Monitoring
- WebSocket API for live scan status
- CloudWatch dashboards with custom metrics
- X-Ray distributed tracing
- SNS notifications for critical threats

---

## 📁 Project Structure

```
project_eks/
├── infrastructure/           # Terraform IaC
│   ├── main.tf              # Main configuration
│   ├── eks.tf               # EKS cluster
│   ├── rds.tf               # PostgreSQL database
│   ├── opensearch.tf        # OpenSearch domain
│   ├── s3.tf                # S3 buckets
│   ├── sqs.tf               # SQS queues
│   ├── redis.tf             # ElastiCache Redis
│   ├── networking.tf        # VPC, subnets, security groups
│   ├── iam.tf               # IAM roles and policies
│   └── variables.tf         # Input variables
│
├── kubernetes/              # K8s manifests
│   ├── scan-api/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── hpa.yaml
│   │   └── ingress.yaml
│   ├── scan-worker/
│   ├── secret-detector/
│   ├── web-monitor/
│   ├── ai-analyzer/
│   ├── report-generator/
│   ├── search-indexer/
│   ├── configmaps/
│   │   └── app-config.yaml
│   └── secrets/
│       └── app-secrets.yaml.example
│
├── services/                # Microservices source code
│   ├── scan-api/
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── src/
│   │       ├── index.js
│   │       ├── routes/
│   │       ├── controllers/
│   │       └── middleware/
│   ├── scan-worker/
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── src/
│   │       ├── worker.js
│   │       ├── virusTotal.js
│   │       └── hashCache.js
│   ├── secret-detector/
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── src/
│   │       ├── detector.js
│   │       └── patterns.js
│   ├── web-monitor/
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── src/
│   │       └── monitor.js
│   ├── ai-analyzer/
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── src/
│   │       ├── analyzer.js
│   │       └── bedrock.js
│   ├── report-generator/
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── src/
│   │       └── generator.js
│   └── search-indexer/
│       ├── Dockerfile
│       ├── package.json
│       └── src/
│           ├── indexer.js
│           ├── search.js
│           └── aggregations.js
│
├── .github/
│   └── workflows/
│       ├── deploy-eks.yml   # Main deployment pipeline
│       ├── build-images.yml # Docker image builds
│       └── terraform.yml    # Infrastructure updates
│
├── docs/
│   ├── ARCHITECTURE.md      # Detailed architecture
│   ├── DEPLOYMENT.md        # Deployment guide
│   ├── API.md               # API documentation
│   └── SEARCH.md            # OpenSearch integration guide
│
└── README.md               # This file
```

---

## 🛠️ Prerequisites

- **AWS Account** with appropriate permissions
- **AWS CLI** v2.x configured
- **kubectl** v1.28+
- **eksctl** v0.165+
- **Terraform** v1.6+ (or AWS CDK)
- **Docker** v24+
- **Node.js** v20+
- **Git**

### Install Tools (Windows)
```powershell
# Using Chocolatey
choco install awscli kubernetes-cli eksctl terraform docker-desktop nodejs git -y

# Or using winget
winget install Amazon.AWSCLI Kubernetes.kubectl eksctl HashiCorp.Terraform Docker.DockerDesktop OpenJS.NodeJS Git.Git
```

---

## 🚀 Quick Start

### 1. Clone & Configure

```bash
cd project_eks

# Configure AWS credentials
aws configure
# Enter your AWS Access Key ID, Secret Key, and Region (e.g., us-east-1)

# Set required environment variables
export TF_VAR_vt_api_key="your_virustotal_api_key"
export TF_VAR_project_name="virusprotect"
export TF_VAR_environment="production"
```

### 2. Deploy Infrastructure with Terraform

```bash
cd infrastructure

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy infrastructure (takes ~20-30 minutes)
terraform apply -auto-approve

# Get outputs (RDS endpoint, OpenSearch domain, EKS cluster name)
terraform output
```

### 3. Configure kubectl for EKS

```bash
# Update kubeconfig
aws eks update-kubeconfig --name virusprotect-cluster --region us-east-1

# Verify connection
kubectl get nodes
```

### 4. Build & Push Docker Images

```bash
# Login to Amazon ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com

# Build and push all services
cd services

for service in scan-api scan-worker secret-detector web-monitor ai-analyzer report-generator search-indexer; do
  cd $service
  docker build -t virusprotect/$service:latest .
  docker tag virusprotect/$service:latest $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com/virusprotect/$service:latest
  docker push $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com/virusprotect/$service:latest
  cd ..
done
```

### 5. Deploy Kubernetes Resources

```bash
cd kubernetes

# Create namespace
kubectl create namespace virusprotect

# Create secrets (replace with actual values)
kubectl create secret generic app-secrets \
  --from-literal=vt-api-key=$VT_API_KEY \
  --from-literal=database-url=$DATABASE_URL \
  --from-literal=opensearch-username=admin \
  --from-literal=opensearch-password=$OS_PASSWORD \
  -n virusprotect

# Apply ConfigMaps
kubectl apply -f configmaps/ -n virusprotect

# Deploy all services
kubectl apply -f scan-api/ -n virusprotect
kubectl apply -f scan-worker/ -n virusprotect
kubectl apply -f secret-detector/ -n virusprotect
kubectl apply -f web-monitor/ -n virusprotect
kubectl apply -f ai-analyzer/ -n virusprotect
kubectl apply -f report-generator/ -n virusprotect
kubectl apply -f search-indexer/ -n virusprotect

# Verify deployments
kubectl get pods -n virusprotect
kubectl get svc -n virusprotect
```

### 6. Access the Application

```bash
# Get Load Balancer URL
kubectl get ingress -n virusprotect

# Or get ALB endpoint
kubectl get svc scan-api-service -n virusprotect -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## 🔍 OpenSearch Integration

### Initialize OpenSearch Indices

```bash
# Run the indexer initialization
kubectl exec -it deployment/search-indexer -n virusprotect -- node src/init-indices.js
```

### Access Kibana Dashboard

```bash
# Get OpenSearch domain endpoint
aws opensearch describe-domain --domain-name virusprotect-search --query 'DomainStatus.Endpoint' --output text

# Open in browser: https://<opensearch-endpoint>/_dashboards
```

### Example Search Queries

```javascript
// Full-text search
GET /scans/_search
{
  "query": {
    "multi_match": {
      "query": "trojan malware",
      "fields": ["fileName", "threats", "aiSummary"]
    }
  }
}

// Filter by risk level and date
GET /scans/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "riskLevel": "critical" } },
        { "range": { "scanTimestamp": { "gte": "now-7d" } } }
      ]
    }
  }
}

// Aggregations for dashboard
GET /scans/_search
{
  "size": 0,
  "aggs": {
    "top_threats": {
      "terms": { "field": "threats.keyword", "size": 10 }
    },
    "scans_per_day": {
      "date_histogram": {
        "field": "scanTimestamp",
        "calendar_interval": "day"
      }
    }
  }
}
```

---

## 📊 Monitoring & Observability

### CloudWatch Dashboards

Access CloudWatch dashboards:
```bash
aws cloudwatch list-dashboards --region us-east-1
```

Key metrics:
- **Scan throughput**: Scans/minute
- **Queue depth**: SQS messages visible
- **API latency**: P50, P95, P99
- **Error rates**: 4xx, 5xx responses
- **Pod metrics**: CPU, memory, restarts

### View Logs

```bash
# API logs
kubectl logs -f deployment/scan-api -n virusprotect

# Worker logs
kubectl logs -f deployment/scan-worker -n virusprotect

# All pods with label
kubectl logs -l app=scan-api -n virusprotect --tail=100
```

### X-Ray Tracing

Enable X-Ray daemon:
```bash
kubectl apply -f https://github.com/aws/aws-xray-daemon/releases/latest/download/xray-daemon-k8s.yaml
```

---

## 🔧 Configuration

### Environment Variables

Create `kubernetes/configmaps/app-config.yaml`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  NODE_ENV: production
  LOG_LEVEL: info
  REDIS_URL: redis://virusprotect-redis.abc123.0001.use1.cache.amazonaws.com:6379
  OPENSEARCH_ENDPOINT: https://search-virusprotect-abc123.us-east-1.es.amazonaws.com
  SQS_QUEUE_URL: https://sqs.us-east-1.amazonaws.com/123456789012/virusprotect-scan-queue
  S3_UPLOAD_BUCKET: virusprotect-uploads-prod
  S3_QUARANTINE_BUCKET: virusprotect-quarantine-prod
  S3_REPORTS_BUCKET: virusprotect-reports-prod
  MAX_FILE_SIZE: "104857600"  # 100MB
  SCAN_TIMEOUT: "300"  # 5 minutes
  ENABLE_AI_ANALYSIS: "true"
  AI_PROVIDER: bedrock
  AWS_REGION: us-east-1
```

### Secrets

Never commit secrets! Create from environment:
```bash
kubectl create secret generic app-secrets \
  --from-literal=vt-api-key=$VT_API_KEY \
  --from-literal=database-url="postgresql://admin:password@virusprotect-db.abc123.us-east-1.rds.amazonaws.com:5432/virusprotect" \
  --from-literal=opensearch-username=admin \
  --from-literal=opensearch-password=$OS_PASSWORD \
  --from-literal=jwt-secret=$(openssl rand -base64 32) \
  -n virusprotect
```

---

## 🔄 CI/CD Pipeline

### GitHub Actions Workflow

The pipeline automatically:
1. Builds Docker images on push to `main`
2. Pushes images to Amazon ECR
3. Updates Kubernetes deployments
4. Runs health checks

Configure secrets in GitHub:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `EKS_CLUSTER_NAME`
- `VT_API_KEY`

---

## 📈 Scaling

### Horizontal Pod Autoscaler (HPA)

```bash
# Check HPA status
kubectl get hpa -n virusprotect

# Manually scale
kubectl scale deployment scan-worker --replicas=10 -n virusprotect
```

### Cluster Autoscaler

Automatically adds/removes nodes based on pod demand:
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
```

---

## 💰 Cost Optimization

Current setup estimated costs (us-east-1):
- **EKS cluster**: $73/month (control plane)
- **EC2 nodes**: ~$150/month (3x t3.medium)
- **RDS PostgreSQL**: ~$30/month (db.t3.micro)
- **OpenSearch**: ~$100/month (t3.medium.search x2)
- **ElastiCache Redis**: ~$15/month (cache.t3.micro)
- **S3**: ~$5/month (100GB storage)
- **Data transfer**: ~$20/month

**Total: ~$393/month** (before spot instances)

### Savings Strategies:
1. **Use Spot Instances** for workers (50-70% savings)
2. **Reserved Instances** for RDS/ElastiCache (40% savings)
3. **S3 Intelligent-Tiering** for old scans
4. **Lambda** for infrequent tasks
5. **CloudFront caching** to reduce backend load

---

## 🔒 Security Best Practices

- ✅ All data encrypted at rest (KMS)
- ✅ TLS/SSL for all connections
- ✅ VPC isolation with private subnets
- ✅ IAM roles for pods (IRSA)
- ✅ Secrets Manager for sensitive data
- ✅ AWS WAF for DDoS protection
- ✅ GuardDuty for threat detection
- ✅ Regular security patches (automated)

---

## 🧪 Testing

### Local Development

```bash
# Run services locally with Docker Compose
cd services
docker-compose up

# Or run individual service
cd scan-api
npm install
npm run dev
```

### Load Testing

```bash
# Install k6
choco install k6

# Run load test
k6 run docs/load-test.js
```

---

## 🐛 Troubleshooting

### Pods not starting
```bash
kubectl describe pod <pod-name> -n virusprotect
kubectl logs <pod-name> -n virusprotect
```

### OpenSearch connection issues
```bash
# Test connectivity from pod
kubectl exec -it deployment/scan-api -n virusprotect -- curl -u admin:password https://opensearch-endpoint/_cluster/health
```

### Database connection errors
```bash
# Verify RDS endpoint
aws rds describe-db-instances --db-instance-identifier virusprotect-db

# Test from pod
kubectl exec -it deployment/scan-api -n virusprotect -- psql $DATABASE_URL
```

---

## 📚 Documentation

- [Architecture Details](docs/ARCHITECTURE.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [API Reference](docs/API.md)
- [OpenSearch Integration](docs/SEARCH.md)

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test locally
4. Submit a pull request

---

## 📝 License

MIT License - See [LICENSE](../LICENSE) for details

---

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/virusprotect/issues)
- **Docs**: [Documentation](docs/)
- **Email**: support@virusprotect.com

---

**Built with ❤️ for cloud-native security scanning**
