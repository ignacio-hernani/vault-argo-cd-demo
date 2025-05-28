# HashiCorp Vault Enterprise + Argo CD Integration Demo

This comprehensive guide demonstrates the integration between HashiCorp Vault Enterprise and Argo CD using the Argo CD Vault Plugin approach. The documentation provides detailed explanations for users with limited Kubernetes experience.

## Overview

This demonstration creates a local environment where:
1. **Minikube** provides a local Kubernetes cluster for testing
2. **HashiCorp Vault Enterprise** manages secrets centrally with enterprise-grade security
3. **Argo CD with Vault Plugin** enables GitOps deployments with dynamic secret injection
4. **Sample Application** demonstrates real-world secret injection patterns

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Git Repo      │    │   Argo CD       │    │   Vault         │
│   (Manifests)   │───▶│   (with Plugin) │───▶│   (Secrets)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   Kubernetes    │
                       │   (Application) │
                       └─────────────────┘
```

## Prerequisites

- macOS with Homebrew installed
- Docker Desktop installed and running
- A valid Vault Enterprise license file named `vault.hclic` in this directory
- Basic terminal/command line knowledge

**Security Notice**: Never commit your `vault.hclic` license file to a public repository. The file is included in `.gitignore` to prevent accidental commits. Maintain proper security protocols when handling license files.

## Core Concepts Demonstrated

This demo illustrates several key concepts:

*   **GitOps**: Using Git as the single source of truth for declarative infrastructure and applications.
*   **Secrets Management**: Securely storing and accessing sensitive data using HashiCorp Vault.
*   **Kubernetes**: Container orchestration for deploying and managing the application.
*   **Argo CD**: A declarative, GitOps continuous delivery tool for Kubernetes.
*   **Argo CD Vault Plugin (AVP)**: An Argo CD plugin to retrieve secrets from Vault and inject them into Kubernetes manifests before deployment.

## Implementation Guide

### Step 1: Vault Enterprise Setup

Your Vault Enterprise instance should be running from the provided `vault.sh` script. Verify the installation:

```bash
# Check if Vault is running
vault status
```

If not running, execute:
```bash
./vault.sh
```

**Technical Note**: Vault runs in Docker using "dev mode" with an unsealed state and root token. This configuration is suitable for demonstration purposes only and should never be used in production environments.

### Step 2: Install Required Tools

```bash
# Install minikube (local Kubernetes cluster)
brew install minikube

# Install kubectl (Kubernetes command-line tool)
brew install kubectl

# Install helm (Kubernetes package manager)
brew install helm

# Install vault CLI (if not already installed)
brew install vault
```

**Kubernetes Concepts:**
- **kubectl**: Your main tool to talk to Kubernetes clusters
- **minikube**: Creates a single-node Kubernetes cluster on your Mac
- **helm**: Package manager for Kubernetes applications

### Step 3: Initialize Minikube Cluster

```bash
# Start minikube with Docker driver
minikube start --driver=docker --cpus=4 --memory=6144

# Verify cluster is running
kubectl cluster-info
```

**Implementation Details**: Minikube creates a containerized Kubernetes cluster using Docker. The cluster operates within Docker containers rather than directly on the host system.

### Step 4: Configure Vault Authentication

```bash
# Set Vault environment variables
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"

# Enable Kubernetes auth method
vault auth enable kubernetes

# Configure Kubernetes auth (completed after Argo CD installation)
```

### Step 5: Create Vault Secrets

```bash
# Enable KV secrets engine
vault secrets enable -path=secret kv-v2

# Create sample database secret
vault kv put secret/myapp/database \
    username="myuser" \
    password="supersecret123" \
    host="db.example.com" \
    port="5432"

# Create API key secret
vault kv put secret/myapp/api \
    key="api-key-12345" \
    endpoint="https://api.example.com"

# Verify secret creation
vault kv get secret/myapp/database
vault kv get secret/myapp/api
```

**Purpose**: These secrets represent typical enterprise credentials such as database connection strings and API keys that would be managed centrally in production environments.

### Step 6: Install Argo CD with Vault Plugin

Deploy a customized Argo CD installation that includes the Vault plugin from initial setup.

```bash
# Create Argo CD namespace
kubectl create namespace argocd

# Add Argo CD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

Create the Argo CD configuration with Vault plugin:

```bash
cat > argocd-values.yaml << 'EOF'
configs:
  cm:
    # Enable the Vault plugin
    configManagementPlugins: |
      - name: argocd-vault-plugin
        generate:
          command: ["argocd-vault-plugin"]
          args: ["generate", "./"]

repoServer:
  # Install Vault plugin in the repo server
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
  
  # Configure the repo server container
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
```

