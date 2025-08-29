# AWS CodeBuild Pipeline Configurations

This directory contains AWS CodeBuild buildspec configurations for building and deploying .NET applications and NPM packages with AWS CodeArtifact integration.

## Build Configurations

### Build Pipelines

#### `build-dotnet-eks-service.yaml`
Builds .NET services for deployment to EKS clusters with CodeArtifact integration.

**Features:**
- .NET 8.0 runtime support
- AWS CodeArtifact integration for private NuGet packages
- Automated testing with TRX reporting
- Version management and artifact storage
- Clean build artifacts for efficient storage

**Build Process:**
1. **Install Phase**: Sets up .NET 8.0 and CodeArtifact credential provider
2. **Pre-build**: Configures CodeArtifact source and reads version information
3. **Build**: Restores packages, builds solution, runs tests
4. **Artifacts**: Creates clean artifact package for deployment

**Key Components:**
- CodeArtifact domain: `demo-domain`
- Repository: `demo-nuget`
- Test reporting: Visual Studio TRX format
- Artifact naming: `{version}-pre{buildNumber}.zip`

#### `build-dotnet-nuget-package.yaml`
Creates and publishes NuGet packages to CodeArtifact repository.

**Features:**
- NuGet package creation and publishing
- CodeArtifact repository integration
- Version management
- Package validation

### Deployment Pipelines

#### `deploy-dotnet-eks-service.yaml`
Deploys .NET services to EKS clusters.

**Features:**
- EKS service deployment
- Kubernetes manifest application
- Service configuration management
- Health checks and monitoring

#### `deploy-dotnet-nuget-package.yaml`
Deploys NuGet packages to production repositories.

**Features:**
- Package promotion to production
- Repository management
- Version control

#### `deploy-npm-cloudfront-website.yaml`
Deploys NPM packages to CloudFront for static website hosting.

**Features:**
- NPM package deployment
- CloudFront distribution management
- Static website hosting
- CDN configuration

## Prerequisites

### AWS Services
- **CodeBuild**: For build execution
- **CodeArtifact**: For package management
- **EKS**: For service deployment
- **CloudFront**: For static website hosting
- **S3**: For artifact storage

### Required Permissions
The CodeBuild service role needs permissions for:
- `codeartifact:GetAuthorizationToken`
- `codeartifact:GetRepositoryEndpoint`
- `codeartifact:PublishPackageVersion`
- `eks:DescribeCluster`
- `eks:UpdateClusterConfig`
- `cloudfront:CreateDistribution`
- `s3:PutObject`, `s3:GetObject`

### Environment Setup
1. **CodeArtifact Domain**: Create domain `demo-domain`
2. **NuGet Repository**: Create repository `demo-nuget`
3. **EKS Cluster**: Ensure cluster is accessible
4. **S3 Bucket**: Configure artifact storage bucket

## Configuration Details

### CodeArtifact Integration
```yaml
# CodeArtifact source configuration
export demo_nuget_source=$(aws codeartifact get-repository-endpoint --domain demo-domain --domain-owner $DEMO_ACCOUNT --repository demo-nuget --format nuget --query repositoryEndpoint --output text)"v3/index.json"
export demo_nuget_token=$(aws codeartifact get-authorization-token --duration-seconds 900 --domain "demo-domain" --domain-owner $DEMO_ACCOUNT --query authorizationToken --output text)
dotnet nuget add source -n codeartifact $demo_nuget_source
```

### Version Management
```yaml
# Version handling
releaseVersion=$(pwsh -Command '(Get-Content version | Out-String).Trim()')
prereleaseVersion=$releaseVersion-pre$CODEBUILD_BUILD_NUMBER
```

### Test Reporting
```yaml
# Test execution with reporting
dotnet test **/*.Tests.csproj --logger trx --results-directory ./testresults
```

## Usage

### Creating CodeBuild Projects
1. **Build Project**: Use `build-dotnet-eks-service.yaml` for service builds
2. **Deploy Project**: Use `deploy-dotnet-eks-service.yaml` for deployments
3. **Package Project**: Use `build-dotnet-nuget-package.yaml` for package creation

### Build Triggers
- **Source Code Changes**: Trigger builds on code commits
- **Manual Execution**: Run builds manually via AWS Console or CLI
- **Scheduled Builds**: Configure periodic builds for testing

### Environment Variables
Configure these environment variables in your CodeBuild project:
- `DEMO_ACCOUNT`: AWS account ID
- `EKS_CLUSTER_NAME`: Target EKS cluster name
- `EKS_REGION`: AWS region for EKS cluster
- `CODEARTIFACT_DOMAIN`: CodeArtifact domain name
- `CODEARTIFACT_REPOSITORY`: CodeArtifact repository name

## Best Practices

### Build Optimization
1. **Use Build Cache**: Configure S3 cache for faster builds
2. **Parallel Testing**: Run tests in parallel when possible
3. **Artifact Cleanup**: Remove unnecessary files before artifact creation
4. **Dependency Caching**: Cache NuGet packages between builds

### Security
1. **IAM Roles**: Use least-privilege IAM roles for CodeBuild
2. **Secrets Management**: Use AWS Secrets Manager for sensitive data
3. **Network Security**: Configure VPC for private builds if needed
4. **Artifact Security**: Encrypt artifacts and use secure S3 buckets

### Monitoring
1. **Build Logs**: Monitor build logs for errors and performance
2. **Test Results**: Track test pass/fail rates
3. **Build Times**: Monitor build duration for optimization opportunities
4. **Artifact Sizes**: Track artifact sizes to manage storage costs

## Troubleshooting

### Common Issues
1. **CodeArtifact Authentication**: Verify token generation and permissions
2. **EKS Access**: Check cluster access and kubeconfig configuration
3. **Build Failures**: Review build logs for specific error messages
4. **Test Failures**: Check test output and dependencies

### Debug Steps
1. **Check Permissions**: Verify CodeBuild service role permissions
2. **Review Logs**: Examine build logs for detailed error information
3. **Test Locally**: Reproduce issues in local environment
4. **Check Dependencies**: Verify all required services are accessible

## Integration Examples

### CI/CD Pipeline
```yaml
# Example CodePipeline configuration
- Name: Build
  Actions:
    - Name: Build
      ActionTypeId:
        Category: Build
        Owner: AWS
        Provider: CodeBuild
        Version: '1'
      Configuration:
        ProjectName: demo-dotnet-build
```

### GitHub Integration
```yaml
# GitHub webhook configuration
- Name: Source
  Actions:
    - Name: Source
      ActionTypeId:
        Category: Source
        Owner: AWS
        Provider: CodeStarSourceConnection
        Version: '1'
      Configuration:
        ConnectionArn: arn:aws:codestar-connections:region:account:connection/xxx
        FullRepositoryId: owner/repository
        BranchName: main
```

## Contributing

When contributing to build configurations:
1. **Test locally** before committing changes
2. **Update documentation** for new features
3. **Follow naming conventions** for consistency
4. **Include error handling** for robust builds
5. **Optimize build times** where possible

## Support

For issues or questions:
1. Review build logs for detailed error information
2. Check AWS service quotas and limits
3. Verify IAM permissions for the CodeBuild service role
4. Test configurations in non-production environments first
5. Review AWS CodeBuild documentation for service-specific guidance

---

**Note**: These build configurations are designed for production use. Ensure proper testing and validation before deploying to production environments.
