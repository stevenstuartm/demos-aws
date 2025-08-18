#Requires -Modules AWSPowerShell.NetCore

<#
.SYNOPSIS
    Identifies and deletes unused IAM customer-managed roles in AWS account
.DESCRIPTION
    This script follows AWS security best practices to:
    1. Find all customer-managed IAM roles
    2. Check if roles are currently in use (attached to instances, used by services, etc.)
    3. Verify roles haven't been used recently (configurable period)
    4. Safely delete unused roles with proper cleanup
.PARAMETER DryRun
    If specified, only shows what would be deleted without making changes
.PARAMETER DaysUnused
    Number of days to consider a role unused (default: 90)
.PARAMETER ExcludeRoles
    Array of role names to exclude from deletion
.EXAMPLE
    .\Remove-UnusedIAMRoles.ps1 -DryRun
    .\Remove-UnusedIAMRoles.ps1 -DaysUnused 60 -ExcludeRoles @("MyImportantRole")
#>

[CmdletBinding()]
param(
    [switch]$DryRun = $false,
    [int]$DaysUnused = 90,
    [string[]]$ExcludeRoles = @(),
    [string]$Region = "us-east-1"
)

# Initialize AWS PowerShell session
try {
    Set-DefaultAWSRegion -Region $Region
    $accountId = (Get-STSCallerIdentity).Account
    Write-Host "Connected to AWS Account: $accountId" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to AWS. Ensure AWS credentials are configured."
    exit 1
}

function Test-RoleInUse {
    param([string]$RoleName, [string]$RoleArn)
    
    $inUse = $false
    $usageReasons = @()
    
    try {
        # Check EC2 instances using this role
        try {
            $instances = Get-EC2Instance | Where-Object { 
                $_.Instances.IamInstanceProfile.Arn -like "*$RoleName*" 
            }
            if ($instances) {
                $inUse = $true
                $usageReasons += "Attached to EC2 instances"
            }
        }
        catch {
            Write-Verbose "EC2 check skipped: $($_.Exception.Message)"
        }
        
        # Check ECS services and tasks
        try {
            $clusters = Get-ECSClusterList
            foreach ($cluster in $clusters) {
                $services = Get-ECSServiceList -Cluster $cluster
                foreach ($service in $services) {
                    $serviceDetails = Get-ECSService -Cluster $cluster -Service $service
                    if ($serviceDetails.TaskDefinition) {
                        $taskDef = Get-ECSTaskDefinition -TaskDefinition $serviceDetails.TaskDefinition
                        if ($taskDef.TaskRoleArn -eq $RoleArn -or $taskDef.ExecutionRoleArn -eq $RoleArn) {
                            $inUse = $true
                            $usageReasons += "Used by ECS service: $service"
                        }
                    }
                }
            }
        }
        catch {
            Write-Verbose "ECS check skipped: $($_.Exception.Message)"
        }
        
        # Check Lambda functions
        try {
            $functions = Get-LMFunctionList
            foreach ($func in $functions) {
                $funcConfig = Get-LMFunction -FunctionName $func.FunctionName
                if ($funcConfig.Role -eq $RoleArn) {
                    $inUse = $true
                    $usageReasons += "Used by Lambda function: $($func.FunctionName)"
                }
            }
        }
        catch {
            Write-Verbose "Lambda check skipped: $($_.Exception.Message)"
        }
        
        # Check CodeBuild projects
        try {
            $projects = Get-CBDProjectList
            foreach ($project in $projects) {
                $projectDetails = Get-CBDProject -Name $project
                if ($projectDetails.ServiceRole -eq $RoleArn) {
                    $inUse = $true
                    $usageReasons += "Used by CodeBuild project: $project"
                }
            }
        }
        catch {
            Write-Verbose "CodeBuild check skipped: $($_.Exception.Message)"
        }
        
        # Check Auto Scaling Groups
        try {
            $asGroups = Get-ASAutoScalingGroup
            foreach ($asg in $asGroups) {
                if ($asg.LaunchConfigurationName) {
                    $launchConfig = Get-ASLaunchConfiguration -LaunchConfigurationName $asg.LaunchConfigurationName
                    if ($launchConfig.IamInstanceProfile -like "*$RoleName*") {
                        $inUse = $true
                        $usageReasons += "Used by Auto Scaling Group: $($asg.AutoScalingGroupName)"
                    }
                }
            }
        }
        catch {
            Write-Verbose "Auto Scaling check skipped: $($_.Exception.Message)"
        }
        
    }
    catch {
        Write-Warning "Error checking role usage for $RoleName`: $($_.Exception.Message)"
    }
    
    return @{
        InUse = $inUse
        Reasons = $usageReasons
    }
}

function Get-RoleLastActivity {
    param([string]$RoleName)
    
    try {
        # Get role's last activity from CloudTrail-like services
        $role = Get-IAMRole -RoleName $RoleName
        $lastUsed = $null
        
        # Check for RoleLastUsed information (if available)
        if ($role.RoleLastUsed) {
            $lastUsed = $role.RoleLastUsed.LastUsedDate
        }
        
        return $lastUsed
    }
    catch {
        Write-Warning "Could not determine last activity for role $RoleName"
        return $null
    }
}

