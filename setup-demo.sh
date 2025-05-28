#!/bin/bash

# Vault + ArgoCD Integration Demo Setup Script
# This script automates the setup process described in the README

set -e  # Exit on any error

echo "🚀 Starting Vault + ArgoCD Integration Demo Setup"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
print_status "Checking prerequisites..."

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker Desktop and try again."
    exit 1
fi

# Check if Vault license exists
if [ ! -f "vault.hclic" ]; then
    print_error "Vault license file 'vault.hclic' not found. Please ensure it exists in the current directory."
    print_warning "SECURITY NOTE: Never commit vault.hclic to a public repository! It's included in .gitignore for your protection."
    exit 1
fi

print_success "Prerequisites check passed"

# Step 1: Start Vault Enterprise
print_status "Step 1: Initializing Vault Enterprise..."
if ! docker ps | grep -q vault-enterprise; then
    print_status "Starting Vault container..."
    ./vault.sh
    sleep 10  # Allow Vault initialization time
else
    print_success "Vault container already running"
fi

# Verify Vault is accessible
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"

if ! vault status >/dev/null 2>&1; then
    print_error "Vault is not accessible. Please verify the service is running properly."
    exit 1
fi

print_success "Vault Enterprise is running!"

# Step 2: Install required tools
print_status "Step 2: Installing required tools..."

# Check and install tools
tools=("minikube" "kubectl" "helm")
for tool in "${tools[@]}"; do
    if ! command -v $tool &> /dev/null; then
        print_status "Installing $tool..."
        brew install $tool
    else
        print_success "$tool is already installed"
    fi
done

# Step 3: Start Minikube
print_status "Step 3: Initializing Minikube cluster..."
if ! minikube status | grep -q "Running"; then
    print_status "Starting minikube cluster..."
    minikube start --driver=docker --cpus=4 --memory=6144
else
    print_success "Minikube cluster is already running"
fi

# Verify cluster
kubectl cluster-info >/dev/null 2>&1
print_success "Kubernetes cluster is ready!"

# Step 4: Configure Vault
print_status "Step 4: Configuring Vault for Kubernetes authentication..."

# Enable Kubernetes auth method
if ! vault auth list | grep -q kubernetes; then
    vault auth enable kubernetes
    print_success "Kubernetes auth method enabled"
else
    print_success "Kubernetes auth method already enabled"
fi

# Step 5: Create Vault secrets
print_status "Step 5: Creating sample secrets in Vault..."

# Enable KV secrets engine
if ! vault secrets list | grep -q "secret/"; then
    vault secrets enable -path=secret kv-v2
    print_success "KV secrets engine enabled"
else
    print_success "KV secrets engine already enabled"
fi

# Create sample secrets
vault kv put secret/myapp/database \
    username="myuser" \
    password="supersecret123" \
    host="db.example.com" \
    port="5432"

vault kv put secret/myapp/api \
    key="api-key-12345" \
    endpoint="https://api.example.com"

print_success "Sample secrets created in Vault!"

# Step 6: Install ArgoCD with Vault Plugin
print_status "Step 6: Installing ArgoCD with Vault Plugin..."

# Create namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repo
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1
helm repo update >/dev/null 2>&1

# Create Argo CD values file
cat > argocd-values.yaml << 'EOF'
configs:
  cm:
    configManagementPlugins: |
      - name: argocd-vault-plugin
        generate:
          command: ["argocd-vault-plugin"]
          args: ["generate", "./"]

repoServer:
  initContainers:
    - name: download-tools
      image: alpine:3.18
      command: [sh, -c]
      args:
        - >-
          wget -O argocd-vault-plugin https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v1.17.0/argocd-vault-plugin_1.17.0_linux_amd64 &&
          chmod +x argocd-vault-plugin &&
          mv argocd-vault-plugin /custom-tools/
      volumeMounts:
        - mountPath: /custom-tools
          name: custom-tools
  
  extraContainers:
    - name: avp
      image: quay.io/argoproj/argocd:v2.8.4
      command: [/var/run/argocd/argocd-cmp-server]
      env:
        - name: VAULT_ADDR
          value: "http://host.minikube.internal:8200"
        - name: VAULT_TOKEN
          value: "root"
        - name: AVP_TYPE
          value: "vault"
        - name: AVP_AUTH_TYPE
          value: "token"
        - name: PATH
          value: "/custom-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
      volumeMounts:
        - mountPath: /var/run/argocd
          name: var-files
        - mountPath: /home/argocd/cmp-server/plugins
          name: plugins
        - mountPath: /tmp
          name: avp-tmp
        - mountPath: /home/argocd/cmp-server/config/plugin.yaml
          subPath: plugin.yaml
          name: cmp-plugin
        - mountPath: /custom-tools
          name: custom-tools
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
  
  volumes:
    - name: custom-tools
      emptyDir: {}
    - name: cmp-plugin
      configMap:
        name: argocd-vault-plugin-config
    - name: avp-tmp
      emptyDir: {}

server:
  service:
    type: NodePort
    nodePortHttp: 30080
    nodePortHttps: 30443
EOF

# Create plugin configuration
kubectl create configmap argocd-vault-plugin-config -n argocd --from-literal=plugin.yaml='
apiVersion: argoproj.io/v1alpha1
kind: ConfigManagementPlugin
metadata:
  name: argocd-vault-plugin
