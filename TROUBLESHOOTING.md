# Troubleshooting Guide

This guide covers common issues and their solutions for the Vault + Argo CD integration demo.

## Quick Diagnostics

If you're experiencing issues, start with these diagnostic steps:

```bash
./01-setup.sh  # This will verify and fix any configuration issues
```

The setup script now includes comprehensive verification and will automatically detect and fix most common issues.

## Common Issues and Solutions 🛠️

### 1. Vault Issues

#### "Vault is not accessible"

**Symptoms:**
- `vault status` fails
- Error: "connection refused" or "no such host"

**Solutions:**
```bash
# Check if Vault container is running
docker ps | grep vault-enterprise

# If not running, start Vault
./vault.sh

# Wait for initialization and test
sleep 10
vault status

# Check Vault logs if still failing
docker logs vault-enterprise
```

#### "Sample secrets not found in Vault"

**Symptoms:**
- Vault is running but secrets are missing
- Error: "No value found at secret/myapp/database"

**Solutions:**
```bash
# Set Vault environment variables
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"

# Enable KV engine if needed
vault secrets enable -path=secret kv-v2

# Create the missing secrets
vault kv put secret/myapp/database \
    username="myuser" \
    password="supersecret123" \
    host="db.example.com" \
    port="5432"

vault kv put secret/myapp/api \
    key="api-key-12345" \
    endpoint="https://api.example.com"
```

#### "Kubernetes auth method not enabled"

**Solutions:**
```bash
# Enable Kubernetes auth
vault auth enable kubernetes

# Configure it (run after Argo CD is installed)
./01-setup.sh  # This will reconfigure everything
```

### 2. Minikube/Kubernetes Issues

#### "Minikube is not running"

**Solutions:**
```bash
# Start minikube
minikube start --driver=docker --cpus=4 --memory=6144

# If it fails to start, try deleting and recreating
minikube delete
minikube start --driver=docker --cpus=4 --memory=6144

# Check status
minikube status
```

#### "Kubernetes cluster is not accessible"

**Solutions:**
```bash
# Check kubectl configuration
kubectl config current-context

# Should show "minikube"
# If not, set the context
kubectl config use-context minikube

# Test cluster access
kubectl cluster-info
```

#### "Minikube cannot reach Vault"

**Symptoms:**
- Network connectivity test fails
- Argo CD cannot authenticate to Vault

**Solutions:**
```bash
# Test connectivity from minikube
minikube ssh -- curl http://host.minikube.internal:8200/v1/sys/health

# If this fails, check Docker network settings
# Restart minikube with fresh network
minikube stop
minikube start

# On some systems, you might need to use the host IP instead
VAULT_ADDR="http://$(minikube ssh -- route -n | grep '^0.0.0.0' | awk '{print $2}'):8200"
```

#### "Docker Desktop has only XXXMB memory but you specified XXXMB"

**Symptoms:**
- Minikube fails to start with memory allocation error
- Error mentions Docker Desktop memory limits

**Solutions:**
```bash
# Option 1: Use less memory for minikube (recommended)
minikube start --driver=docker --cpus=4 --memory=6144

# Option 2: Increase Docker Desktop memory allocation
# 1. Open Docker Desktop
# 2. Go to Settings → Resources → Advanced
# 3. Increase Memory to at least 10GB
# 4. Click "Apply & Restart"
# 5. Wait for Docker to restart
# 6. Try the setup again

# Option 3: Use even less memory if needed
minikube start --driver=docker --cpus=2 --memory=4096
```

**Note:** The demo works fine with 6GB of memory. Only increase Docker Desktop's allocation if you need more resources for other containers.

### 3. Argo CD Issues

#### "Argo CD namespace not found"

**Solutions:**
```bash
# Create the namespace
kubectl create namespace argocd

# Run the setup script to install Argo CD
./01-setup.sh
```

#### "Argo CD pods are not running"

**Solutions:**
```bash
# Check pod status
kubectl get pods -n argocd

# Check for issues
kubectl describe pods -n argocd

# Check events
kubectl get events -n argocd --sort-by='.lastTimestamp'

# If pods are stuck, try restarting
kubectl rollout restart deployment -n argocd
```

#### "Vault plugin configuration not found"

**Solutions:**
```bash
# Recreate the plugin configuration
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
'

# Restart Argo CD repo server
kubectl rollout restart deployment argocd-repo-server -n argocd
```

### 4. Application Deployment Issues

#### "Application won't sync"

**Symptoms:**
- Argo CD shows "OutOfSync" status
- Sync operation fails

