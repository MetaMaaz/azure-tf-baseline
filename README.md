# azure-tf-baseline

A deliberately weak Azure baseline in Terraform (storage account, NSG, Key Vault), scanned with Checkov, fixed in order of risk, and gated in GitHub Actions so it can't regress.

## Result

| | Passed | Failed | Skipped |
|---|---|---|---|
| Weak baseline (first commit) | 8 | 16 | 0 |
| Hardened | 19 | 0 | 5 |

The first push of the weak version failed the `iac-scan` workflow. The hardened version passes.

## What was fixed

| Resource | Weak | Fixed | Checkov |
|---|---|---|---|
| NSG | RDP 3389 open to `*` | Rule removed. Admin access via Bastion or JIT | CKV_AZURE_9 |
| Storage | Anonymous blob access allowed | `allow_nested_items_to_be_public = false` | CKV_AZURE_190, CKV2_AZURE_47 |
| Storage | Reachable from any network | `public_network_access_enabled = false` | CKV_AZURE_59 |
| Storage | Account keys usable | `shared_access_key_enabled = false`, Entra auth only | CKV2_AZURE_40 |
| Storage | No recovery | Blob and container soft delete (7 days), versioning | CKV2_AZURE_38 |
| Storage | SAS tokens never expire | SAS expiry policy, 1 day | CKV2_AZURE_41 |
| Key Vault | Can be purged | Purge protection on | CKV_AZURE_110, CKV_AZURE_42 |
| Key Vault | Public, no firewall | Public access off, `network_acls` default Deny | CKV_AZURE_189, CKV_AZURE_109 |
| Key Vault | Access policies | Azure RBAC authorisation | (not a Checkov check) |

## Accepted, with reasons

Each skip sits inside its resource in `main.tf`, so the reason is reviewed with the code.

| Check | Why accepted |
|---|---|
| CKV_AZURE_206 geo-replication | Lab data. ZRS covers a zone outage; geo copies roughly double the cost |
| CKV_AZURE_33 queue logging | No queues in the account |
| CKV2_AZURE_33, CKV2_AZURE_32 private endpoints | Needs a VNet, out of scope. Public network access is disabled instead |
| CKV2_AZURE_1 customer-managed keys | Microsoft-managed keys are acceptable for lab data |

## Run it

```bash
cp terraform.tfvars.example terraform.tfvars   # fill in subscription_id and suffix
terraform init
terraform plan
checkov -d .
```

## Notes

- Shared keys are off, so the provider uses Entra auth (`storage_use_azuread = true`). Public network access is off, so `data_plane_available = false` keeps Terraform on the management plane.
- State is local and gitignored. In a team it would go in a remote backend (storage account, Entra auth, RBAC), because state can hold secrets.
- At runtime, Azure Policy enforces the same rules (audit first, then deny). Checkov catches it before deployment, Policy catches anything created outside Terraform.
