# PowerShell AWS Cleanup Scripts

This directory contains production-ready PowerShell scripts for cleaning up unused AWS resources. These scripts follow AWS security best practices and include comprehensive safety features.

## Scripts Overview

### `Remove-Unused-IAMPolicies.ps1`
Identifies and removes unused IAM customer-managed policies from your AWS account.

**Key Features:**
- Comprehensive policy attachment checking across all IAM entities
- Dry-run mode for safe testing and review
- Detailed logging and audit trails
- Confirmation prompts for safety
- AWS module compatibility checking
- Automatic cleanup of policy versions before deletion

**Usage Examples:**
```powershell
# Dry run to see what would be deleted
.\Remove-Unused-IAMPolicies.ps1 -DryRun

# Execute with confirmation prompts
.\Remove-Unused-IAMPolicies.ps1 -Confirm

# Custom log file location
.\Remove-Unused-IAMPolicies.ps1 -LogFile "C:\Logs\iam-cleanup.log"
```

**Parameters:**
- `-DryRun`: Only identifies unused policies without deleting them
- `-LogFile`: Path to log file (default: timestamped file in current directory)
- `-Confirm`: Prompts for confirmation before each deletion

### `Remove-Unused-IAMRoles.ps1`
Identifies and deletes unused IAM roles across multiple AWS services with comprehensive usage detection.

**Key Features:**
- Multi-service usage detection (EC2, ECS, Lambda, CodeBuild, Auto Scaling)
- Configurable unused period threshold (default: 90 days)
- Role exclusion list support
- Safe deletion with dependency cleanup
- Cross-region support
- Comprehensive dependency checking before deletion

**Usage Examples:**
```powershell
# Dry run with custom unused period
.\Remove-Unused-IAMRoles.ps1 -DryRun -DaysUnused 60

# Exclude specific roles from deletion
.\Remove-Unused-IAMRoles.ps1 -ExcludeRoles @("MyImportantRole", "ProductionRole")

# Execute with custom region
.\Remove-Unused-IAMRoles.ps1 -Region "us-west-2"
```

**Parameters:**
- `-DryRun`: Only shows what would be deleted
- `-DaysUnused`: Number of days to consider a role unused (default: 90)
- `-ExcludeRoles`: Array of role names to exclude from deletion
- `-Region`: AWS region to process (default: us-east-1)

### `Remove-Unused-SecurityGroups.ps1`
Identifies and deletes unused EC2 security groups across all AWS regions.

**Key Features:**
- Multi-region processing
- Comprehensive dependency checking (EC2, ELB, RDS)
- Default security group protection
- Rate limiting for API calls
- Detailed logging and reporting
- Cross-region security group reference detection

**Usage Examples:**
```powershell
# Dry run across all regions
.\Remove-Unused-SecurityGroups.ps1 -DryRun

# Exclude specific regions
.\Remove-Unused-SecurityGroups.ps1 -ExcludeRegions @("us-east-1", "eu-west-1")

# Custom log path
.\Remove-Unused-SecurityGroups.ps1 -LogPath "C:\Logs\sg-cleanup.log"
```

**Parameters:**
- `-DryRun`: Only identifies unused security groups without deleting them
- `-LogPath`: Path for the log file (default: timestamped file in current directory)
- `-ExcludeRegions`: Array of regions to exclude from the cleanup process

## Prerequisites

### PowerShell Requirements
- PowerShell 5.1 or later
- AWS PowerShell modules (choose one option):

**Option 1: AWS PowerShell Core**
```powershell
Install-Module -Name AWSPowerShell.NetCore -Scope CurrentUser -Force
```

**Option 2: AWS Tools (Recommended)**
```powershell
Install-Module -Name AWS.Tools.Installer -Scope CurrentUser -Force
Install-AWSToolsModule AWS.Tools.Common, AWS.Tools.IdentityManagement, AWS.Tools.SecurityToken -Scope CurrentUser
```

### AWS Configuration
- AWS credentials configured via:
  - `aws configure` command
  - IAM roles (if running on EC2)
  - Environment variables
  - AWS credential profiles

### Required Permissions
The scripts require the following AWS permissions:
- `iam:ListPolicies`, `iam:GetPolicy`, `iam:DeletePolicy`
- `iam:ListRoles`, `iam:GetRole`, `iam:DeleteRole`
- `ec2:DescribeSecurityGroups`, `ec2:DeleteSecurityGroup`
- `ec2:DescribeInstances`, `ec2:DescribeLoadBalancers`
- `rds:DescribeDBInstances`
- `sts:GetCallerIdentity`

## Safety Features

### Built-in Safety Measures
1. **Dry-Run Mode**: All scripts support `-DryRun` parameter to preview changes
2. **Dependency Checking**: Comprehensive checks before deletion
3. **Confirmation Prompts**: User confirmation for destructive operations
4. **Detailed Logging**: Complete audit trail of all operations
5. **Error Handling**: Graceful error handling with detailed error messages
6. **Rate Limiting**: Built-in delays to respect AWS API limits

### Best Practices
1. **Always run with `-DryRun` first** to review what will be deleted
2. **Use exclusion lists** for critical resources
3. **Review logs** before and after execution
4. **Run during maintenance windows** to minimize impact
5. **Test in non-production environments** first
6. **Backup configurations** before major cleanup operations

## Logging and Monitoring

### Log Files
- All scripts generate detailed log files with timestamps
- Logs include operation details, errors, and success confirmations
- Default log locations are in the script execution directory
- Custom log paths can be specified via parameters

### Log Format
```
[2024-01-15 10:30:45] [INFO] Starting IAM unused policy cleanup script
[2024-01-15 10:30:46] [INFO] Found 25 customer managed policies
[2024-01-15 10:30:47] [WARNING] Policy 'unused-policy' is NOT in use
[2024-01-15 10:30:48] [SUCCESS] Successfully deleted policy: unused-policy
```

## Error Handling

### Common Issues and Solutions
1. **Permission Denied**: Verify IAM permissions for the executing user/role
2. **Module Not Found**: Install required AWS PowerShell modules
3. **Rate Limiting**: Scripts include built-in delays, but may need adjustment
4. **Dependency Conflicts**: Review error logs for specific dependency issues

### Troubleshooting
1. Check script logs for detailed error information
2. Verify AWS credentials and permissions
3. Test with `-DryRun` mode first
4. Review AWS service quotas and limits
5. Check for conflicting AWS CLI configurations

## Scheduling and Automation

### Recommended Scheduling
- **Development/Test**: Weekly cleanup runs
- **Production**: Monthly cleanup runs during maintenance windows
- **Critical Resources**: Use exclusion lists to prevent accidental deletion

### Automation Examples
```powershell
# Scheduled task for weekly cleanup
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\Remove-Unused-IAMPolicies.ps1 -DryRun"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
Register-ScheduledTask -TaskName "AWS-IAM-Cleanup" -Action $action -Trigger $trigger
```

## Contributing

When contributing to these scripts:
1. **Test thoroughly** in safe environments
2. **Maintain safety features** (dry-run, confirmations, logging)
3. **Add comprehensive error handling**
4. **Update documentation** for new features
5. **Follow existing naming conventions**

## Support

For issues or questions:
1. Review script logs for detailed error information
2. Check AWS service quotas and limits
3. Verify IAM permissions for the executing user/role
4. Test in non-production environments first
5. Review AWS documentation for service-specific limitations

---

**⚠️ Security Notice**: These scripts perform destructive operations on AWS resources. Always review and test thoroughly before running in production environments.
