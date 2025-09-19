#! /bin/bash

echo "Create list of namespaces used only for deploying Apps"
kubectl create namespace nginx-ingress --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -
