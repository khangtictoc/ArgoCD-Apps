ARGOCD_CHART_VERSION="8.3.5"
CLUSTER_CONTEXT="testproject-dev"
NAMESPACE="argocd"

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install my-argo-cd argo/argo-cd --version $ARGOCD_CHART_VERSION -f values.yaml --namespace $NAMESPACE --create-namespace

# Wait for all pods in namespace to be in Running state
echo "Waiting for all pods in $NAMESPACE to be in Running state..."
while true; do
    NOT_READY=$(kubectl get pods -n $NAMESPACE --no-headers | grep -v "Running" | wc -l)
    if [ "$NOT_READY" -eq 0 ]; then
        echo "✅ All pods are in Running state."

        echo "Port-forwarding ArgoCD server ..."
        kubectl port-forward service/my-argo-cd-argocd-server -n argocd 8080:443 > /dev/null 2>&1 &
        echo "[CHECKED ✅] Now you can access ArgoCD UI at: https://localhost:8080"
        
        ARGOCD_INIT_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
        echo "[CHECKED ✅] ArgoCD initial admin password: $ARGOCD_INIT_PASSWORD"
        echo "Logging into ArgoCD..."
        argocd login localhost:8080 --insecure --username admin --password $ARGOCD_INIT_PASSWORD
        echo "[CHECKED ✅] Successfully logged into ArgoCD CLI."

        argocd cluster add $CLUSTER_CONTEXT --yes
        echo "[CHECKED ✅] Successfully added cluster $CLUSTER_CONTEXT to ArgoCD."
    else
        echo "Still waiting... ($NOT_READY pods not ready)"
        sleep 2
    fi
done
