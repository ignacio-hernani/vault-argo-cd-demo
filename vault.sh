## Deploy Vault Enterprise

# Set up Vault environment variables
export VAULT_PORT=8200
export VAULT_ADDR="http://127.0.0.1:${VAULT_PORT}"
export VAULT_TOKEN="root"

# Read your license file
VAULT_LICENSE=$(cat "vault.hclic")
CONTAINER_NAME=vault-enterprise

# Check Docker installation
if [[ $(docker version) ]]; then
    echo "Docker version found: $(docker version)"
else
    brew install --cask docker
fi

# Pull and run Vault Enterprise
docker pull hashicorp/vault-enterprise
docker run -d --rm --name $CONTAINER_NAME --cap-add=IPC_LOCK \
  -e "VAULT_DEV_ROOT_TOKEN_ID=${VAULT_TOKEN}" \
  -e "VAULT_DEV_LISTEN_ADDRESS=:${VAULT_PORT}" \
  -e "VAULT_LICENSE=${VAULT_LICENSE}" \
  -e "VAULT_LOG_LEVEL=trace" \
  -p $VAULT_PORT:$VAULT_PORT hashicorp/vault-enterprise:latest

# Wait for Vault to start
sleep 5

# Verify Vault is running
vault status

# What's happening:
#   We're running Vault in a Docker container (not in Kubernetes yet)
#   Dev mode means Vault starts unsealed with a root token (not for production!)
#   Port 8200 is exposed so we can access Vault from our Mac