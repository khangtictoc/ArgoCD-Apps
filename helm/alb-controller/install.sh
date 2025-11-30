#! /bin/bash

## Pre-requisites:
# Install eksctl: https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html
# for ARM systems, set ARCH to: `arm64`, `armv6` or `armv7`
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH

CLUSTER_NAME=$1
REGION=$2
VPC_ID=$3

if ! command -v eksctl 2>&1 >/dev/null
then
    curl -LO --progress-bar "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    # Verify checksum
    curl -L "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
else
    echo "- [CHECKED ✅] eksctl command exists"
fi

## Install AWS Load Balancer Controller

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.3/docs/install/iam_policy.json

# Determine the policy ARN by looking up or creating the policy. This is idempotent
echo "Looking for existing policy 'AWSLoadBalancerControllerIAMPolicy'..."
POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text 2>/dev/null || true)

if [ -n "$POLICY_ARN" ]; then
    echo "Found existing policy. ARN: $POLICY_ARN"
else
    echo "Policy not found. Creating 'AWSLoadBalancerControllerIAMPolicy'..."
    set +e
    CREATE_OUT=$(aws iam create-policy \
        --policy-name "AWSLoadBalancerControllerIAMPolicy" \
        --policy-document file://iam_policy.json \
        --query 'Policy.Arn' --output text 2>&1)
    CREATE_EXIT=$?
    set -e

    if [ $CREATE_EXIT -eq 0 ] && [ -n "$CREATE_OUT" ]; then
        POLICY_ARN="$CREATE_OUT"
        echo "Policy created successfully. ARN: $POLICY_ARN"
    else
        echo "Create policy output: $CREATE_OUT"
        if echo "$CREATE_OUT" | grep -q "EntityAlreadyExists"; then
            echo "Policy already exists (race). Retrieving ARN..."
            POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text)
            if [ -n "$POLICY_ARN" ]; then
                echo "Retrieved existing policy ARN: $POLICY_ARN"
            else
                echo "ERROR: Policy exists but ARN could not be retrieved."
                exit 1
            fi
        else
            echo "ERROR: Failed to create policy or retrieve ARN."
            exit 1
        fi
    fi
fi

rm iam_policy.json

eksctl utils associate-iam-oidc-provider --region=$REGION --cluster=$CLUSTER_NAME --approve

# Get access to the cluster
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

# Check if ServiceAccount exists in Kubernetes
if ! kubectl get sa aws-load-balancer-controller -n kube-system >/dev/null 2>&1; then
    echo "[INFO] ServiceAccount kube-system/aws-load-balancer-controller does not exist. Creating fresh..."

    echo "[INFO] Deleting existing ServiceAccount and CloudFormation stack to ensure clean state..."
    eksctl delete iamserviceaccount \
      --cluster=$CLUSTER_NAME \
      --namespace=kube-system \
      --name=aws-load-balancer-controller \
      --region=$REGION \
      --wait

    echo "[INFO] Creating ServiceAccount kube-system/aws-load-balancer-controller..."
    eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=$POLICY_ARN \
    --region=$REGION \
    --approve
fi

# Helm install
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