**Solutions:**
```bash
# Check Argo CD application status
kubectl describe application vault-demo -n argocd

# Check Argo CD repo server logs
kubectl logs -n argocd deployment/argocd-repo-server -c avp

# Check for plugin errors
kubectl logs -n argocd deployment/argocd-repo-server -c argocd-repo-server

# Force refresh and sync
kubectl patch application vault-demo -n argocd --type merge -p='{"operation":{"sync":{"revision":"HEAD"}}}'
```

#### "Secrets not injected properly"

**Symptoms:**
- Application deploys but environment variables show `<path:...>` instead of actual values
- Pods fail to start due to invalid configuration

**Solutions:**
```bash
# Check if Vault plugin is working
kubectl logs -n argocd deployment/argocd-repo-server -c avp

# Verify Vault authentication
vault auth list
vault policy read argocd-policy

# Test Vault access from Argo CD pod
kubectl exec -n argocd deployment/argocd-repo-server -c avp -- env | grep VAULT

# Check the generated manifests
kubectl get deployment vault-demo-app -o yaml | grep -A 10 env:
```

### 5. Network and Connectivity Issues

#### "Connection timeouts"

**Solutions:**
```bash
# Check Docker Desktop is running and healthy
docker system info

# Restart Docker Desktop if needed
# Check available resources (CPU/Memory)

# Increase minikube resources
minikube stop
minikube start --driver=docker --cpus=6 --memory=6144
```

#### "DNS resolution issues"

**Solutions:**
```bash
# Test DNS from minikube
minikube ssh -- nslookup host.minikube.internal

# If DNS fails, restart minikube
minikube stop
minikube start

# Alternative: Use IP address instead of hostname
MINIKUBE_HOST_IP=$(minikube ssh -- route -n | grep '^0.0.0.0' | awk '{print $2}')
echo "Use this IP instead of host.minikube.internal: $MINIKUBE_HOST_IP"
```

## Advanced Debugging

### Check All Component Status

```bash
# Comprehensive status check
echo "=== Docker ==="
docker ps | grep vault

echo "=== Vault ==="
vault status

echo "=== Minikube ==="
minikube status

echo "=== Kubernetes ==="
kubectl get nodes
kubectl get pods --all-namespaces

echo "=== Argo CD ==="
kubectl get pods -n argocd
kubectl get applications -n argocd

echo "=== Demo App ==="
kubectl get pods -n default
kubectl get svc -n default
```

### Collect Logs

```bash
# Create a logs directory
mkdir -p debug-logs

# Collect Vault logs
docker logs vault-enterprise > debug-logs/vault.log 2>&1

# Collect Argo CD logs
kubectl logs -n argocd deployment/argocd-server > debug-logs/argocd-server.log 2>&1
kubectl logs -n argocd deployment/argocd-repo-server -c argocd-repo-server > debug-logs/argocd-repo-server.log 2>&1
kubectl logs -n argocd deployment/argocd-repo-server -c avp > debug-logs/argocd-vault-plugin.log 2>&1

# Collect Kubernetes events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' > debug-logs/k8s-events.log

echo "Logs collected in debug-logs/ directory"
```

### Test Vault Plugin Manually

```bash
# Download and test the plugin manually
wget -O /tmp/argocd-vault-plugin https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v1.17.0/argocd-vault-plugin_1.17.0_darwin_amd64
chmod +x /tmp/argocd-vault-plugin

# Set environment variables
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"
export AVP_TYPE="vault"
export AVP_AUTH_TYPE="token"

# Test plugin on demo manifests
cd demo-app/manifests
/tmp/argocd-vault-plugin generate ./
```

## Complete Reset

If all troubleshooting steps fail, completely reset the demonstration environment:

```bash
# Clean up everything
./03-cleanup.sh

# Wait for cleanup completion
sleep 5

# Start fresh
./01-setup.sh
```

## Support Information

If you're still having issues:

1. **Check the logs** using the commands above
2. **Run the setup script**: `./01-setup.sh` (it includes verification and will identify and fix issues)
3. **Review error messages** carefully
4. **Check system resources** (CPU, memory, disk space)
5. **Restart Docker Desktop** if needed

### Common Error Patterns

| Error Message | Likely Cause | Solution |
|---------------|--------------|----------|
| `connection refused` | Service not running | Start the service |
| `no such host` | DNS/network issue | Check network configuration |
| `permission denied` | Authentication issue | Check tokens/credentials |
| `not found` | Resource missing | Create the resource |
| `timeout` | Resource constraints | Increase resources |

### System Requirements

Ensure your system meets these requirements:

- **macOS**: 10.14 or later
- **Docker Desktop**: 4.0 or later
- **RAM**: At least 8GB available
- **CPU**: At least 4 cores
- **Disk**: At least 10GB free space

---

This troubleshooting guide provides comprehensive solutions for common demonstration environment issues. The demonstration is designed for educational purposes and experimentation. 