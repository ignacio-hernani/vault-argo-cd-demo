#!/bin/bash

# Vault + ArgoCD Integration Demo Setup Script
# This script verifies the current setup and performs configuration only if needed

set -e  # Exit on any error

echo "🚀 Vault + ArgoCD Integration Demo"
echo "=================================="

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

print_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

# Track what needs to be set up
NEEDS_SETUP=0
MISSING_COMPONENTS=()

# Verification functions
verify_docker() {
    print_check "Checking Docker..."
    if docker info >/dev/null 2>&1; then
        print_success "Docker is running"
        return 0
    else
        print_error "Docker is not running"
        MISSING_COMPONENTS+=("Docker")
        return 1
    fi
}

verify_vault() {
    print_check "Checking Vault..."
    export VAULT_ADDR="http://127.0.0.1:8200"
    export VAULT_TOKEN="root"
    
    if ! vault status >/dev/null 2>&1; then
        print_warning "Vault is not accessible"
        MISSING_COMPONENTS+=("Vault")
        return 1
    fi
    
    print_success "Vault is accessible"
    
    # Check Vault secrets
    print_check "Checking Vault secrets..."
    if ! vault kv get secret/myapp/database >/dev/null 2>&1; then
        print_warning "Sample secrets not found in Vault"
        MISSING_COMPONENTS+=("Vault secrets")
        return 1
    fi
    print_success "Sample secrets exist in Vault"
    
    # Check Vault auth methods
    print_check "Checking Vault auth methods..."
    if ! vault auth list | grep -q kubernetes; then
        print_warning "Kubernetes auth method not enabled"
        MISSING_COMPONENTS+=("Vault Kubernetes auth")
        return 1
    fi
    print_success "Kubernetes auth method enabled"
    
    return 0
}

verify_minikube() {
    print_check "Checking Minikube..."
    if ! minikube status | grep -q "Running"; then
        print_warning "Minikube is not running"
        MISSING_COMPONENTS+=("Minikube")
        return 1
    fi
    print_success "Minikube is running"
    
    # Check cluster connectivity
    print_check "Checking Kubernetes cluster..."
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_warning "Kubernetes cluster is not accessible"
        MISSING_COMPONENTS+=("Kubernetes cluster")
        return 1
    fi
    print_success "Kubernetes cluster is accessible"
    
    return 0
}

verify_argocd() {
    print_check "Checking ArgoCD installation..."
    if ! kubectl get namespace argocd >/dev/null 2>&1; then
        print_warning "ArgoCD namespace not found"
        MISSING_COMPONENTS+=("ArgoCD")
        return 1
    fi
    print_success "ArgoCD namespace exists"
    
    # Check ArgoCD pods
    print_check "Checking ArgoCD pods..."
    if ! kubectl get pods -n argocd | grep -q "Running"; then
        print_warning "ArgoCD pods are not running"
        MISSING_COMPONENTS+=("ArgoCD pods")
        return 1
    fi
    print_success "ArgoCD pods are running"
    
    # Check ArgoCD server readiness
    if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
        READY=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        if [ "$READY" = "$DESIRED" ] && [ "$READY" != "" ] && [ "$READY" != "0" ]; then
            print_success "ArgoCD server is ready"
        else
            print_warning "ArgoCD server is not fully ready ($READY/$DESIRED replicas)"
            MISSING_COMPONENTS+=("ArgoCD server readiness")
            return 1
        fi
    fi
    
    # Check Vault plugin configuration
    print_check "Checking Vault plugin configuration..."
    if ! kubectl get configmap argocd-vault-plugin-config -n argocd >/dev/null 2>&1; then
        print_warning "Vault plugin configuration not found"
        MISSING_COMPONENTS+=("Vault plugin config")
        return 1
    fi
    print_success "Vault plugin configuration exists"
    
    return 0
}

verify_connectivity() {
    print_check "Checking network connectivity from minikube to Vault..."
    if minikube ssh -- curl -s http://host.minikube.internal:8200/v1/sys/health >/dev/null 2>&1; then
        print_success "Minikube can reach Vault"
        return 0
    else
        print_warning "Minikube cannot reach Vault"
        MISSING_COMPONENTS+=("Network connectivity")
        return 1
    fi
}

