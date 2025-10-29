# param(
#     [string]$Region = "us-east-1"
# )

$PROD_VPC = "vpc-5d8b2b3b"
#$DEV_VPC = "vpc-f76cfe9e"

function Tag-Resources {
    param(
        [string[]]$ResourceIds,
        [string]$Environment,
        [string]$Domain,
        [string]$Layer,
        [string]$Region
    )
    
    foreach ($resourceId in $ResourceIds) {
        if ($resourceId -and $resourceId.Trim()) {
            Write-Host "  Resource: $resourceId"
            aws ec2 create-tags --region $Region --resources $resourceId --tags Key=environment,Value=$Environment Key=domain,Value=$Domain Key=layer,Value=$Layer
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
        [string]$Layer,
        [string]$Region
    )
    
    Write-Host "`nTagging resources in VPC $VpcId with environment=$Environment, domain=$Domain, layer=$Layer`n" -ForegroundColor Cyan

    Write-Host "VPC:"
    Tag-Resources -ResourceIds @($VpcId) -environment $Environment -domain $Domain -layer $Layer -Region $Region

    $subnets = aws ec2 describe-subnets --region $Region --filters "Name=vpc-id,Values=$VpcId" --query 'Subnets[*].SubnetId' --output text
    if ($subnets) {
        Write-Host "`nSubnets:"
        Tag-Resources -ResourceIds ($subnets -split '\s+') -environment $Environment -domain $Domain -layer $Layer -Region $Region
    }

    $routeTables = aws ec2 describe-route-tables --region $Region --filters "Name=vpc-id,Values=$VpcId" --query 'RouteTables[*].RouteTableId' --output text
    if ($routeTables) {
        Write-Host "`nRoute Tables:"
        Tag-Resources -ResourceIds ($routeTables -split '\s+') -environment $Environment -domain $Domain -layer $Layer -Region $Region
    }

    $igws = aws ec2 describe-internet-gateways --region $Region --filters "Name=attachment.vpc-id,Values=$VpcId" --query 'InternetGateways[*].InternetGatewayId' --output text
    if ($igws) {
        Write-Host "`nInternet Gateways:"
        Tag-Resources -ResourceIds ($igws -split '\s+') -environment $Environment -domain $Domain -layer $Layer -Region $Region
    }

    $natGateways = aws ec2 describe-nat-gateways --region $Region --filter "Name=vpc-id,Values=$VpcId" --query 'NatGateways[*].NatGatewayId' --output text
    if ($natGateways) {
        Write-Host "`nNAT Gateways:"
        Tag-Resources -ResourceIds ($natGateways -split '\s+') -environment $Environment -domain $Domain -layer $Layer -Region $Region
    }

    $securityGroups = aws ec2 describe-security-groups --region $Region --filters "Name=vpc-id,Values=$VpcId" --query 'SecurityGroups[*].GroupId' --output text
    if ($securityGroups) {
        Write-Host "`nSecurity Groups:"
        Tag-Resources -ResourceIds ($securityGroups -split '\s+') -environment $Environment -domain $Domain -layer $Layer -Region $Region
    }

    $nacls = aws ec2 describe-network-acls --region $Region --filters "Name=vpc-id,Values=$VpcId" --query 'NetworkAcls[*].NetworkAclId' --output text
    if ($nacls) {
        Write-Host "`nNetwork ACLs:"
        Tag-Resources -ResourceIds ($nacls -split '\s+') -environment $Environment -domain $Domain -layer $Layer -Region $Region
    }

    $vpcEndpoints = aws ec2 describe-vpc-endpoints --region $Region --filters "Name=vpc-id,Values=$VpcId" --query 'VpcEndpoints[*].VpcEndpointId' --output text
    if ($vpcEndpoints) {
        Write-Host "`nVPC Endpoints:"
        Tag-Resources -ResourceIds ($vpcEndpoints -split '\s+') -environment $Environment -domain $Domain -layer $Layer -Region $Region
    }
    
    Write-Host "`nCompleted tagging for VPC $VpcId" -ForegroundColor Cyan
}

Tag-ResourcesByVpc -VpcId $PROD_VPC -environment "prod" -domain "platform" -layer "network" -Region "us-east-1"
#Tag-ResourcesByVpc -VpcId $DEV_VPC -environment "dev" -domain "platform" -layer "network" -Region "us-east-1"

Write-Host "All VPC resources tagged with: environment, domain, layer"