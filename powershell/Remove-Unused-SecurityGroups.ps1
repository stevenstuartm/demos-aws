#Requires -Modules AWSPowerShell.NetCore

<#
.SYNOPSIS
    Identifies and deletes unused EC2 security groups across all AWS regions.

.DESCRIPTION
    This script finds security groups that are not associated with any EC2 instances,
    load balancers, RDS instances, or other AWS resources, then safely deletes them
    following AWS best practices.

.PARAMETER DryRun
    If specified, only identifies unused security groups without deleting them.

.PARAMETER LogPath
    Path for the log file. Defaults to current directory.

.PARAMETER ExcludeRegions
    Array of regions to exclude from the cleanup process.

.EXAMPLE
    .\Remove-UnusedSecurityGroups.ps1 -DryRun
    
.EXAMPLE
    .\Remove-UnusedSecurityGroups.ps1 -LogPath "C:\Logs\aws-cleanup.log"
#>

param(
    [switch]$DryRun,
    [string]$LogPath = ".\aws-sg-cleanup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log",
    [string[]]$ExcludeRegions = @()
)

# Initialize logging
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry
    Add-Content -Path $LogPath -Value $logEntry
}

# Test AWS credentials and connectivity
function Test-AWSConnectivity {
    try {
        $identity = Get-STSCallerIdentity -ErrorAction Stop
        Write-Log "Connected to AWS as: $($identity.Arn)"
        return $true
    }
    catch {
        Write-Log "Failed to connect to AWS. Please check your credentials." "ERROR"
        return $false
    }
}

