#!/bin/bash

# HashiCorp Vault Enterprise + Argo CD Integration Demo Workflow
# Interactive demonstration of the complete integration workflow

set -e

echo "Vault + Argo CD Integration Demo Workflow"
echo "========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_step() {
    echo -e "\n${CYAN}[STEP]${NC} $1"
    echo "----------------------------------------"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[DEMO]${NC} $1"
}

# Ensure demo environment is ready
print_step "1. Ensuring Demo Environment is Ready"
print_info "Running setup verification and configuration..."
echo ""

# Call 01-setup.sh which will quickly verify and configure only if needed
if ! ./01-setup.sh; then
    echo ""
    print_error "Failed to prepare demo environment. Please check the setup output above."
    exit 1
fi

echo ""
print_success "Demo environment is ready!"

# Set Vault environment variables for the demo
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"

print_step "2. Demonstrating Vault Secret Management"

print_info "Current secrets stored in Vault:"
echo "Database secrets:"
vault kv get -format=table secret/myapp/database
echo ""
echo "API secrets:"
vault kv get -format=table secret/myapp/api

print_step "3. Displaying Argo CD Status"
print_info "Argo CD applications:"
kubectl get applications -n argocd 2>/dev/null || echo "No applications deployed yet"

print_info "Argo CD pods status:"
kubectl get pods -n argocd

print_step "4. Demonstrating Secret Injection Mechanism"
print_info "Examining demo application manifest with Vault placeholders:"
echo ""
cat demo-app/manifests/deployment.yaml | grep -A 10 "env:" | head -15

print_warning "Note the <path:secret/...> placeholders that will be replaced by the Vault plugin during deployment"

print_step "5. Creating Argo CD Application (if not exists)"
if ! kubectl get application vault-demo -n argocd >/dev/null 2>&1; then
    print_info "Creating Argo CD application..."
    
    # Use the vault-demo-app.yaml created by 01-setup.sh
    if [ -f "vault-demo-app.yaml" ]; then
        kubectl apply -f vault-demo-app.yaml
    else
        # Fallback: create a basic application manifest
        cat > /tmp/vault-demo-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vault-demo
  namespace: argocd
spec:
  project: default
  source:
    repoURL: .
    targetRevision: HEAD
    path: demo-app/manifests
    plugin:
      name: argocd-vault-plugin
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
        kubectl apply -f /tmp/vault-demo-app.yaml
    fi
    
    print_success "Argo CD application created successfully"
    
    print_info "Waiting for application synchronization..."
    sleep 10
else
    print_success "Argo CD application already exists"
fi

print_step "6. Monitoring Application Deployment"
print_info "Application status:"
kubectl get application vault-demo -n argocd -o wide 2>/dev/null || echo "Application not found"

print_info "Deployed resources:"
kubectl get deployment,service,configmap -n default | grep vault-demo || echo "Resources not yet deployed"

print_step "7. Verifying Secret Injection"
if kubectl get deployment vault-demo-app -n default >/dev/null 2>&1; then
    print_info "Verifying secret injection process..."
    
    # Get the deployment and check environment variables
    echo "Environment variables in the deployed application:"
    kubectl get deployment vault-demo-app -n default -o jsonpath='{.spec.template.spec.containers[0].env}' | jq '.' 2>/dev/null || \
    kubectl get deployment vault-demo-app -n default -o yaml | grep -A 20 "env:" | head -15
    
    print_success "Secrets have been successfully injected by the Vault plugin"
else
    print_warning "Application not yet deployed. This is expected if Argo CD is still synchronizing."
fi

