# AWS Demos Repository

This repository contains AWS infrastructure automation scripts, EKS cluster configurations, and PowerShell utilities for AWS resource management and cleanup.

## Repository Structure

```
demos.aws/
├── codebuild/          # AWS CodeBuild buildspec configurations
│   └── README.md       # Build and deployment pipeline documentation
├── eks/               # EKS cluster and Kubernetes resources
│   └── README.md       # EKS cluster setup and configuration guide
├── powershell/        # PowerShell scripts for AWS resource cleanup
│   └── README.md       # AWS cleanup scripts documentation
└── README.md          # This file
```

## Quick Overview

### EKS Infrastructure (`eks/`)
Production-ready EKS cluster configurations with multi-node group setup, auto-scaling, load balancing, and monitoring. See [eks/README.md](eks/README.md) for detailed setup instructions.

### CodeBuild Pipelines (`codebuild/`)
Build and deployment configurations for .NET applications and NPM packages with AWS CodeArtifact integration. See [codebuild/README.md](codebuild/README.md) for pipeline documentation.

### PowerShell Cleanup Scripts (`powershell/`)
Production-ready PowerShell utilities for cleaning up unused AWS resources (IAM policies, roles, security groups). See [powershell/README.md](powershell/README.md) for script documentation and usage.

## Prerequisites

- AWS CLI configured with appropriate permissions
- PowerShell 5.1+ (for cleanup scripts)
- `eksctl`, `kubectl`, and `helm` (for EKS infrastructure)

## Getting Started

1. **EKS Cluster**: Start with [eks/README.md](eks/README.md) for cluster setup
2. **Build Pipelines**: Review [codebuild/README.md](codebuild/README.md) for CI/CD configuration
3. **Resource Cleanup**: Use [powershell/README.md](powershell/README.md) for maintenance scripts

## Security Notice

⚠️ **Important**: The PowerShell scripts perform destructive operations on AWS resources. Always:
- Run with `-DryRun` first to review changes
- Test in non-production environments
- Review logs and confirmations before execution

## Contributing

When contributing:
1. Test scripts thoroughly in safe environments
2. Update relevant folder README files
3. Follow existing naming conventions
4. Include proper error handling and logging

## Support

For issues or questions:
1. Check the specific folder README for detailed documentation
2. Review script logs for error information
3. Verify AWS permissions and service quotas
4. Test in non-production environments first

---

**Note**: This repository contains production-ready AWS automation scripts. Ensure compliance with your organization's policies and AWS best practices.