spec:
  allowConcurrency: true
  discover:
    find:
      command:
        - sh
        - "-c"
        - "find . -name '\''*.yaml'\'' | xargs -I {} grep -l '\''<path\\|avp\\.kubernetes\\.io'\'' {}"
  generate:
    command:
      - argocd-vault-plugin
      - generate
      - ./
  lockRepo: false
' --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
if ! helm list -n argocd | grep -q argocd; then
    print_status "Installing ArgoCD with Vault plugin..."
    helm install argocd argo/argo-cd -n argocd -f argocd-values.yaml
    
    print_status "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
else
    print_success "ArgoCD is already installed"
fi

print_success "ArgoCD with Vault Plugin installed!"

# Step 7: Configure Vault policy and authentication
print_status "Step 7: Configuring Vault policies and authentication..."

# Create policy for ArgoCD
vault policy write argocd-policy - << 'EOF'
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
EOF

# Wait for Argo CD service account to be created
print_status "Waiting for Argo CD service account initialization..."
kubectl wait --for=condition=ready --timeout=60s pod -l app.kubernetes.io/name=argocd-server -n argocd

# Get minikube IP and configure Kubernetes auth
MINIKUBE_IP=$(minikube ip)
print_status "Configuring Kubernetes authentication with cluster IP: $MINIKUBE_IP"

# Get service account token (handling both old and new Kubernetes versions)
SA_TOKEN=""
if kubectl get secret -n argocd | grep -q argocd-server-token; then
    # Old method (K8s < 1.24)
    SA_TOKEN=$(kubectl get secret -n argocd $(kubectl get serviceaccount -n argocd argocd-server -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 -d)
else
    # New method (K8s >= 1.24)
    SA_TOKEN=$(kubectl create token argocd-server -n argocd --duration=24h)
fi

# Configure Kubernetes auth
vault write auth/kubernetes/config \
    token_reviewer_jwt="$SA_TOKEN" \
    kubernetes_host="https://${MINIKUBE_IP}:8443" \
    kubernetes_ca_cert="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)"

# Create role for Argo CD
vault write auth/kubernetes/role/argocd \
    bound_service_account_names=argocd-server \
    bound_service_account_namespaces=argocd \
    policies=argocd-policy \
    ttl=1h

print_success "Vault authentication configuration completed"

# Step 8: Create demo application
print_status "Step 8: Creating demo application manifests..."

mkdir -p demo-app/manifests

# Create deployment with Vault secrets
cat > demo-app/manifests/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault-demo-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vault-demo-app
  template:
    metadata:
      labels:
        app: vault-demo-app
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80
        env:
        - name: DB_USERNAME
          value: <path:secret/data/myapp/database#username>
        - name: DB_PASSWORD
          value: <path:secret/data/myapp/database#password>
        - name: DB_HOST
          value: <path:secret/data/myapp/database#host>
        - name: API_KEY
          value: <path:secret/data/myapp/api#key>
        volumeMounts:
        - name: config
          mountPath: /usr/share/nginx/html
      volumes:
      - name: config
        configMap:
          name: app-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: default
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
        <title>Vault + Argo CD Integration Demo</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
            .container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .secret { background: #e8f5e8; padding: 15px; margin: 10px 0; border-radius: 4px; border-left: 4px solid #4caf50; }
            h1 { color: #333; }
            .note { background: #fff3cd; padding: 10px; border-radius: 4px; border-left: 4px solid #ffc107; margin: 20px 0; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Vault + Argo CD Integration Demo</h1>
            <p>This application demonstrates how Argo CD can fetch secrets from HashiCorp Vault during deployment.</p>
            
            <div class="note">
                <strong>Note:</strong> In production environments, secrets should never be displayed in user interfaces. 
                This demonstration is for educational purposes only.
            </div>
            
            <h2>Secrets Retrieved from Vault:</h2>
            <div class="secret">
                <strong>Database Username:</strong> <path:secret/data/myapp/database#username>
            </div>
            <div class="secret">
                <strong>Database Host:</strong> <path:secret/data/myapp/database#host>
            </div>
            <div class="secret">
                <strong>API Endpoint:</strong> <path:secret/data/myapp/api#endpoint>
            </div>
            
            <h2>Implementation Process:</h2>
            <ol>
                <li>ArgoCD detects changes in the Git repository</li>
                <li>The Vault plugin processes manifests with <code>&lt;path:...&gt;</code> placeholders</li>
                <li>Plugin authenticates to Vault using Kubernetes auth</li>
                <li>Secrets are fetched and injected into the manifests</li>
                <li>Final manifests are applied to Kubernetes</li>
            </ol>
        </div>
    </body>
    </html>
---
apiVersion: v1
kind: Service
metadata:
  name: vault-demo-app
  namespace: default
spec:
  selector:
    app: vault-demo-app
  ports:
  - port: 80
    targetPort: 80
  type: NodePort
EOF

print_success "Demo application manifests created!"

# Get Argo CD admin password
print_status "Retrieving Argo CD admin credentials..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Final instructions
echo ""
echo "Demo setup completed successfully"
echo "================================"
echo ""
print_success "Next steps:"
echo "1. Access ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Then open: https://localhost:8080"
echo "   Username: admin"
echo "   Password: $ARGOCD_PASSWORD"
echo ""
echo "2. Create an Argo CD application pointing to this repository"
echo "3. Configure the application to use the 'argocd-vault-plugin'"
echo "4. Set the source path to 'demo-app/manifests'"
echo ""
print_warning "Important: Commit and push the demo-app/ directory to your Git repository before creating the Argo CD application"
echo ""
print_status "To clean up the environment later, run: ./cleanup-demo.sh" 