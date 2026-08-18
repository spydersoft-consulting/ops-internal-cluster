# Vault Auto-Unseal Implementation Guide

This guide covers the complete deployment of Azure Key Vault auto-unseal for HashiCorp Vault running in Kubernetes.

## Summary of Changes

### Terraform Changes

- **azuread/application-vault-autounseal.tf**: New service principal for auto-unseal
- **geregalab/key-vault-geregalab.tf**: Added RSA key for vault unsealing
- **geregalab/key-vault-geregalab-vault-autounseal.tf**: Access policy for service principal
- **geregalab/variables.tf**: Added `vault_autounseal_client_id` variable
- **geregalab/config/gerega.tfvars**: Added placeholder for client ID

### Kubernetes Changes

- **external/tools/vault/templates/vault-autounseal-secret-es.yaml**: External Secret to retrieve credentials
- **external/tools/vault/values.yaml**:
  - Added `updateStrategyType: "RollingUpdate"` for automatic pod updates
  - Added `seal "azurekeyvault"` configuration block
  - Added environment variable references for credentials

## Prerequisites

✅ Azure subscription with existing Key Vault (`geregalab`)
✅ Vault instance running in Kubernetes (namespace: `tools`)
✅ External Secrets Operator configured with Vault backend
✅ Current Vault unsealed and accessible

## Deployment Order

### Phase 1: Azure Infrastructure (Terraform)

#### Step 1: Apply Azure AD Configuration

```powershell
cd d:\ops\ops-automation\terraform\azuread

# Review changes
terraform plan

# Apply to create service principal
terraform apply

# Capture the output
$clientId = terraform output -raw vault_autounseal_client_id
Write-Host "Client ID: $clientId"
```

**What this creates:**

- Azure AD Application: "Vault Auto-Unseal (K8s)"
- Service Principal with 365-day credential rotation
- Vault secret at `secrets-k8/vault/autounseal` with all credentials

#### Step 2: Update GereLab Configuration

```powershell
# Update the tfvars file with the actual client ID
cd ..\geregalab
code .\config\gerega.tfvars

# Replace this line:
# vault_autounseal_client_id = "PLACEHOLDER_UPDATE_AFTER_AZUREAD_APPLY"
# With the actual client ID from Step 1
```

#### Step 3: Apply GereLab Infrastructure

```powershell
# Still in geregalab directory

# Review changes
terraform plan

# Apply to create key and access policy
terraform apply
```

**What this creates:**

- RSA-2048 key named `vault-auto-unseal` in Key Vault `geregalab`
- Access policy granting the service principal: Get, WrapKey, UnwrapKey permissions

**Verification:**

```powershell
# Verify the key exists
az keyvault key show --vault-name geregalab --name vault-auto-unseal

# Verify the service principal has access
az keyvault key list --vault-name geregalab
```

### Phase 2: Kubernetes Configuration

#### Step 4: Verify Vault Secret (Critical!)

```powershell
# This secret was created by azuread terraform
# Verify it exists in your current Vault instance

cd d:\ops\ops-internal-cluster

# Login to Vault if needed
export VAULT_ADDR=https://hcvault.mattgerega.net
vault login

# Verify the secret exists
vault kv get secrets-k8/vault/autounseal
```

**Expected output:**

```
====== Data ======
Key              Value
---              -----
client_id        <uuid>
client_secret    <secret>
key_name         vault-auto-unseal
tenant_id        70965cdd-c60c-4109-9fcf-709b2f23bd0c
vault_name       geregalab
```

#### Step 5: Commit and Push Kubernetes Manifests

```powershell
cd d:\ops\ops-internal-cluster

# Review the changes
git status
git diff

# Files to be committed:
# - external/tools/vault/values.yaml
# - external/tools/vault/templates/vault-autounseal-secret-es.yaml

git add external/tools/vault/
git commit -m "feat(vault): Add Azure Key Vault auto-unseal configuration

- Add External Secret for auto-unseal credentials
- Configure seal stanza for Azure Key Vault
- Enable RollingUpdate strategy for automatic pod updates"

git push
```

#### Step 6: ArgoCD Sync (Manual - Do NOT Auto-Sync Yet!)

```powershell
# Option A: ArgoCD UI
# 1. Navigate to the vault application in ArgoCD
# 2. Click "Sync" (do NOT enable auto-sync yet)
# 3. Review the changes:
#    - ExternalSecret will be created
#    - StatefulSet will be updated (triggers pod recreation)

# Option B: ArgoCD CLI
argocd app sync vault --dry-run
argocd app sync vault
```

