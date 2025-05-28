#!/bin/bash

# GitHub Setup Script for Vault + ArgoCD Demo
# This script helps you set up the demo with a GitHub repository

set -e

echo "🐙 Setting up Vault + ArgoCD Demo with GitHub"
echo "============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if git is installed
if ! command -v git &> /dev/null; then
    print_error "Git is not installed. Please install git first."
    exit 1
fi

# Check if we're already in a git repository
if [ -d ".git" ]; then
    print_success "Already in a git repository"
    REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$REPO_URL" ]; then
        print_status "Current repository: $REPO_URL"
    else
        print_warning "No remote origin set"
    fi
else
    print_status "Initializing git repository..."
    git init
    print_success "Git repository initialized"
fi

# Get repository URL from user
echo ""
print_status "Please provide your GitHub repository URL:"
echo "Examples:"
echo "  https://github.com/username/vault-argo-cd-demo"
echo "  git@github.com:username/vault-argo-cd-demo.git"
echo ""
read -p "Repository URL: " REPO_URL

if [ -z "$REPO_URL" ]; then
    print_error "Repository URL is required"
    exit 1
fi

# Set up git remote
if git remote get-url origin >/dev/null 2>&1; then
    print_status "Updating existing remote origin..."
    git remote set-url origin "$REPO_URL"
else
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

# Update ArgoCD application template
print_status "Updating ArgoCD application template..."
sed -i.bak "s|repoURL: https://github.com/your-username/vault-argo-cd-demo|repoURL: $REPO_URL|g" argocd-application-template.yaml
rm -f argocd-application-template.yaml.bak
print_success "ArgoCD application template updated"

# Create updated application for immediate use
print_status "Creating ArgoCD application with your repository..."
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

echo ""
echo "🎉 GitHub setup completed!"
echo "========================="
echo ""
print_success "Next steps:"
echo "1. Apply the ArgoCD application:"
echo "   kubectl apply -f vault-demo-app.yaml"
echo ""
echo "2. Watch the application sync:"
echo "   kubectl get applications -n argocd -w"
echo ""
echo "3. Access ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Open: https://localhost:8080"
echo ""
echo "4. Monitor the deployment:"
echo "   kubectl get pods -n default -w"
echo ""
print_warning "Repository URL: $REPO_URL"
print_status "The demo will now pull manifests from your GitHub repository!" 