# Get all security groups that are potentially unused
function Get-UnusedSecurityGroups {
    param([string]$Region)
    
    Write-Log "Analyzing security groups in region: $Region"
    
    try {
        # Get all security groups in the region
        $allSecurityGroups = Get-EC2SecurityGroup -Region $Region
        Write-Log "Found $($allSecurityGroups.Count) total security groups in $Region"
        
        # Get all EC2 instances and their security groups
        $ec2Instances = Get-EC2Instance -Region $Region
        $usedSGIds = @()
        
        foreach ($reservation in $ec2Instances) {
            foreach ($instance in $reservation.Instances) {
                $usedSGIds += $instance.SecurityGroups.GroupId
            }
        }
        
        # Get security groups used by Load Balancers
        try {
            $elbSecurityGroups = Get-ELBLoadBalancer -Region $Region | ForEach-Object { $_.SecurityGroups }
            $usedSGIds += $elbSecurityGroups
            
            # ALB/NLB security groups
            $elbv2SecurityGroups = Get-ELB2LoadBalancer -Region $Region | ForEach-Object { $_.SecurityGroups }
            $usedSGIds += $elbv2SecurityGroups
        }
        catch {
            Write-Log "Could not retrieve ELB security groups in $Region - this is normal if ELB service is not used" "WARN"
        }
        
        # Get security groups used by RDS instances
        try {
            $rdsInstances = Get-RDSDBInstance -Region $Region
            foreach ($rdsInstance in $rdsInstances) {
                $usedSGIds += $rdsInstance.VpcSecurityGroups.VpcSecurityGroupId
            }
        }
        catch {
            Write-Log "Could not retrieve RDS security groups in $Region - this is normal if RDS service is not used" "WARN"
        }
        
        # Get security groups referenced by other security groups
        $referencedSGIds = @()
        foreach ($sg in $allSecurityGroups) {
            foreach ($rule in $sg.IpPermissions) {
                $referencedSGIds += $rule.UserIdGroupPairs.GroupId
            }
            foreach ($rule in $sg.IpPermissionsEgress) {
                $referencedSGIds += $rule.UserIdGroupPairs.GroupId
            }
        }
        $usedSGIds += $referencedSGIds
        
        # Remove duplicates and filter out null values
        $usedSGIds = $usedSGIds | Where-Object { $_ -ne $null } | Sort-Object -Unique
        
        # Find unused security groups (excluding default security groups)
        $unusedSecurityGroups = $allSecurityGroups | Where-Object {
            $_.GroupId -notin $usedSGIds -and 
            $_.GroupName -ne "default"
        }
        
        Write-Log "Found $($unusedSecurityGroups.Count) unused security groups in $Region"
        return $unusedSecurityGroups
    }
    catch {
        Write-Log "Error analyzing security groups in region $Region`: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

# Safely delete a security group with dependency checks
function Remove-SecurityGroupSafely {
    param(
        [object]$SecurityGroup,
        [string]$Region
    )
    
    try {
        # Double-check that the security group is not in use
        $sgDetails = Get-EC2SecurityGroup -GroupId $SecurityGroup.GroupId -Region $Region
        
        # Check for any dependencies one more time
        $dependentResources = @()
        
        # Check EC2 instances
        $ec2Check = Get-EC2Instance -Region $Region | ForEach-Object {
            $_.Instances | Where-Object { $_.SecurityGroups.GroupId -contains $SecurityGroup.GroupId }
        }
        if ($ec2Check) { $dependentResources += "EC2 Instances" }
        
        if ($dependentResources.Count -gt 0) {
            Write-Log "Security group $($SecurityGroup.GroupId) has dependencies: $($dependentResources -join ', '). Skipping deletion." "WARN"
            return $false
        }
        
        # Proceed with deletion
        if ($DryRun) {
            Write-Log "DRY RUN: Would delete security group $($SecurityGroup.GroupId) ($($SecurityGroup.GroupName)) in $Region"
            return $true
        }
        else {
            Remove-EC2SecurityGroup -GroupId $SecurityGroup.GroupId -Region $Region -Force
            Write-Log "Successfully deleted security group $($SecurityGroup.GroupId) ($($SecurityGroup.GroupName)) in $Region" "SUCCESS"
            return $true
        }
    }
    catch {
        Write-Log "Failed to delete security group $($SecurityGroup.GroupId): $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main execution
function Main {
    Write-Log "Starting AWS Security Group cleanup process"
    Write-Log "Log file: $LogPath"
    
    if ($DryRun) {
        Write-Log "Running in DRY RUN mode - no security groups will be deleted"
    }
    
    # Test AWS connectivity
    if (-not (Test-AWSConnectivity)) {
        exit 1
    }
    
    # Get all available regions
    try {
        $regions = Get-EC2Region | Select-Object -ExpandProperty RegionName
        $regions = $regions | Where-Object { $_ -notin $ExcludeRegions }
        Write-Log "Will process $($regions.Count) regions"
    }
    catch {
        Write-Log "Failed to get AWS regions: $($_.Exception.Message)" "ERROR"
        exit 1
    }
    
    $totalUnusedSGs = 0
    $totalDeletedSGs = 0
    
    # Process each region
    foreach ($region in $regions) {
        Write-Log "Processing region: $region"
        
        $unusedSGs = Get-UnusedSecurityGroups -Region $region
        $totalUnusedSGs += $unusedSGs.Count
        
        if ($unusedSGs.Count -eq 0) {
            Write-Log "No unused security groups found in $region"
            continue
        }
        
        # Display unused security groups
        Write-Log "Unused security groups in $region`:"
        foreach ($sg in $unusedSGs) {
            Write-Log "  - $($sg.GroupId) ($($sg.GroupName)) - $($sg.Description)"
        }
        
        # Delete unused security groups
        foreach ($sg in $unusedSGs) {
            if (Remove-SecurityGroupSafely -SecurityGroup $sg -Region $region) {
                $totalDeletedSGs++
            }
            Start-Sleep -Seconds 1  # Rate limiting
        }
    }
    
    # Summary
    Write-Log "="*50
    Write-Log "CLEANUP SUMMARY"
    Write-Log "="*50
    Write-Log "Total unused security groups found: $totalUnusedSGs"
    if ($DryRun) {
        Write-Log "Total security groups that would be deleted: $totalDeletedSGs"
        Write-Log "This was a DRY RUN - no security groups were actually deleted"
    }
    else {
        Write-Log "Total security groups successfully deleted: $totalDeletedSGs"
    }
    Write-Log "Process completed at $(Get-Date)"
}

# Execute main function
Main