**What happens during sync:**

1. External Secret `vault-autounseal-secret-es` is created
2. External Secrets Operator fetches credentials from Vault
3. Secret `vault-autounseal-secret` is created in namespace `tools`
4. StatefulSet `vault` is updated with new configuration
5. Pod `vault-0` is **terminated and recreated** (because of RollingUpdate)
6. New pod starts with **BOTH** seals configured (Shamir + Azure Key Vault)
7. **CRITICAL**: Pod will be SEALED and waiting for migration!

### Phase 3: Seal Migration (CRITICAL STEP!)

#### Step 7: Monitor Pod Restart

```powershell
# Watch the pod restart
kubectl get pods -n tools -l app.kubernetes.io/name=vault -w

# Expected sequence:
# vault-0   1/1   Running       -> Terminating
# vault-0   0/1   Terminating   -> Pending
# vault-0   0/1   Pending       -> ContainerCreating
# vault-0   0/1   Running       -> Running (but NOT ready - vault is sealed!)
```

**IMPORTANT**: The pod will start but the readiness probe will fail because Vault is SEALED!

#### Step 8: Perform Seal Migration (ONE-TIME PROCESS)

⚠️ **You MUST have your original Shamir unseal keys for this step!**

**Critical**: All unseal commands **MUST** use the `-migrate` flag!

```powershell
# Check vault status - it will be sealed
kubectl exec -n tools vault-0 -- vault status

# Expected output:
# Sealed: true
# Seal Type: shamir
# Total Shares: 5 (or whatever you configured)
# Threshold: 3

# Perform the migration by unsealing with the OLD Shamir keys using -migrate flag
# You need to provide the threshold number of keys (e.g., 3 of 5)
# ALL unseal commands MUST specify the -migrate flag

kubectl exec -n tools vault-0 -- vault operator unseal -migrate
# Enter KEY_1 when prompted
# Output: Sealed: true, Unseal Progress: 1/3

kubectl exec -n tools vault-0 -- vault operator unseal -migrate
# Enter KEY_2 when prompted
# Output: Sealed: true, Unseal Progress: 2/3

kubectl exec -n tools vault-0 -- vault operator unseal -migrate
# Enter KEY_3 when prompted
# Output: Sealed: false, Seal Type: azurekeyvault
# 🎉 MIGRATION COMPLETE!
```

**Alternative (non-interactive) approach:**
```powershell
# If you want to avoid interactive prompts
kubectl exec -n tools vault-0 -- vault operator unseal -migrate <KEY_1>
kubectl exec -n tools vault-0 -- vault operator unseal -migrate <KEY_2>
kubectl exec -n tools vault-0 -- vault operator unseal -migrate <KEY_3>
```

**What happened during migration:**
1. Vault detected the new `azurekeyvault` seal in the config
2. The `-migrate` flag instructed Vault to perform seal migration
3. You provided the old Shamir unseal keys to prove authorization
4. Vault migrated the unseal keys → recovery keys for the new seal
5. Vault encrypted the root key using Azure Key Vault
6. Vault auto-unsealed using Azure Key Vault
7. Future restarts will auto-unseal - NO MORE KEYS NEEDED!

#### Step 9: Verify Auto-Unseal Is Active

```powershell
# Check vault status
kubectl exec -n tools vault-0 -- vault status

# Expected output:
# Sealed: false
# Seal Type: azurekeyvault  ← Changed from 'shamir'!
# Recovery Seal Type: shamir  ← Old keys now for recovery only

# The pod should now be ready
kubectl get pod -n tools vault-0

# Check logs for successful migration
kubectl logs -n tools vault-0 | Select-String -Pattern "seal|migration|azure"
```

**Success indicators:**
- ✅ Pod is in `Running` state (1/1 Ready)
- ✅ `Sealed: false` 
- ✅ `Seal Type: azurekeyvault` (not `shamir`)
- ✅ `Recovery Seal Type: shamir` (old keys now for recovery)
- ✅ Vault UI is accessible at https://hcvault.mattgerega.net
- ✅ Can authenticate and access secrets

### Phase 4: Testing

#### Step 10: Test Manual Seal/Unseal (IMPORTANT - Validates Auto-Unseal)