verify_demo_app() {
    print_check "Checking demo application manifests..."
    if [ -d "demo-app/manifests" ] && [ -f "demo-app/manifests/deployment.yaml" ]; then
        print_success "Demo application manifests exist"
        
        # Check for Vault placeholders
        if grep -q "<path:secret" demo-app/manifests/deployment.yaml; then
            print_success "Vault placeholders found in manifests"
        else
            print_warning "No Vault placeholders found in manifests"
            MISSING_COMPONENTS+=("Vault placeholders in manifests")
            return 1
        fi
        return 0
    else
        print_warning "Demo application manifests not found"
        MISSING_COMPONENTS+=("Demo app manifests")
        return 1
    fi
}

verify_tools() {
    print_check "Checking required tools..."
    local missing_tools=()
    TOOLS=("kubectl" "helm" "minikube" "vault")
    for tool in "${TOOLS[@]}"; do
        if command -v $tool >/dev/null 2>&1; then
            print_success "$tool is installed"
        else
            print_warning "$tool is not installed"
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        MISSING_COMPONENTS+=("Tools: ${missing_tools[*]}")
        return 1
    fi
    return 0
}

verify_git_setup() {
    print_check "Checking Git repository setup..."
    if [ -d ".git" ]; then
        REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
        if [ -n "$REPO_URL" ]; then
            print_success "Git repository configured with remote: $REPO_URL"
            return 0
        else
            print_warning "Git repository exists but no remote origin set"
            MISSING_COMPONENTS+=("Git remote origin")
            return 1
        fi
    else
        print_warning "Git repository not initialized"
        MISSING_COMPONENTS+=("Git repository")
        return 1
    fi
}

# Run comprehensive verification
echo "🔍 Verifying current setup..."
echo ""

# Check prerequisites that must be present
if ! command -v git &> /dev/null; then
    print_error "Git is not installed. Please install git first."
    exit 1
fi

if [ ! -f "vault.hclic" ]; then
    print_error "Vault license file 'vault.hclic' not found. Please ensure it exists in the current directory."
    print_warning "SECURITY NOTE: Never commit vault.hclic to a public repository!"
    exit 1
fi

# Run all verification checks
verify_docker || NEEDS_SETUP=1
verify_tools || NEEDS_SETUP=1
verify_git_setup || NEEDS_SETUP=1
verify_vault || NEEDS_SETUP=1
verify_minikube || NEEDS_SETUP=1
verify_argocd || NEEDS_SETUP=1
verify_connectivity || NEEDS_SETUP=1
verify_demo_app || NEEDS_SETUP=1

echo ""
echo "======================================"

# If everything is already set up, provide success message and exit
if [ $NEEDS_SETUP -eq 0 ]; then
    print_success "✅ All components are already configured and running!"
    echo ""
    print_success "Your demo environment is ready to use:"
    echo ""
    echo "🎯 Next steps:"
    echo "1. Apply the ArgoCD application:"
    echo "   kubectl apply -f vault-demo-app.yaml"
    echo ""
    echo "2. Watch the application sync:"
    echo "   kubectl get applications -n argocd -w"
    echo ""
    echo "3. Access ArgoCD UI:"
    echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "   Then open: https://localhost:8080"
    
    # Get admin password
    if kubectl get secret argocd-initial-admin-secret -n argocd >/dev/null 2>&1; then
        ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "")
        if [ -n "$ARGOCD_PASSWORD" ]; then
            echo "   Username: admin"
            echo "   Password: $ARGOCD_PASSWORD"
        fi
    fi
    
    echo ""
    echo "4. Monitor the deployment:"
    echo "   kubectl get pods -n default -w"
    echo ""
    print_status "To clean up the environment, run: ./03-cleanup.sh"
    exit 0
fi

# If setup is needed, show what's missing and proceed
echo ""
print_warning "Setup required for the following components:"
for component in "${MISSING_COMPONENTS[@]}"; do
    echo "  - $component"
done

echo ""
print_status "🛠️ Proceeding with setup configuration..."
echo ""

# REPO_URL variable for Git setup (will be set during Git setup)
REPO_URL=""

