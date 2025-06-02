# Get Started in 5 Minutes

Welcome to the Vault + Argo CD integration demonstration. This guide provides rapid deployment instructions for the complete demonstration environment.

## Prerequisites

- macOS with Docker Desktop running
- Terminal access
- Vault Enterprise license file (`vault.hclic`) in this directory
- GitHub account and repository for proper GitOps workflow

## Step 1: Run the Complete Setup

```bash
./setup-demo.sh
```

**What this does:**
This script verifies the current environment and identifies whether complete/partial/none setup needs to be performed. The complete setup is:
- Sets up GitHub repository integration
- Installs required tools (minikube, kubectl, helm)
- Starts Vault Enterprise and creates sample secrets
- Sets up a local Kubernetes cluster
- Installs ArgoCD with the Vault plugin
- Configures authentication between all components
- Creates demonstration application manifests
- Commits and pushes demo to your GitHub repository
- Creates ready-to-use ArgoCD application manifest

**Duration:** Approximately 5-10 minutes (or instant if already configured)

**Repository setup:** The script will prompt you for your GitHub repository URL and handle all Git configuration automatically.

## Step 2: Deploy the Application

```bash
# Apply the Argo CD application (uses your GitHub repository)
kubectl apply -f vault-demo-app.yaml

# Monitor the synchronization process
kubectl get applications -n argocd -w
```

**Alternative:** Create the application via Argo CD UI:
1. Click "NEW APP" in Argo CD interface
2. Configure using the template below
3. Click "CREATE"

### Argo CD Application Configuration Template

```yaml
Application Name: vault-demo
Project: default
Sync Policy: Automatic

Source:
  Repository URL: [YOUR_GIT_REPO_URL]
  Revision: HEAD
  Path: demo-app/manifests

Destination:
  Cluster URL: https://kubernetes.default.svc
  Namespace: default

Plugin: argocd-vault-plugin
```

## Step 3: Execute Demo Workflow

```bash
./demo-workflow.sh
```

**What this does:**
- **Automatically ensures environment is ready** (calls setup-demo.sh if needed)
- Demonstrates how secrets are stored in Vault
- Shows how Argo CD deploys applications
- Illustrates how the Vault plugin injects secrets
- Walks through the complete GitOps workflow
- Updates secrets in real-time to show dynamic capabilities

**Note:** The demo workflow automatically verifies and sets up the environment, so you can run it directly even if you're unsure about the setup status.

## Step 4: Access the UIs

### Argo CD Dashboard
```bash
# In a new terminal window:
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Then open: https://localhost:8080
# Username: admin
# Password: (shown at end of setup script)
```

### Demo Application
```bash
# Get the application URL:
minikube service vault-demo-app --url

# Open the URL in your browser to observe secret injection
```

## Step 5: Experiment with the Integration

Execute these commands to observe the integration in action:

```bash
# Update a secret in Vault
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"
vault kv put secret/myapp/database username="new-user" password="new-password"

# Watch ArgoCD sync the changes
kubectl get applications -n argocd -w

# Verify the updated deployment
kubectl get deployment vault-demo-app -o yaml | grep -A 10 env:
```

## Expected Results

1. **Argo CD Dashboard**: Displays application synchronization status
2. **Vault Secrets**: Demonstration database and API credentials
3. **Demo Application**: Web interface showing secret injection process
4. **Kubernetes Resources**: Deployment, Service, and ConfigMap objects

## Troubleshooting

### Common Issues:

**Argo CD cannot reach Vault:**
- Re-run setup script: `./setup-demo.sh` (it will verify and fix issues)
- Verify Vault status: `vault status`
- Test minikube connectivity: `minikube ssh -- curl http://host.minikube.internal:8200/v1/sys/health`

**Application synchronization failure:**
- Check Argo CD logs: `kubectl logs -n argocd deployment/argocd-repo-server`
- Verify plugin installation: `kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-repo-server`

**Secret injection failure:**
- Verify Vault policies: `vault policy read argocd-policy`
- Check Kubernetes authentication: `vault auth list`

**Environment appears broken:**
- Run the setup script again: `./setup-demo.sh` (it will identify and fix issues)

## Environment Cleanup

When you're done:

```bash
./cleanup-demo.sh
```

The Vault plugin intercepts `<path:...>` placeholders in your manifests and replaces them with actual secrets from Vault before applying to Kubernetes.

## Support Resources

- **Detailed documentation** → See `README.md`
- **Troubleshooting** → See `TROUBLESHOOTING.md`

---

**That's it! The setup script intelligently handles verification and configuration, making the demo experience seamless.** 