```powershell
# Seal the vault manually
kubectl exec -n tools vault-0 -- vault operator seal

# Check if it auto-unseals
Start-Sleep -Seconds 5
kubectl exec -n tools vault-0 -- vault status

# Should show: Sealed: false (auto-unsealed!)
```

#### Step 11: Test Pod Deletion (Simulated Upgrade)

This is the REAL test - does it auto-unseal on restart?

```powershell
# Delete the pod to simulate an upgrade
kubectl delete pod -n tools vault-0

# Watch it recreate and auto-unseal
kubectl get pod -n tools vault-0 -w

# Expected: Pod goes to Running (1/1) automatically!
# No unseal keys needed!

# Verify it's unsealed
kubectl exec -n tools vault-0 -- vault status

# Should show:
# Sealed: false (auto-unsealed!)
# Seal Type: azurekeyvault
```

✅ **SUCCESS!** If the pod is unsealed without any manual intervention, auto-unseal is working!

### Phase 5: Post-Migration Considerations

#### Understanding Recovery Keys

#### Remove Old Shamir Unseal Keys (After Successful Migration)

The old unseal keys from Shamir seal are now obsolete. You can:

1. **Document them** and store securely offline (recommended for disaster recovery)
2. **Revoke operator access** if you distributed keys to multiple operators

**Note:** Keep them temporarily in case you need to roll back!

## Rollback Plan

If auto-unseal fails, you can roll back:

### Rollback Step 1: Revert Helm Values

```powershell
cd d:\ops\ops-internal-cluster

# Revert the values.yaml changes
git revert HEAD
git push
```

### Rollback Step 2: Sync ArgoCD

```powershell
argocd app sync vault
```

### Rollback Step 3: Manual Unseal

```powershell
# If the pod is sealed, unseal it manually with original keys
kubectl exec -n tools vault-0 -- vault operator unseal <key1>
kubectl exec -n tools vault-0 -- vault operator unseal <key2>
kubectl exec -n tools vault-0 -- vault operator unseal <key3>
```

## Troubleshooting

### Issue: External Secret Not Created

```powershell
# Check External Secrets Operator logs
kubectl logs -n cluster-tools -l app.kubernetes.io/name=external-secrets

# Check the ExternalSecret status
kubectl get externalsecret -n tools vault-autounseal-secret-es -o yaml
kubectl describe externalsecret -n tools vault-autounseal-secret-es
```

### Issue: Pod Fails to Start

```powershell
# Check pod events
kubectl describe pod -n tools vault-0

# Check vault logs
kubectl logs -n tools vault-0

# Common errors:
# - "permission denied": Service principal doesn't have Key Vault access
# - "key not found": Key name mismatch
# - "vault not found": Vault name incorrect
```

### Issue: Auto-Unseal Not Working

```powershell
# Verify environment variables are set
kubectl exec -n tools vault-0 -- env | Select-String -Pattern "AZURE"

# Verify the secret exists and has data
kubectl get secret -n tools vault-autounseal-secret -o yaml

# Check Azure Key Vault access
az keyvault key show --vault-name geregalab --name vault-auto-unseal
```

### Issue: Service Principal Permission Denied

```powershell
# Re-apply the access policy
cd d:\ops\ops-automation\terraform\geregalab
terraform apply -target=azurerm_key_vault_access_policy.vault_autounseal
```

## Benefits After Implementation

✅ **Automatic pod updates**: No more manual pod deletion for upgrades
✅ **Auto-unseal**: No manual intervention after pod restarts
✅ **Rolling upgrades**: Pod automatically recreates when chart/image updates
✅ **Better security**: Unseal keys managed by Azure Key Vault
✅ **Centralized management**: Service principal credentials rotated via Terraform

## Cost Impact

- **Azure Key Vault operations**: ~$0.03 per 10,000 operations
- **Expected monthly cost**: < $1 (minimal operations for unsealing)
- **No additional compute**: Same single-pod configuration

## Future Enhancements (Optional)

1. **Enable HA mode**: Migrate to Raft storage with 3 replicas
2. **Auto-snapshot**: Configure automated backups to S3/Azure Storage
3. **Monitoring**: Add alerts for seal status changes
4. **Performance replication**: Enterprise feature for multi-cluster

## References

- [Vault Auto-Unseal Documentation](https://developer.hashicorp.com/vault/docs/concepts/seal#auto-unseal)
- [Azure Key Vault Seal](https://developer.hashicorp.com/vault/docs/configuration/seal/azurekeyvault)
- [Vault Helm Chart](https://github.com/hashicorp/vault-helm)
