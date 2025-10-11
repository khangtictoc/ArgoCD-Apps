#! /bin/bash

echo "Create list of namespaces used only for deploying Apps"
kubectl create namespace nginx-ingress 
kubectl create namespace jenkins 
kubectl create namespace cert-manager 
kubectl create namespace mongodb
kubectl create namespace postgresql
kubectl create namespace grafana-stacks
kubectl create namespace hcp-vault
