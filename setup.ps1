# GitOps

# prep cluster
$FX_AKS_RESOURCE_GROUP="k8s-flux-rg"
$FX_LOCATION="australiaeast"
$FX_VM_SKU="Standard_D2as_v5"
$FX_AKS_NAME="k8s-flux-aks"
$FX_NODE_COUNT="2"

# create RG
az group create --location $FX_LOCATION `
    --resource-group $FX_AKS_RESOURCE_GROUP

# create cluster
az aks create --node-count $FX_NODE_COUNT `
    --generate-ssh-keys `
    --node-vm-size $FX_VM_SKU `
    --name $FX_AKS_NAME `
    --resource-group $FX_AKS_RESOURCE_GROUP

# merge creds into kube config
az aks get-credentials --name $FX_AKS_NAME `
    --resource-group $FX_AKS_RESOURCE_GROUP `
    --file $HOME/.kube/config

kubectl config current-context
kubectl config use-context $FX_AKS_NAME
kubectl get nodes

# install Flux CLI (use Admin terminal)
choco install flux

# check pre-requisites
flux check --pre

# bootstrap
$GITHUB_REPO = 'k8s-flux-aks'
$GITHUB_USER = 'ivee-tech'
$env:GITHUB_TOKEN = $null # '***'
$CLUSTER_NAME = 'k8s-flux-aks'

flux bootstrap github `
    --owner=$GITHUB_USER `
    --repository=$GITHUB_REPO `
    --branch=main `
    --path=./clusters/$CLUSTER_NAME `
    --read-write-key `
    --personal

# create source
flux create source git demo `
    --url=https://github.com/$GITHUB_USER/$GITHUB_REPO `
    --branch=main `
    --interval=30s `
    --export > ./clusters/$CLUSTER_NAME/demo-source.yaml


# create kustomization
flux create kustomization demoapp-dev `
    --source=demo `
    --path="./infrastructure/overlays/dev" `
    --prune=true `
    --health-check="Deployment/demoapp-dev.demoapp-dev" `
    --health-check="Deployment/redis-dev.demoapp-dev" `
    --health-check-timeout=2m `
    --export > ./clusters/$CLUSTER_NAME/demoapp-dev.yaml

# create helm source
flux create source helm bitnami `
    --url=https://charts.bitnami.com/bitnami `
    --interval=1m0s `
    --export > ./clusters/$CLUSTER_NAME/helmrepo-bitnami.yaml

# create redis helm release
flux create helmrelease redis `
    --source=HelmRepository/bitnami `
    --chart redis `
    --release-name redis `
    --target-namespace default `
    --interval 5m0s `
    --export > ./clusters/$CLUSTER_NAME/helmrelease-redis.yaml

# create helm chart
$ACR_NAME = 'ktbacr'
flux create source helm demoapp `
    --url https://$ACR_NAME.azurecr.io/helm/v1/repo/ `
    --interval 1m0s `
    --secret-ref acr `
    --export > ./clusters/$CLUSTER_NAME/helmrepo-demoapp.yaml

$env:HELM_EXPERIMENTAL_OCI=1

# save chart to ACR
helm package . $ACR_NAME.azurecr.io/demoapp:1.0.0

# login to ACR
helm registry login $ACR_NAME.azurecr.io

# create secret for pulling images from ACR
kubectl create secret generic acr --from-literal username={yourACRName} --fromliteral `
    "password={yourACRAdminPassword}" -n flux-system

# create helm release
flux create helmrelease demoapp `
    --source=HelmRepository/demoapp `
    --release-name demoapp `
    --target-namespace default `
    --interval 5m0s `
    --export > ./clusters/$CLUSTER_NAME/helmrelease-demoapp.yaml

# monitoring
flux create source git monitoring `
    --interval=30m `
    --url=https://github.com/fluxcd/flux2 `
    --branch=main `
    --export > ./clusters/$CLUSTER_NAME/monitor-source.yaml

flux create kustomization monitoring `
    --interval=1h `
    --prune=true `
    --source=monitoring `
    --path="./manifests/monitoring" `
    --health-check="Deployment/prometheus.flux-system" `
    --health-check="Deployment/grafana.flux-system" `
    --export > ./clusters/$CLUSTER_NAME/monitor-kustomization.yaml

# port-forward grafana
kubectl -n flux-system port-forward svc/grafana 3000:3000

# Teams integration
kubectl -n flux-system create secret generic teams-url --from-iteral https://outlook...
