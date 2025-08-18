# Module requirements - install one of these:
# Install-Module -Name AWSPowerShell.NetCore -Scope CurrentUser -Force
# OR
# Install-Module -Name AWS.Tools.Installer -Scope CurrentUser -Force
# Install-AWSToolsModule AWS.Tools.Common, AWS.Tools.IdentityManagement, AWS.Tools.SecurityToken -Scope CurrentUser

<#
.SYNOPSIS
    Identifies and removes unused IAM customer managed policies from AWS account
    
.DESCRIPTION
    This script locates all IAM customer managed policies that are not attached to any
    users, groups, or roles and provides options to delete them safely. Includes
    comprehensive logging and dry-run capabilities.
    
.PARAMETER DryRun
    If specified, only identifies unused policies without deleting them
    
.PARAMETER LogFile
    Path to log file for audit trail (default: .\IAM-Cleanup-Log.txt)
    
.PARAMETER Confirm
    If specified, prompts for confirmation before each deletion
    
.EXAMPLE
    .\Remove-UnusedIAMPolicies.ps1 -DryRun
    Lists all unused policies without deleting them
    
.EXAMPLE
    .\Remove-UnusedIAMPolicies.ps1 -Confirm
    Deletes unused policies with confirmation prompts
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$LogFile = ".\IAM-Cleanup-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt",
    [switch]$Confirm
)

# Check for required AWS modules
function Test-AWSModules {
    $hasAWSPowerShell = Get-Module -ListAvailable -Name "AWSPowerShell.NetCore"
    $hasAWSTools = (Get-Module -ListAvailable -Name "AWS.Tools.Common") -and 
                   (Get-Module -ListAvailable -Name "AWS.Tools.IdentityManagement") -and
                   (Get-Module -ListAvailable -Name "AWS.Tools.SecurityToken")
    
    if (-not $hasAWSPowerShell -and -not $hasAWSTools) {
        Write-Host "ERROR: Required AWS PowerShell modules not found!" -ForegroundColor Red
        Write-Host "Please install one of the following:" -ForegroundColor Yellow
        Write-Host "Option 1: Install-Module -Name AWSPowerShell.NetCore -Scope CurrentUser -Force" -ForegroundColor Green
        Write-Host "Option 2: Install-Module -Name AWS.Tools.Installer -Scope CurrentUser -Force" -ForegroundColor Green
        Write-Host "          Install-AWSToolsModule AWS.Tools.Common, AWS.Tools.IdentityManagement, AWS.Tools.SecurityToken -Scope CurrentUser" -ForegroundColor Green
        return $false
    }
    
    # Import appropriate modules
    if ($hasAWSPowerShell) {
        Import-Module AWSPowerShell.NetCore -Force
        Write-Log "Loaded AWSPowerShell.NetCore module"
    } else {
        Import-Module AWS.Tools.Common, AWS.Tools.IdentityManagement, AWS.Tools.SecurityToken -Force
        Write-Log "Loaded AWS.Tools modules"
    }
    
    return $true
}
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry
    Add-Content -Path $LogFile -Value $logEntry
}