Create the plugin configuration:

```bash
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
        - "find . -name '*.yaml' | xargs -I {} grep -l '<path\\|avp\\.kubernetes\\.io' {}"
  generate:
    command:
      - argocd-vault-plugin
      - generate
      - ./
  lockRepo: false
'
```

Install Argo CD:

```bash
# Install Argo CD with custom configuration
helm install argocd argo/argo-cd -n argocd -f argocd-values.yaml

# Wait for Argo CD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### Step 7: Access Argo CD Interface

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Enable port forwarding for UI access
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Access via browser: https://localhost:8080
# Username: admin
# Password: (from command above)
```

**Interface Details**: Argo CD provides a web-based interface for monitoring application deployments, sync status, and managing GitOps workflows.

### Step 8: Configure Vault Policy and Authentication

```bash
# Create a policy for ArgoCD to read secrets
vault policy write argocd-policy - << 'EOF'
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
EOF

# Get minikube IP for Kubernetes auth configuration
MINIKUBE_IP=$(minikube ip)

# Configure Kubernetes authentication
vault write auth/kubernetes/config \
    token_reviewer_jwt="$(kubectl get secret -n argocd $(kubectl get serviceaccount -n argocd argocd-server -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 -d)" \
    kubernetes_host="https://${MINIKUBE_IP}:8443" \
    kubernetes_ca_cert="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)"

# Create a role for ArgoCD
vault write auth/kubernetes/role/argocd \
    bound_service_account_names=argocd-server \
    bound_service_account_namespaces=argocd \
    policies=argocd-policy \
    ttl=1h
```

### Step 9: Create Application Manifests with Vault Integration

Let's modify our application to use Vault secrets:

```bash
mkdir -p demo-app/manifests
```

Create a deployment that uses Vault secrets:

```bash
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
            
            <h2>How it works:</h2>
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
```

### Step 10: Create Argo CD Application

```bash
cat > demo-app/application.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vault-demo
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-username/vault-argo-cd-demo
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
```

Deploy the application:

```bash
kubectl apply -f demo-app/application.yaml
```

### Step 11: Verify Integration

```bash
# Check if the application is synced
kubectl get applications -n argocd

# Verify deployed resources
kubectl get pods -n default

# Check if secrets were properly injected
kubectl describe deployment vault-demo-app -n default

# Access the application
minikube service vault-demo-app --url
```

## Technical Implementation Details

### Key Kubernetes Concepts

1. **Namespace**: Like folders for organizing resources in Kubernetes
2. **Deployment**: Describes how to run your application (how many copies, what image, etc.)
3. **Service**: Provides a stable way to access your application
4. **ConfigMap**: Stores configuration data that pods can use
5. **Secret**: Sensitive data storage (replaced by Vault in this implementation)

### Vault Plugin Workflow

1. **Detection**: Argo CD scans manifests for `<path:...>` placeholder patterns
2. **Authentication**: Plugin authenticates to Vault using Kubernetes service account
3. **Secret Retrieval**: Plugin fetches secrets from specified Vault paths
4. **Injection**: Placeholders are replaced with actual secret values
5. **Deployment**: Final manifests with resolved secrets are applied to Kubernetes

### Security Benefits:

- Centralized secret management through Vault
- No secrets stored in Git repositories
- Comprehensive audit trail of secret access
- Dynamic secret rotation capabilities
- Fine-grained access control policies

## Learning Outcomes

After completing this demonstration, you will understand:

*   How GitOps workflows can securely handle sensitive data.
*   The benefits of centralized secret management with HashiCorp Vault.
*   The role and functionality of the Argo CD Vault Plugin.
*   Core Kubernetes concepts related to application deployment and configuration.
*   Best practices for separating secrets from application manifests.
*   The synergy between Argo CD and Vault for secure, automated deployments.

## Environment Cleanup 

When demonstration is complete:

```bash
# Delete the ArgoCD application
kubectl delete application vault-demo -n argocd

# Remove demo application resources
kubectl delete deployment,service,configmap vault-demo-app -n default

# Stop port forwarding processes
pkill -f "kubectl port-forward"

# Stop minikube cluster
minikube stop

# Stop Vault container
docker stop vault-enterprise

# Optional: Remove minikube cluster entirely
minikube delete
```

## Additional Resources

- [Argo CD Vault Plugin Documentation](https://argocd-vault-plugin.readthedocs.io/)
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)

---

This demonstration provides a foundation for implementing secure GitOps workflows with centralized secret management in enterprise environments.