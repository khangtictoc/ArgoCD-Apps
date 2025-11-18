#! /bin/bash

## Pre-requisites:
# Install eksctl: https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html
# for ARM systems, set ARCH to: `arm64`, `armv6` or `armv7`
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH

CLUSTER_NAME=$1
REGION=$2
VPC_ID=$3

curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"

# (Optional) Verify checksum
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check

tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz

sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl

## Install AWS Load Balancer Controller

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.3/docs/install/iam_policy.json

if [ -z "$POLICY_ARN" ]; then
    echo "Policy 'AWSLoadBalancerControllerIAMPolicy' does not exist. Creating it..."
    POLICY_ARN=$(aws iam create-policy \
        --policy-name "AWSLoadBalancerControllerIAMPolicy" \
        --policy-document file://iam_policy.json \
        --query 'Policy.Arn' \
        --output text)

    # Check if creation was successful and ARN was captured
    if [ -z "$POLICY_ARN" ]; then
        echo "ERROR: Failed to create policy or retrieve ARN."
        exit 1
    else
        echo "Policy created successfully. ARN: $POLICY_ARN"
    fi
else
    echo "Policy $POLICY_NAME already exists. ARN: $POLICY_ARN"
fi

rm iam_policy.json

eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=$POLICY_ARN \
    --override-existing-serviceaccounts \
    --region $REGION \
    --approve

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --version 1.13.0 \
  --set region=$REGION \
  --set vpcId=$VPC_ID