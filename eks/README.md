# Demos.AWS.EKS

## Summary:
* This is a rough guide to create a fully functional K8s cluster in AWS EKS. This guide is based on a previous working example and so it is quite specific to the use case at the time.
* Files include placeholders for sensitive values identified by: [some text]. The brackets and values need to be replaced with your values. Other values, such as the cluster name, should also be replaced but they are still included for the sake of comprehension.

### Includes:
* Node groups: public ingress, services, and workers
* Auto scaler
* Metrics server
* Load balancer controller
* IAM roles and security groups
* FluentD

### Does not include:
* Terraform for creating load balancer
* Terraform for creating vpc and subnets

## Install Dependencies

### Install EksCtl on local machine

https://docs.aws.amazon.com/eks/latest/userguide/eksctl.htm

https://eksctl.io/installation/

### Install Helm
https://helm.sh/docs/intro/install/

## Create Cluster

* It is important to consider which AWS user will be used to create the cluster. If you use your own user then THE cluster admin will be you and that could cause a critical problem later. It is better to use an IAM user which is dedicated to managing EKS. So an "eks-admin" console-only user could be created and used here. After creating the cluster resources any user that has been added as an admin in K82 RBAC could be used to manange the cluster. The point is to have a fallback and to not lose access to your cluster.

```
eksctl create cluster -f cluster.yaml --without-nodegroup
```

At this point the local kube config (~/.kube/config) will have the new remote EKS cluster set as the current context. All local kubectl commands will now be run against that EKS cluster.

## Create Cluster Namespaces

```
kubectl create -f namespaces.yaml
```

## Create OpenId IAM Provider

```
eksctl utils associate-iam-oidc-provider --cluster=demo --approve
```

## Create Node Groups

### Public-Subnet Services

```
eksctl create nodegroup -f node-groups/public-ingress.yaml
```

Tag the resulting Auto Scaling Group
* Key: k8s.io/cluster-autoscaler/node-template/label/tier Value: public-ingress

### Private-Subnet Services

```
eksctl create nodegroup -f node-groups/public-services.yaml
```

Tag the resulting Auto Scaling Group
* Key: k8s.io/cluster-autoscaler/node-template/label/tier Value: public-services

### Private Workers

```
eksctl create nodegroup -f node-groups/workers-spot-t2md.yaml
```

Tag the resulting Auto Scaling Group
* Key: k8s.io/cluster-autoscaler/node-template/label/tier Value: workers
* Key: k8s.io/cluster-autoscaler/node-template/label/workerClass Value: spot-t2mdn

### Tag Subnets

I am not sure if ASG and subnet tags are required with later versions of EKS. They used to be so I have made it habit to include them just in case.

* Key: kubernetes.io/cluster/demo Value: shared
* Key: kubernetes.io/role/elb Value: 1
 
## Create ALB Ingress Controller

* The controller does not actually get created until an ingress that refers to the controller is created. But this still needs to occur first.

```
aws iam create-policy \
    --policy-name demo-eks-alb-controller-policy \
    --policy-document file://ingress/eks-alb-controller-policy.json
```


```
eksctl create iamserviceaccount \
  --cluster=demo \
  --namespace=kube-system \
  --name=demo-eks-alb-controller \
  --attach-policy-arn=arn:aws:iam::[account]:policy/demo-eks-alb-controller-policy \
  --override-existing-serviceaccounts \
  --approve
```


```
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

```
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=demo \
  --set serviceAccount.create=false \
  --set serviceAccount.name=demo-eks-alb-controller
```
## Create Ingress 
### Create Ingress Classes

```
kubectl apply -f ingress/ingress-classes.yaml
```

### Create Ingress

```
kubectl apply -f ingress/services-ingress.yaml
```

### Create Route53 DNS Records

* For the domains defined in the ingress, add Alias records pointing to the correct ingress ALB.
* api.demos.io needs to point to the demo-services ALB.
* This could be done automatically using the external DNS EKS feature. That feature has not been enabled and that is intentional.

## Enable Metrics Server

```
kubectl apply -f metrics-server.yaml
```

## Enable Monitoring

* Add CloudWatchAgentServerPolicy Policy to Instance Role
* This ought to be done already if the  SDK was used. The SDK should have added the correct roles when it first created the node groups.

### Deploy Fluentd QuickStart

* “There are two configurations for Fluent Bit: an optimized version and a version that provides an experience more similar to FluentD. The Quick Start configuration uses the optimized version.”

```
curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml | sed "s/{{cluster_name}}/demo/;s/{{region_name}}/us-east-2/" | kubectl apply -f -
```

## Enable Cluster Autoscaling

```
aws iam create-policy \
    --policy-name demo-eks-cluster-autoscaler-policy \
    --policy-document file://eks-cluster-autoscaler-policy.json
```

```
eksctl create iamserviceaccount \
  --cluster=demo \
  --namespace=kube-system \
  --name=cluster-autoscaler \
  --attach-policy-arn=arn:aws:iam::169513989294:policy/demo-eks-cluster-autoscaler-policy \
  --override-existing-serviceaccounts \
  --approve
```

```
kubectl apply -f autoscaler.yaml
```

## Update Node Groups Instance Roles

For several reasons we are relying on the auto-generated roles and policies created though EKS as guided by the NG yaml files. However, we need to update those roles with the permissions that our services need. Instances in the same node group share the same IAM role.

For now, each NG role should have the “node-groups/demo-eks-services-node-policy.json” policy. It is that policy that we ought to be updating instead of adding additional policies to the NG role. If the policy gets too large then it can always be simplified.

## RDS Access

If you get an RDS timeout in your service logs then this may be the issue. RDS Instances have a security group whose inbound rules may need you to allow access from the Cluster’s NodeGroups' security groups. So find the security group for the rds instance and the node group and then update the inbound rules of the RDS sg using the ng sg. If you are using a new node group and/or using an RDS instance that the ng has not before called then this is something that may need to be done.
