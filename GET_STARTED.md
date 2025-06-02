# Get Started in 5 Minutes

Welcome to the Vault + Argo CD integration demonstration. This guide provides rapid deployment instructions for the complete demonstration environment.

## Prerequisites

- macOS with Docker Desktop running
- Terminal access
- Vault Enterprise license file (`vault.hclic`) in this directory
- **GitHub account** and repository for proper GitOps workflow

## Step 1: Run the Complete Setup

```bash
./setup-demo.sh
```

**What this does:**
- Sets up GitHub repository integration
- Installs required tools (minikube, kubectl, helm)
- Starts Vault Enterprise and creates sample secrets
- Sets up a local Kubernetes cluster
- Installs ArgoCD with the Vault plugin
- Configures authentication between all components
- Creates demonstration application manifests
- Commits and pushes demo to your GitHub repository
- Creates ready-to-use ArgoCD application manifest

**Duration:** Approximately 5-10 minutes

**Repository setup:** The script will prompt you for your GitHub repository URL and handle all Git configuration automatically.

## Step 2: Verify Environment

```bash
./verify-setup.sh
```

**Verification includes:**
- All services are operational
- Network connectivity is functional
- Vault plugin is properly configured

## Step 3: Deploy the Application

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

## Step 4: Execute Demo Workflow

```bash
./demo.sh
```

**Demo includes:**
- How secrets are stored in Vault
- How Argo CD deploys applications
- How the Vault plugin injects secrets
- The complete GitOps workflow

## Step 5: Access the UIs

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

## Step 6: Experiment with the Integration

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
- Verify Vault status: `vault status`
- Test minikube connectivity: `minikube ssh -- curl http://host.minikube.internal:8200/v1/sys/health`

**Application synchronization failure:**
- Check Argo CD logs: `kubectl logs -n argocd deployment/argocd-repo-server`
- Verify plugin installation: `kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-repo-server`

**Secret injection failure:**
- Verify Vault policies: `vault policy read argocd-policy`
- Check Kubernetes authentication: `vault auth list`

## Environment Cleanup

When you're done:

```bash
./cleanup-demo.sh
```

The Vault plugin intercepts `<path:...>` placeholders in your manifests and replaces them with actual secrets from Vault before applying to Kubernetes.

## Support Resources

- **Detailed documentation** → See `README.md`
- **Troubleshooting** → See `TROUBLESHOOTING.md`  
- **Demo overview** → See `DEMO_SUMMARY.md`

---

**That's it! You now have a working Vault + ArgoCD integration demo running locally. ** 