# Step 0: GitHub Repository Setup
if [[ " ${MISSING_COMPONENTS[*]} " =~ " Git repository " ]] || [[ " ${MISSING_COMPONENTS[*]} " =~ " Git remote origin " ]]; then
    print_status "Step 0: Setting up GitHub repository..."
    
    # Check if we're already in a git repository
    if [ -d ".git" ]; then
        print_success "Already in a git repository"
        REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
        if [ -z "$REPO_URL" ]; then
            print_warning "No remote origin set"
            # Get repository URL from user
            echo ""
            print_status "Please provide your GitHub repository URL:"
            echo "Examples:"
            echo "  https://github.com/username/vault-argo-cd-demo"
            echo "  git@github.com:username/vault-argo-cd-demo.git"
            echo ""
            read -p "Repository URL: " REPO_URL
            
            if [ -z "$REPO_URL" ]; then
                print_error "Repository URL is required for GitOps workflow"
                exit 1
            fi
            
            print_status "Adding remote origin..."
            git remote add origin "$REPO_URL"
        fi
    else
        print_status "Initializing git repository..."
        git init
        print_success "Git repository initialized"
        
        # Get repository URL from user
        echo ""
        print_status "Please provide your GitHub repository URL:"
        echo "Examples:"
        echo "  https://github.com/username/vault-argo-cd-demo"
        echo "  git@github.com:username/vault-argo-cd-demo.git"
        echo ""
        read -p "Repository URL: " REPO_URL
        
        if [ -z "$REPO_URL" ]; then
            print_error "Repository URL is required for GitOps workflow"
            exit 1
        fi
        
        print_status "Adding remote origin..."
        git remote add origin "$REPO_URL"
    fi
    
    # Create .gitignore if it doesn't exist
    if [ ! -f ".gitignore" ]; then
        print_status "Creating .gitignore..."
        cat > .gitignore << 'EOF'
# Demo generated files
argocd-values.yaml
debug-logs/

# Vault license (NEVER commit this!)
vault.hclic

# macOS
.DS_Store

# Temporary files
*.tmp
/tmp/

# IDE files
.vscode/
.idea/
EOF
        print_success ".gitignore created"
    fi
else
    # Get existing repository URL for later use
    REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
fi

# Step 1: Start Vault Enterprise
if [[ " ${MISSING_COMPONENTS[*]} " =~ " Vault " ]]; then
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
fi

# Step 2: Install required tools
if [[ " ${MISSING_COMPONENTS[*]} " =~ " Tools:" ]]; then
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
fi

# Step 3: Start Minikube
if [[ " ${MISSING_COMPONENTS[*]} " =~ " Minikube " ]] || [[ " ${MISSING_COMPONENTS[*]} " =~ " Kubernetes cluster " ]]; then
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
fi

# Step 4: Configure Vault
if [[ " ${MISSING_COMPONENTS[*]} " =~ " Vault " ]] || [[ " ${MISSING_COMPONENTS[*]} " =~ " Vault Kubernetes auth " ]]; then
    print_status "Step 4: Configuring Vault for Kubernetes authentication..."

    # Set Vault environment variables
    export VAULT_ADDR="http://127.0.0.1:8200"
    export VAULT_TOKEN="root"

    # Enable Kubernetes auth method
    if ! vault auth list | grep -q kubernetes; then
        vault auth enable kubernetes
        print_success "Kubernetes auth method enabled"
    else
        print_success "Kubernetes auth method already enabled"
    fi
fi

# Step 5: Create Vault secrets
if [[ " ${MISSING_COMPONENTS[*]} " =~ " Vault secrets " ]]; then
    print_status "Step 5: Creating sample secrets in Vault..."

    # Set Vault environment variables
    export VAULT_ADDR="http://127.0.0.1:8200"
    export VAULT_TOKEN="root"

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
fi

# Step 6: Install ArgoCD with Vault Plugin
if [[ " ${MISSING_COMPONENTS[*]} " =~ " ArgoCD " ]] || [[ " ${MISSING_COMPONENTS[*]} " =~ " Vault plugin config " ]]; then
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
fi

