#!/bin/bash

# HashiCorp Vault Enterprise + Argo CD Integration Demo Cleanup Script
# Automated cleanup process for demonstration environment resources

set -e  # Exit on any error

echo "Initializing Vault + Argo CD Demo Environment Cleanup"
echo "===================================================="

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

# Ask for confirmation
echo "This operation will remove all demonstration resources including:"
echo "- Argo CD installation"
echo "- Demonstration application"
echo "- Minikube cluster"
echo "- Vault container"
echo "- Generated configuration files"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup operation cancelled."
    exit 0
fi

# Stop any port forwarding
print_status "Terminating port forwarding processes..."
pkill -f "kubectl port-forward" 2>/dev/null || true
print_success "Port forwarding processes terminated"

# Delete ArgoCD application if it exists
print_status "Cleaning up ArgoCD application..."
if kubectl get application vault-demo -n argocd >/dev/null 2>&1; then
    kubectl delete application vault-demo -n argocd
    print_success "ArgoCD application deleted"
else
    print_status "ArgoCD application not found, skipping"
fi

# Delete demo app resources
print_status "Cleaning up demo application resources..."
kubectl delete deployment,service,configmap vault-demo-app -n default 2>/dev/null || true
print_success "Demo application resources cleaned up"

# Delete ArgoCD installation
print_status "Uninstalling ArgoCD..."
if helm list -n argocd | grep -q argocd 2>/dev/null; then
    helm uninstall argocd -n argocd
    print_success "ArgoCD uninstalled"
else
    print_status "Argo CD installation not found, skipping"
fi

# Delete ArgoCD namespace
print_status "Deleting ArgoCD namespace..."
kubectl delete namespace argocd 2>/dev/null || true
print_success "ArgoCD namespace deleted"

# Stop minikube
print_status "Stopping minikube cluster..."
if minikube status | grep -q "Running" 2>/dev/null; then
    minikube stop
    print_success "Minikube cluster stopped"
else
    print_status "Minikube cluster not running, skipping"
fi

# Ask if user wants to delete minikube cluster entirely
echo ""
read -p "Do you want to delete the minikube cluster entirely? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Deleting minikube cluster..."
    minikube delete
    print_success "Minikube cluster deleted"
fi

# Stop Vault container
print_status "Stopping Vault container..."
if docker ps | grep -q vault-enterprise 2>/dev/null; then
    docker stop vault-enterprise
    print_success "Vault container stopped"
else
    print_status "Vault container not running, skipping"
fi

# Clean up generated files
print_status "Cleaning up generated files..."
rm -f argocd-values.yaml
rm -rf demo-app/
print_success "Generated files cleaned up"

echo ""
echo "🎉 Cleanup completed successfully!"
echo "================================="
echo ""
print_success "All demo resources have been cleaned up."
print_status "You can now run './setup-demo.sh' again to restart the demo."
echo ""
print_warning "Note: Your Vault license file and original application files were preserved." 