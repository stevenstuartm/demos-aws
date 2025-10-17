$PROD_VPC = "vpc-0ae3a1e1450cc2fe8"
$DEV_VPC = "vpc-f76cfe9e"

function Tag-Resources {
    param(
        [string[]]$ResourceIds,
        [string]$Environment,
        [string]$Domain,
        [string]$Layer
    )
    
    foreach ($resourceId in $ResourceIds) {
        if ($resourceId -and $resourceId.Trim()) {
            Write-Host "  Resource: $resourceId"
            aws ec2 create-tags --resources $resourceId --tags Key=environment,Value=$Environment Key=domain,Value=$Domain Key=layer,Value=$Layer
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    Success" -ForegroundColor Green
            } else {
                Write-Host "    Failed" -ForegroundColor Red
            }
        }
    }
}

function Tag-ResourcesByVpc {
    param(
        [string]$VpcId,
        [string]$Environment,
        [string]$Domain,
        [string]$Layer
    )
    
    Write-Host "`nTagging resources in VPC $VpcId with environment=$Environment, domain=$Domain, layer=$Layer`n" -ForegroundColor Cyan
    
    Write-Host "VPC:"
    Tag-Resources -ResourceIds @($VpcId) -Environment $Environment -Domain $Domain -Layer $Layer
    
    $subnets = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VpcId" --query 'Subnets[*].SubnetId' --output text
    if ($subnets) {
        Write-Host "`nSubnets:"
        Tag-Resources -ResourceIds ($subnets -split '\s+') -Environment $Environment -Domain $Domain -Layer $Layer
    }
    
    $routeTables = aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VpcId" --query 'RouteTables[*].RouteTableId' --output text
    if ($routeTables) {
        Write-Host "`nRoute Tables:"
        Tag-Resources -ResourceIds ($routeTables -split '\s+') -Environment $Environment -Domain $Domain -Layer $Layer
    }
    
    $igws = aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VpcId" --query 'InternetGateways[*].InternetGatewayId' --output text
    if ($igws) {
        Write-Host "`nInternet Gateways:"
        Tag-Resources -ResourceIds ($igws -split '\s+') -Environment $Environment -Domain $Domain -Layer $Layer
    }
    
    $natGateways = aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VpcId" --query 'NatGateways[*].NatGatewayId' --output text
    if ($natGateways) {
        Write-Host "`nNAT Gateways:"
        Tag-Resources -ResourceIds ($natGateways -split '\s+') -Environment $Environment -Domain $Domain -Layer $Layer
    }
    
    $securityGroups = aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VpcId" --query 'SecurityGroups[*].GroupId' --output text
    if ($securityGroups) {
        Write-Host "`nSecurity Groups:"
        Tag-Resources -ResourceIds ($securityGroups -split '\s+') -Environment $Environment -Domain $Domain -Layer $Layer
    }
    
    $nacls = aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VpcId" --query 'NetworkAcls[*].NetworkAclId' --output text
    if ($nacls) {
        Write-Host "`nNetwork ACLs:"
        Tag-Resources -ResourceIds ($nacls -split '\s+') -Environment $Environment -Domain $Domain -Layer $Layer
    }
    
    $vpcEndpoints = aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VpcId" --query 'VpcEndpoints[*].VpcEndpointId' --output text
    if ($vpcEndpoints) {
        Write-Host "`nVPC Endpoints:"
        Tag-Resources -ResourceIds ($vpcEndpoints -split '\s+') -Environment $Environment -Domain $Domain -Layer $Layer
    }
    
    Write-Host "`nCompleted tagging for VPC $VpcId" -ForegroundColor Cyan
}

Tag-ResourcesByVpc -VpcId $PROD_VPC -Environment "prod" -Domain "platform" -Layer "network"
Tag-ResourcesByVpc -VpcId $DEV_VPC -Environment "dev" -Domain "platform" -Layer "network"

Write-Host "All VPC resources tagged with: environment, domain, layer"