function Remove-IAMRoleSafely {
    param([string]$RoleName)
    
    try {
        Write-Host "Cleaning up role: $RoleName" -ForegroundColor Yellow
        
        # 1. Detach all managed policies
        $attachedPolicies = Get-IAMAttachedRolePolicyList -RoleName $RoleName
        foreach ($policy in $attachedPolicies) {
            Write-Host "  Detaching managed policy: $($policy.PolicyName)"
            if (-not $DryRun) {
                Unregister-IAMRolePolicy -RoleName $RoleName -PolicyArn $policy.PolicyArn
            }
        }
        
        # 2. Delete all inline policies
        $inlinePolicies = Get-IAMRolePolicyList -RoleName $RoleName
        foreach ($policyName in $inlinePolicies) {
            Write-Host "  Deleting inline policy: $policyName"
            if (-not $DryRun) {
                Remove-IAMRolePolicy -RoleName $RoleName -PolicyName $policyName -Force
            }
        }
        
        # 3. Remove role from instance profiles
        $instanceProfiles = Get-IAMInstanceProfileList | Where-Object { 
            $_.Roles | Where-Object { $_.RoleName -eq $RoleName } 
        }
        foreach ($profile in $instanceProfiles) {
            Write-Host "  Removing from instance profile: $($profile.InstanceProfileName)"
            if (-not $DryRun) {
                Remove-IAMRoleFromInstanceProfile -InstanceProfileName $profile.InstanceProfileName -RoleName $RoleName
            }
        }
        
        # 4. Finally delete the role
        Write-Host "  Deleting role: $RoleName"
        if (-not $DryRun) {
            Remove-IAMRole -RoleName $RoleName -Force
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to delete role $RoleName`: $($_.Exception.Message)"
        return $false
    }
}

# Main execution
Write-Host "Starting IAM Role Cleanup Process..." -ForegroundColor Cyan
Write-Host "Days unused threshold: $DaysUnused" -ForegroundColor Cyan
Write-Host "Dry run mode: $DryRun" -ForegroundColor Cyan

# Get all customer-managed roles (exclude AWS service roles)
Write-Host "`nFetching all customer-managed IAM roles..." -ForegroundColor Yellow
$allRoles = Get-IAMRoleList | Where-Object { 
    -not $_.Path.StartsWith("/aws-service-role/") -and
    -not $_.Path.StartsWith("/service-role/") -and
    $_.RoleName -notin $ExcludeRoles
}

Write-Host "Found $($allRoles.Count) customer-managed roles to analyze" -ForegroundColor Green

$unusedRoles = @()
$cutoffDate = (Get-Date).AddDays(-$DaysUnused)

foreach ($role in $allRoles) {
    Write-Host "`nAnalyzing role: $($role.RoleName)" -ForegroundColor White
    
    # Check if role is currently in use
    $usageCheck = Test-RoleInUse -RoleName $role.RoleName -RoleArn $role.Arn
    
    if ($usageCheck.InUse) {
        Write-Host "  ACTIVE - Role is currently in use:" -ForegroundColor Green
        foreach ($reason in $usageCheck.Reasons) {
            Write-Host "    - $reason" -ForegroundColor Green
        }
        continue
    }
    
    # Check last activity
    $lastActivity = Get-RoleLastActivity -RoleName $role.RoleName
    
    if ($lastActivity -and $lastActivity -gt $cutoffDate) {
        Write-Host "  RECENT - Last used: $lastActivity" -ForegroundColor Yellow
        continue
    }
    
    # Role appears unused
    $unusedRoles += $role
    Write-Host "  UNUSED - Candidate for deletion" -ForegroundColor Red
    if ($lastActivity) {
        Write-Host "    Last activity: $lastActivity" -ForegroundColor Gray
    } else {
        Write-Host "    Last activity: Unknown/Never" -ForegroundColor Gray
    }
}

# Summary and deletion
Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan
Write-Host "Total roles analyzed: $($allRoles.Count)"
Write-Host "Unused roles found: $($unusedRoles.Count)"

if ($unusedRoles.Count -eq 0) {
    Write-Host "No unused roles found. Cleanup complete!" -ForegroundColor Green
    exit 0
}

Write-Host "`nUnused roles to be deleted:" -ForegroundColor Red
foreach ($role in $unusedRoles) {
    Write-Host "  - $($role.RoleName)" -ForegroundColor Red
}

if ($DryRun) {
    Write-Host "`n[DRY RUN] No changes made. Use -DryRun:`$false to execute deletions." -ForegroundColor Magenta
    exit 0
}

# Confirm deletion
Write-Host "`nWARNING: This will permanently delete $($unusedRoles.Count) IAM roles!" -ForegroundColor Red
$confirmation = Read-Host "Type 'DELETE' to confirm"

if ($confirmation -ne "DELETE") {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit 0
}

# Perform deletions
Write-Host "`nProceeding with role deletions..." -ForegroundColor Red
$deleteResults = @{
    Success = 0
    Failed = 0
}

foreach ($role in $unusedRoles) {
    if (Remove-IAMRoleSafely -RoleName $role.RoleName) {
        $deleteResults.Success++
        Write-Host "Successfully deleted: $($role.RoleName)" -ForegroundColor Green
    } else {
        $deleteResults.Failed++
        Write-Host "Failed to delete: $($role.RoleName)" -ForegroundColor Red
    }
}

Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "CLEANUP COMPLETE" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan
Write-Host "Successfully deleted: $($deleteResults.Success) roles" -ForegroundColor Green
Write-Host "Failed to delete: $($deleteResults.Failed) roles" -ForegroundColor Red

if ($deleteResults.Failed -gt 0) {
    Write-Host "Review the errors above and manually investigate failed deletions." -ForegroundColor Yellow
}