# Verify AWS credentials and region
function Test-AWSConfiguration {
    try {
        $identity = Get-STSCallerIdentity -ErrorAction Stop
        Write-Log "Connected to AWS Account: $($identity.Account) as $($identity.Arn)"
        return $true
    }
    catch {
        Write-Log "AWS credentials not configured or invalid: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Get all customer managed policies
function Get-CustomerManagedPolicies {
    try {
        Write-Log "Retrieving all customer managed policies..."
        $policies = Get-IAMPolicies -Scope Local -MaxItems 1000
        Write-Log "Found $($policies.Count) customer managed policies"
        return $policies
    }
    catch {
        Write-Log "Failed to retrieve IAM policies: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Check if policy is attached to any entity
function Test-PolicyAttachment {
    param([string]$PolicyArn)
    
    try {
        # Check policy entities (users, groups, roles)
        $entities = Get-IAMEntitiesForPolicy -PolicyArn $PolicyArn
        
        $attachmentCount = 0
        $attachmentCount += $entities.PolicyUsers.Count
        $attachmentCount += $entities.PolicyGroups.Count  
        $attachmentCount += $entities.PolicyRoles.Count
        
        return $attachmentCount -gt 0
    }
    catch {
        Write-Log "Failed to check attachments for policy ${PolicyArn}: $($_.Exception.Message)" "WARNING"
        return $true # Assume attached if we can't check
    }
}

# Safely delete IAM policy
function Remove-IAMPolicySafely {
    param([object]$Policy)
    
    try {
        # Delete all non-default versions first
        $versions = Get-IAMPolicyVersions -PolicyArn $Policy.Arn
        $nonDefaultVersions = $versions | Where-Object { -not $_.IsDefaultVersion }
        
        foreach ($version in $nonDefaultVersions) {
            Write-Log "Deleting policy version $($version.VersionId) for $($Policy.PolicyName)"
            Remove-IAMPolicyVersion -PolicyArn $Policy.Arn -VersionId $version.VersionId -Force
        }
        
        # Delete the policy
        Write-Log "Deleting policy: $($Policy.PolicyName)"
        Remove-IAMPolicy -PolicyArn $Policy.Arn -Force
        
        Write-Log "Successfully deleted policy: $($Policy.PolicyName)" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to delete policy $($Policy.PolicyName): $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Initialize logging
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry
    Add-Content -Path $LogFile -Value $logEntry
}

# Main execution
try {
    Write-Host "Starting IAM unused policy cleanup script" -ForegroundColor Cyan
    
    # Check for AWS modules first
    if (-not (Test-AWSModules)) {
        exit 1
    }
    Write-Log "Starting IAM unused policy cleanup script"
    Write-Log "Parameters: DryRun=$DryRun, Confirm=$Confirm, LogFile=$LogFile"
    
    # Verify AWS configuration
    if (-not (Test-AWSConfiguration)) {
        throw "AWS configuration validation failed"
    }
    
    # Get all customer managed policies
    $allPolicies = Get-CustomerManagedPolicies
    
    if ($allPolicies.Count -eq 0) {
        Write-Log "No customer managed policies found in this account"
        exit 0
    }
    
    # Identify unused policies
    Write-Log "Checking policy attachments..."
    $unusedPolicies = @()
    $usedPolicies = @()
    
    foreach ($policy in $allPolicies) {
        Write-Progress -Activity "Checking Policy Attachments" -Status $policy.PolicyName -PercentComplete (($unusedPolicies.Count + $usedPolicies.Count) / $allPolicies.Count * 100)
        
        $isAttached = Test-PolicyAttachment -PolicyArn $policy.Arn
        
        if ($isAttached) {
            $usedPolicies += $policy
            Write-Log "Policy '$($policy.PolicyName)' is in use"
        } else {
            $unusedPolicies += $policy
            Write-Log "Policy '$($policy.PolicyName)' is NOT in use" "WARNING"
        }
    }
    
    Write-Progress -Completed -Activity "Checking Policy Attachments"
    
    # Summary
    Write-Log "=== SUMMARY ==="
    Write-Log "Total customer managed policies: $($allPolicies.Count)"
    Write-Log "Policies in use: $($usedPolicies.Count)"
    Write-Log "Unused policies: $($unusedPolicies.Count)"
    
    if ($unusedPolicies.Count -eq 0) {
        Write-Log "No unused policies found. Nothing to clean up."
        exit 0
    }
    
    # List unused policies
    Write-Log "=== UNUSED POLICIES ==="
    foreach ($policy in $unusedPolicies) {
        Write-Log "- $($policy.PolicyName) (ARN: $($policy.Arn), Created: $($policy.CreateDate))"
    }
    
    # Handle dry run
    if ($DryRun) {
        Write-Log "DRY RUN MODE: No policies will be deleted"
        Write-Log "To actually delete these policies, run the script without -DryRun parameter"
        exit 0
    }
    
    # Confirm deletion
    if ($Confirm) {
        $response = Read-Host "Do you want to delete all $($unusedPolicies.Count) unused policies? (y/N)"
        if ($response -ne 'y' -and $response -ne 'Y') {
            Write-Log "Operation cancelled by user"
            exit 0
        }
    }
    
    # Delete unused policies
    Write-Log "=== DELETION PROCESS ==="
    $deletedCount = 0
    $failedCount = 0
    
    foreach ($policy in $unusedPolicies) {
        if ($Confirm) {
            $response = Read-Host "Delete policy '$($policy.PolicyName)'? (y/N/q to quit)"
            if ($response -eq 'q' -or $response -eq 'Q') {
                Write-Log "Deletion process stopped by user"
                break
            }
            if ($response -ne 'y' -and $response -ne 'Y') {
                Write-Log "Skipping policy: $($policy.PolicyName)"
                continue
            }
        }
        
        $success = Remove-IAMPolicySafely -Policy $policy
        if ($success) {
            $deletedCount++
        } else {
            $failedCount++
        }
    }
    
    # Final summary
    Write-Log "=== FINAL SUMMARY ==="
    Write-Log "Policies successfully deleted: $deletedCount"
    Write-Log "Policies failed to delete: $failedCount"
    Write-Log "Script completed successfully"
    
}
catch {
    Write-Log "Script failed with error: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
finally {
    Write-Log "Log file saved to: $LogFile"
}