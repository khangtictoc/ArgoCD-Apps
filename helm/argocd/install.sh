#! /bin/bash

ARGOCD_CHART_VERSION="8.3.5"
CLUSTER_CONTEXT="testproject-dev"
NAMESPACE="argocd"
APPS_NAMESPACE="argocd-apps"
URL="http://localhost:8080"

function helm-install(){
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update
    helm upgrade --install my-argo-cd argo/argo-cd --version $ARGOCD_CHART_VERSION -f values.yaml --namespace $NAMESPACE --create-namespace
}

function check-service-available(){
    while true; do
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL")

        if [[ "$STATUS" =~ ^[45][0-9][0-9]$ ]]; then
            echo "waiting... (got $STATUS)"
            sleep 1
        else
            echo -e "${GREEN}ArgoCD service are available to be used${NC}"
            break
        fi
    done
}

function create-predefined-namespace(){
    echo "Create dedicated namespace for ArgoCD Apps"
    kubectl create namespace $APPS_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    echo -e "${GREEN}[CHECKED]${NC} Namespace '$APPS_NAMESPACE' created."
}

function argocd-reconfig(){
    echo "Logging into ArgoCD..."
    argocd login localhost:8080 --insecure --username admin --password $ARGOCD_INIT_PASSWORD
    echo "✅ Successfully logged into ArgoCD CLI."

    argocd cluster add $CLUSTER_CONTEXT --yes
    echo -e "${GREEN}[CHECKED]${NC} Added cluster $CLUSTER_CONTEXT to ArgoCD."

    echo "Allow all Source Repositories for AppProject 'default'"
    argocd proj add-source default '*'
    echo -e "${GREEN}[CHECKED]${NC} All source repositories allowed for AppProject 'default'."
}
function post-install--tasks(){
    create-predefined-namespace
    argocd-reconfig
}

function post-install--notification(){
    echo "✅ All pods are in Running state."

    echo "Port-forwarding ArgoCD server ..."
    kubectl port-forward service/my-argo-cd-argocd-server -n argocd 8080:443 > /dev/null 2>&1 &
    sleep 10
    echo -e "${GREEN}[CHECKED]${NC} Now you can access ArgoCD UI at: $URL"
    
    ARGOCD_INIT_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    echo -e "${CYAN}[INFO]${NC} ArgoCD initial 'admin' password: $ARGOCD_INIT_PASSWORD"
}



function main(){
    source <(curl -sS https://raw.githubusercontent.com/khangtictoc/Productive-Workspace-Set-Up/refs/heads/main/linux/utility/library/bash/ansi_color.sh)
    init-ansicolor
    helm-install

    # Wait for all pods in namespace to be in Running state
    echo "Waiting for all pods in $NAMESPACE to be in Running state..."
    while true; do
        NOT_READY=$(kubectl get pods -n $NAMESPACE --no-headers | grep -v "Running" | wc -l)
        if [ "$NOT_READY" -eq 0 ]; then
            post-install--notification
            check-service-available
            post-install--tasks
            break
        else
            echo "Still waiting... ($NOT_READY pods not ready)"
            sleep 1
        fi
    done
}

main "$@" 