# Step 7: Configure Vault policy and authentication
if [[ " ${MISSING_COMPONENTS[*]} " =~ " Vault Kubernetes auth " ]] || [[ " ${MISSING_COMPONENTS[*]} " =~ " ArgoCD " ]]; then
    print_status "Step 7: Configuring Vault policies and authentication..."

    # Set Vault environment variables
    export VAULT_ADDR="http://127.0.0.1:8200"
    export VAULT_TOKEN="root"

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
fi

# Step 8: Create demo application
if [[ " ${MISSING_COMPONENTS[*]} " =~ " Demo app manifests " ]] || [[ " ${MISSING_COMPONENTS[*]} " =~ " Vault placeholders in manifests " ]]; then
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
fi

# Step 9: Update ArgoCD application template and create ready-to-use manifest
# This step runs if we have Git setup or if manifests were created
if [ -n "$REPO_URL" ] || [[ " ${MISSING_COMPONENTS[*]} " =~ " Demo app manifests " ]]; then
    print_status "Step 9: Configuring ArgoCD application for your repository..."

    # Get repository URL if not already set
    if [ -z "$REPO_URL" ]; then
        REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
    fi

    if [ -n "$REPO_URL" ]; then
        # Update ArgoCD application template
        sed -i.bak "s|repoURL: https://github.com/ignacio-hernani/vault-argo-cd-demo|repoURL: $REPO_URL|g" argocd-application-template.yaml 2>/dev/null || true
        rm -f argocd-application-template.yaml.bak

        # Create ready-to-use application manifest
        cat > vault-demo-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vault-demo
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: $REPO_URL
    targetRevision: HEAD
    path: demo-app/manifests
    
    plugin:
      name: argocd-vault-plugin
      env:
        - name: VAULT_ADDR
          value: "http://host.minikube.internal:8200"
        - name: AVP_TYPE
          value: "vault"
        - name: AVP_AUTH_TYPE
          value: "token"
        - name: VAULT_TOKEN
          value: "root"
  
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

        print_success "ArgoCD application manifest created: vault-demo-app.yaml"
    fi
fi

# Step 10: Commit and push to GitHub
if [[ " ${MISSING_COMPONENTS[*]} " =~ " Git " ]] || [[ " ${MISSING_COMPONENTS[*]} " =~ " Demo app manifests " ]]; then
    print_status "Step 10: Committing and pushing to GitHub..."

    # Stage and commit all files
    print_status "Staging files for commit..."
    git add .

    # Check if there are changes to commit
    if git diff --staged --quiet; then
        print_warning "No changes to commit"
    else
        print_status "Committing files..."
        git commit -m "Initial commit: Vault + ArgoCD integration demo

- Complete demo setup with automated scripts
- Comprehensive documentation and troubleshooting guides
- ArgoCD Vault Plugin integration
- Sample application with secret injection
- Verification and cleanup scripts"
        print_success "Files committed"
    fi

    # Push to GitHub
    print_status "Pushing to GitHub..."
    if git push -u origin main 2>/dev/null || git push -u origin master 2>/dev/null; then
        print_success "Successfully pushed to GitHub!"
    else
        print_warning "Push failed. You may need to:"
        echo "1. Create the repository on GitHub first"
        echo "2. Set up authentication (SSH keys or personal access token)"
        echo "3. Run: git push -u origin main"
    fi
fi

# Get Argo CD admin password
print_status "Retrieving Argo CD admin credentials..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "")

# Final instructions
echo ""
echo "Demo setup completed successfully!"
echo "===================================="
echo ""
if [ -n "$REPO_URL" ]; then
    print_success "Your repository: $REPO_URL"
fi
print_success "Next steps:"
echo ""
echo "1. Apply the ArgoCD application:"
echo "   kubectl apply -f vault-demo-app.yaml"
echo ""
echo "2. Watch the application sync:"
echo "   kubectl get applications -n argocd -w"
echo ""
echo "3. Access ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Then open: https://localhost:8080"
if [ -n "$ARGOCD_PASSWORD" ]; then
    echo "   Username: admin"
    echo "   Password: $ARGOCD_PASSWORD"
fi
echo ""
echo "4. Monitor the deployment:"
echo "   kubectl get pods -n default -w"
echo ""
print_warning "The demo will now pull manifests from your GitHub repository!"
print_status "To clean up the environment later, run: ./03-cleanup.sh" 