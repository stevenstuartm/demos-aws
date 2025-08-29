# EKS Cluster Infrastructure

This directory contains production-ready EKS cluster configurations with comprehensive Kubernetes infrastructure setup including auto-scaling, load balancing, monitoring, and security components.

## Overview

### What's Included
- **Multi-tier Node Groups**: Public ingress, services, and worker nodes
- **Auto Scaling**: Cluster autoscaler with proper IAM policies
- **Load Balancing**: ALB ingress controller with Route53 integration
- **Monitoring**: Metrics server and CloudWatch integration with FluentD
- **Security**: IAM roles, security groups, and RBAC configurations
- **Cost Optimization**: Spot instance worker nodes

### What's Not Included
- Terraform configurations for VPC and subnets
- Terraform for load balancer creation
- Application-specific deployments

## Prerequisites

### Required Tools
- **eksctl**: EKS cluster management tool
  - [Installation Guide](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html)
  - [eksctl.io Installation](https://eksctl.io/installation/)
- **kubectl**: Kubernetes command-line tool
- **helm**: Kubernetes package manager
  - [Installation Guide](https://helm.sh/docs/intro/install/)
- **AWS CLI**: Configured with appropriate permissions

### AWS Requirements
- AWS account with EKS permissions
- VPC with public and private subnets
- Dedicated IAM user for cluster management (recommended)

## Quick Start

### 1. Create EKS Cluster
```bash
# Create cluster without node groups first
eksctl create cluster -f cluster.yaml --without-nodegroup
```

**Important**: Use a dedicated IAM user (e.g., "eks-admin") for cluster creation to avoid access issues later.

### 2. Create Namespaces
```bash
kubectl create -f namespaces.yaml
```

### 3. Setup OIDC Provider
```bash
eksctl utils associate-iam-oidc-provider --cluster=demo --approve
```

### 4. Create Node Groups
```bash
# Public ingress nodes
eksctl create nodegroup -f node-groups/public-ingress.yaml

# Public services nodes  
eksctl create nodegroup -f node-groups/public-services.yaml

# Private worker nodes (spot instances)
eksctl create nodegroup -f node-groups/workers-spot-t2md.yaml
```

### 5. Deploy Core Components
```bash
# Metrics server
kubectl apply -f metrics/metrics-server.yaml

# Cluster autoscaler
kubectl apply -f autoscaler/autoscaler.yaml

# Load balancer controller
kubectl apply -f ingress/ingress-classes.yaml
```

## Detailed Setup Guide

### Node Group Configuration

#### Auto Scaling Group Tags
After creating each node group, tag the resulting Auto Scaling Group:

**Public Ingress:**
- Key: `k8s.io/cluster-autoscaler/node-template/label/tier` Value: `public-ingress`

**Public Services:**
- Key: `k8s.io/cluster-autoscaler/node-template/label/tier` Value: `public-services`

**Private Workers:**
- Key: `k8s.io/cluster-autoscaler/node-template/label/tier` Value: `workers`
- Key: `k8s.io/cluster-autoscaler/node-template/label/workerClass` Value: `spot-t2md`

#### Subnet Tags
Tag your subnets for load balancer integration:
- Key: `kubernetes.io/cluster/demo` Value: `shared`
- Key: `kubernetes.io/role/elb` Value: `1`

### Load Balancer Controller Setup

#### 1. Create IAM Policy
```bash
aws iam create-policy \
    --policy-name demo-eks-alb-controller-policy \
    --policy-document file://ingress/eks-alb-controller-policy.json
```

#### 2. Create Service Account
```bash
eksctl create iamserviceaccount \
  --cluster=demo \
  --namespace=kube-system \
  --name=demo-eks-alb-controller \
  --attach-policy-arn=arn:aws:iam::[account]:policy/demo-eks-alb-controller-policy \
  --override-existing-serviceaccounts \
  --approve
```

#### 3. Install Controller
```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=demo \
  --set serviceAccount.create=false \
  --set serviceAccount.name=demo-eks-alb-controller
```

#### 4. Deploy Ingress Resources
```bash
kubectl apply -f ingress/ingress-classes.yaml
kubectl apply -f ingress/services-ingress.yaml
```

### Monitoring and Logging

#### Metrics Server
```bash
kubectl apply -f metrics/metrics-server.yaml
```

#### CloudWatch Monitoring
The CloudWatchAgentServerPolicy should be automatically added to instance roles by eksctl.

#### FluentD Logging
```bash
curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml | sed "s/{{cluster_name}}/demo/;s/{{region_name}}/us-east-2/" | kubectl apply -f -
```

### Cluster Autoscaler

#### 1. Create IAM Policy
```bash
aws iam create-policy \
    --policy-name demo-eks-cluster-autoscaler-policy \
    --policy-document file://autoscaler/eks-cluster-autoscaler-policy.json
```

#### 2. Create Service Account
```bash
eksctl create iamserviceaccount \
  --cluster=demo \
  --namespace=kube-system \
  --name=cluster-autoscaler \
  --attach-policy-arn=arn:aws:iam::[account]:policy/demo-eks-cluster-autoscaler-policy \
  --override-existing-serviceaccounts \
  --approve
```

#### 3. Deploy Autoscaler
```bash
kubectl apply -f autoscaler/autoscaler.yaml
```

## Configuration Management

### Placeholder Values
All configuration files contain placeholders marked with `[brackets]` that need to be replaced:
- `[account]`: Your AWS account ID
- `[region]`: AWS region
- `[cluster-name]`: EKS cluster name
- Other environment-specific values

### Node Group IAM Roles
Each node group uses auto-generated IAM roles. Update these roles with the `node-groups/demo-eks-services-node-policy.json` policy for service-specific permissions.

## DNS Configuration

### Route53 Setup
For domains defined in ingress configurations, create Alias records pointing to the appropriate ALB:
- `api.demos.io` → demo-services ALB
- Add other domain mappings as needed

**Note**: External DNS automation is intentionally disabled for manual control.

## Troubleshooting

### Common Issues

#### RDS Connection Timeouts
If services experience RDS timeouts:
1. Identify the RDS instance security group
2. Identify the node group security group
3. Add inbound rule to RDS security group allowing access from node group security group

#### Node Group Access Issues
- Verify Auto Scaling Group tags are correctly applied
- Check subnet tags for load balancer integration
- Ensure IAM roles have necessary permissions

#### Load Balancer Controller Issues
- Verify service account exists and has correct permissions
- Check controller logs: `kubectl logs -n kube-system deployment/aws-load-balancer-controller`
- Ensure ingress classes are properly configured

### Verification Commands
```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Verify autoscaler
kubectl get pods -n kube-system | grep cluster-autoscaler

# Check load balancer controller
kubectl get pods -n kube-system | grep aws-load-balancer-controller

# Verify metrics server
kubectl top nodes
kubectl top pods
```

## Security Considerations

### IAM Best Practices
- Use dedicated IAM users for cluster management
- Implement least-privilege access
- Regularly rotate access keys
- Enable CloudTrail for audit logging

### Network Security
- Use private subnets for worker nodes
- Implement proper security group rules
- Consider VPC endpoints for AWS service access
- Enable VPC flow logs for network monitoring

### RBAC Configuration
- Configure proper RBAC roles and bindings
- Use service accounts for pod authentication
- Implement network policies for pod-to-pod communication

## Maintenance

### Regular Tasks
1. **Update Cluster**: Keep EKS control plane updated
2. **Node Group Updates**: Rotate node groups for security patches
3. **Component Updates**: Update metrics server, autoscaler, and controllers
4. **Security Audits**: Regular IAM and security group reviews

### Backup Strategy
- Backup etcd data (if using external etcd)
- Document cluster configuration
- Maintain application data backups
- Test disaster recovery procedures

## Cost Optimization

### Spot Instances
- Worker nodes use spot instances for cost savings
- Configure proper instance types and availability zones
- Monitor spot interruption rates

### Resource Management
- Implement proper resource requests and limits
- Use horizontal pod autoscaling
- Monitor and optimize cluster resource utilization
- Clean up unused resources regularly

## Support

For issues or questions:
1. Check AWS EKS documentation
2. Review component-specific logs
3. Verify IAM permissions and security groups
4. Test configurations in non-production environments first

---

**Note**: This configuration is designed for production use. Always test thoroughly and ensure compliance with your organization's security policies.
