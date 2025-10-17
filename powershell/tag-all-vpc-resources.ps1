$PROD_VPC = "vpc-0ae3a1e1450cc2fe8"
$DEV_VPC = "vpc-f76cfe9e"

function Tag-ResourcesByVpc {
    param(
        [string]$VpcId,
        [string]$Environment
    )
    
    Write-Host "Tagging resources in VPC $VpcId as environment=$Environment"
    
    aws ec2 create-tags --resources $VpcId --tags Key=environment,Value=$Environment
    
    $subnets = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VpcId" --query 'Subnets[*].SubnetId' --output text
    if ($subnets) {
        $subnets -split '\s+' | ForEach-Object { 
            aws ec2 create-tags --resources $_ --tags Key=environment,Value=$Environment 
        }
    }
    
    $routeTables = aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VpcId" --query 'RouteTables[*].RouteTableId' --output text
    if ($routeTables) {
        $routeTables -split '\s+' | ForEach-Object { 
            aws ec2 create-tags --resources $_ --tags Key=environment,Value=$Environment 
        }
    }
    
    $igws = aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VpcId" --query 'InternetGateways[*].InternetGatewayId' --output text
    if ($igws) {
        $igws -split '\s+' | ForEach-Object { 
            aws ec2 create-tags --resources $_ --tags Key=environment,Value=$Environment 
        }
    }
    
    $natGateways = aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VpcId" --query 'NatGateways[*].NatGatewayId' --output text
    if ($natGateways) {
        $natGateways -split '\s+' | ForEach-Object { 
            aws ec2 create-tags --resources $_ --tags Key=environment,Value=$Environment 
        }
    }
    
    $securityGroups = aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VpcId" --query 'SecurityGroups[*].GroupId' --output text
    if ($securityGroups) {
        $securityGroups -split '\s+' | ForEach-Object { 
            aws ec2 create-tags --resources $_ --tags Key=environment,Value=$Environment 
        }
    }
    
    $nacls = aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VpcId" --query 'NetworkAcls[*].NetworkAclId' --output text
    if ($nacls) {
        $nacls -split '\s+' | ForEach-Object { 
            aws ec2 create-tags --resources $_ --tags Key=environment,Value=$Environment 
        }
    }
    
    $vpcEndpoints = aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VpcId" --query 'VpcEndpoints[*].VpcEndpointId' --output text
    if ($vpcEndpoints) {
        $vpcEndpoints -split '\s+' | ForEach-Object { 
            aws ec2 create-tags --resources $_ --tags Key=environment,Value=$Environment 
        }
    }
}

#Tag-ResourcesByVpc -VpcId $DEV_VPC -Environment "dev"
Tag-ResourcesByVpc -VpcId $PROD_VPC -Environment "prod"
