#!/bin/bash

# Vault + ArgoCD Integration Demo Verification Script
# This script verifies that all components are working correctly

set -e

echo "🔍 Verifying Vault + ArgoCD Demo Setup"
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Track overall status
OVERALL_STATUS=0

# Function to check and report status
check_status() {
    if [ $1 -eq 0 ]; then
        print_success "$2"
    else
        print_error "$2"
        OVERALL_STATUS=1
    fi
}

echo "Checking prerequisites and components..."
echo ""

# Check 1: Docker
print_status "Checking Docker..."
if docker info >/dev/null 2>&1; then
    print_success "Docker is running"
else
    print_error "Docker is not running"
    OVERALL_STATUS=1
fi

# Check 2: Vault
print_status "Checking Vault..."
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"

if vault status >/dev/null 2>&1; then
    print_success "Vault is accessible"
    
    # Check Vault secrets
    print_status "Checking Vault secrets..."
    if vault kv get secret/myapp/database >/dev/null 2>&1; then
        print_success "Sample secrets exist in Vault"
    else
        print_error "Sample secrets not found in Vault"
        OVERALL_STATUS=1
    fi
    
    # Check Vault auth methods
    print_status "Checking Vault auth methods..."
    if vault auth list | grep -q kubernetes; then
        print_success "Kubernetes auth method enabled"
    else
        print_error "Kubernetes auth method not enabled"
        OVERALL_STATUS=1
    fi
else
    print_error "Vault is not accessible"
    OVERALL_STATUS=1
fi

# Check 3: Minikube
print_status "Checking Minikube..."
if minikube status | grep -q "Running"; then
    print_success "Minikube is running"
    
    # Check cluster connectivity
    print_status "Checking Kubernetes cluster..."
    if kubectl cluster-info >/dev/null 2>&1; then
        print_success "Kubernetes cluster is accessible"
    else
        print_error "Kubernetes cluster is not accessible"
        OVERALL_STATUS=1
    fi
else
    print_error "Minikube is not running"
    OVERALL_STATUS=1
fi

# Check 4: ArgoCD
print_status "Checking ArgoCD installation..."
if kubectl get namespace argocd >/dev/null 2>&1; then
    print_success "ArgoCD namespace exists"
    
    # Check ArgoCD pods
    print_status "Checking ArgoCD pods..."
    if kubectl get pods -n argocd | grep -q "Running"; then
        print_success "ArgoCD pods are running"
        
        # Check ArgoCD server specifically
        if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
            READY=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.readyReplicas}')
            DESIRED=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.replicas}')
            if [ "$READY" = "$DESIRED" ] && [ "$READY" != "" ]; then
                print_success "ArgoCD server is ready"
            else
                print_warning "ArgoCD server is not fully ready ($READY/$DESIRED replicas)"
            fi
        fi
    else
        print_error "ArgoCD pods are not running"
        OVERALL_STATUS=1
    fi
    
    # Check Vault plugin configuration
    print_status "Checking Vault plugin configuration..."
    if kubectl get configmap argocd-vault-plugin-config -n argocd >/dev/null 2>&1; then
        print_success "Vault plugin configuration exists"
    else
        print_error "Vault plugin configuration not found"
        OVERALL_STATUS=1
    fi
else
    print_error "ArgoCD namespace not found"
    OVERALL_STATUS=1
fi

# Check 5: Network connectivity from minikube to Vault
print_status "Checking network connectivity from minikube to Vault..."
if minikube ssh -- curl -s http://host.minikube.internal:8200/v1/sys/health >/dev/null 2>&1; then
    print_success "Minikube can reach Vault"
else
    print_error "Minikube cannot reach Vault"
    OVERALL_STATUS=1
fi

# Check 6: Demo application manifests
print_status "Checking demo application manifests..."
if [ -d "demo-app/manifests" ] && [ -f "demo-app/manifests/deployment.yaml" ]; then
    print_success "Demo application manifests exist"
    
    # Check for Vault placeholders
    if grep -q "<path:secret" demo-app/manifests/deployment.yaml; then
        print_success "Vault placeholders found in manifests"
    else
        print_warning "No Vault placeholders found in manifests"
    fi
else
    print_error "Demo application manifests not found"
    OVERALL_STATUS=1
fi

# Check 7: Required tools
print_status "Checking required tools..."
TOOLS=("kubectl" "helm" "minikube" "vault")
for tool in "${TOOLS[@]}"; do
    if command -v $tool >/dev/null 2>&1; then
        print_success "$tool is installed"
    else
        print_error "$tool is not installed"
        OVERALL_STATUS=1
    fi
done

echo ""
echo "======================================"

if [ $OVERALL_STATUS -eq 0 ]; then
    print_success "All checks passed! Your demo setup is ready."
    echo ""
    echo "Next steps:"
    echo "1. Access ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "2. Create an ArgoCD application using the template in argocd-application-template.yaml"
    echo "3. Watch the magic happen!"
else
    print_error "Some checks failed. Please review the errors above."
    echo ""
    echo "Common fixes:"
    echo "- Run './setup-demo.sh' to set up missing components"
    echo "- Ensure Docker Desktop is running"
    echo "- Check that your Vault license file exists"
    echo ""
    echo "For detailed troubleshooting, see the README.md file."
fi

echo ""
echo "For more help, run: kubectl get pods --all-namespaces"
echo "Or check logs: kubectl logs -n argocd deployment/argocd-server"

exit $OVERALL_STATUS 