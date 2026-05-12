# vault

HashiCorp Vault, standalone mode, auto-unseal via Azure Key Vault, storage on garage S3.

## Post-init checklist

Run **once per Vault initialization** (state persists in the storage backend forever afterward):

### Enable the audit device

The chart deploys a `vault-audit` sidecar that tails `/vault/audit/audit.log` to stdout for Alloy/Loki collection. The audit device itself must be enabled via the API after the pod is up:

```powershell
$env:VAULT_ADDR = "https://hcvault.mattgerega.net"
vault login                # or token from initialization
vault audit enable file file_path=/vault/audit/audit.log log_raw=false
```

Verify:

```powershell
vault audit list
kubectl logs -n <ns> vault-0 -c vault-audit --tail=20
```

Query in Grafana / Loki:

```
{container="vault-audit"}
{container="vault-audit", audit_operation="delete"}
```

This step does **not** need to be re-run on chart upgrades — only after a full Vault re-init (e.g., storage wipe).