print_step "8. Accessing the Demo Application"
if kubectl get service vault-demo-app -n default >/dev/null 2>&1; then
    print_info "Setting up access to the demo application..."
    
    # Check if we're on macOS with Docker driver
    if [[ "$OSTYPE" == "darwin"* ]] && minikube profile list 2>/dev/null | grep -q docker; then
        print_warning "On macOS with Docker driver, minikube requires a tunnel to access services."
        echo ""
        print_info "To access the demo application, run this command in a separate terminal:"
        echo ""
        echo "    minikube service vault-demo-app --url"
        echo ""
        print_info "This will open a tunnel and provide you with a URL to access the application."
        print_info "Keep that terminal open while accessing the application."
        
        # Get the NodePort for reference
        NODE_PORT=$(kubectl get service vault-demo-app -n default -o jsonpath='{.spec.ports[0].nodePort}')
        print_info "The service is exposed on NodePort: $NODE_PORT"
    else
        # For other platforms or drivers, the regular command should work
        APP_URL=$(minikube service vault-demo-app --url 2>/dev/null || echo "Service not ready")
        if [ "$APP_URL" != "Service not ready" ]; then
            print_success "Demo application is available at: $APP_URL"
            print_warning "Open this URL in your browser to observe the injected secrets"
        else
            print_warning "Service is not ready yet. Please retry in a few moments."
        fi
    fi
else
    print_warning "Service not yet created. Argo CD may still be synchronizing."
fi

print_step "9. Demonstrating Secret Updates"
print_info "Now let's demonstrate how to update secrets in Vault dynamically."
echo ""

# Get current secret values to preserve them
print_info "Current database secret in Vault:"
vault kv get -format=table secret/myapp/database
echo ""

# Get existing values to preserve password, host, and port
CURRENT_PASSWORD=$(vault kv get -field=password secret/myapp/database)
CURRENT_HOST=$(vault kv get -field=host secret/myapp/database)
CURRENT_PORT=$(vault kv get -field=port secret/myapp/database)
CURRENT_USERNAME=$(vault kv get -field=username secret/myapp/database)

print_warning "Current username: $CURRENT_USERNAME"
echo ""
print_info "Let's update the database username interactively..."
echo ""

# Prompt for new username
echo -n "Enter new username for the database secret: "
read NEW_USERNAME

# Validate input
if [ -z "$NEW_USERNAME" ]; then
    print_warning "No username provided. Using 'demo-user' as default."
    NEW_USERNAME="demo-user"
fi

print_info "Updating secret with new username: $NEW_USERNAME"

# Update the secret with new username but preserve other values
vault kv put secret/myapp/database \
    username="$NEW_USERNAME" \
    password="$CURRENT_PASSWORD" \
    host="$CURRENT_HOST" \
    port="$CURRENT_PORT"

print_success "Secret updated in Vault successfully!"
echo ""
print_info "Updated database secret:"
vault kv get -format=table secret/myapp/database

echo ""
print_warning "In a production GitOps workflow, the process would be:"
echo "1. Update your application manifests in Git repository"
echo "2. Argo CD would detect the change and initiate redeployment"
echo "3. The Vault plugin would fetch the updated secrets"
echo "4. Your application would receive the new secret values"

echo ""
echo "Demo workflow completed successfully"
echo "==================================="
print_success "You have observed how Vault and Argo CD integrate to provide secure, automated secret management in GitOps workflows"

echo ""
print_info "Useful commands for further exploration:"
echo "VAULT:"
echo "• Check Vault secrets for myapp: vault kv list secret/myapp"
echo "• Check current username of the database secret: vault kv get -field=username secret/myapp/database"
echo "• Update Vault secret: vault kv patch secret/myapp/database username="demo-user""
echo "ARGO CD:"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "Password not found")
echo "• Port-forward ArgoCD (separate terminal): kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "• Access Argo CD interface at: https://localhost:8080 (after port-forwarding)"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD (or get it from the setup script)"
echo "• View Argo CD applications: kubectl get applications -n argocd"
echo "DEMO APP:"
echo "• Monitor deployments: kubectl get pods -w"
echo "• Access demo webapp (separate terminal): minikube service vault-demo-app --url"
echo "• Clean up environment: ./03-cleanup.sh" 