# Part 2 — Terraform (the relief)

Every resource here exists to delete a specific pain from Part 1. Say which one,
each time — that's what makes this land instead of being a syntax tour.

| Pain from Part 1 | Fixed by | File |
|---|---|---|
| IP changed on reboot, broke every URL | `aws_eip` — stable identity, known *before* boot | `instance.tf` |
| Secrets typed by hand into `.env` | Secrets Manager + instance role | `secrets.tf`, `iam.tf` |
| "did I leave 5432 open?" | SG as reviewable code, no :22, no :5432 | `security.tf` |
| DB died with the instance | separate encrypted EBS volume | `storage.tf` |
| 25 minutes of clicking | `user-data.sh`, ~6 min unattended | `user-data.sh` |

## Run it

```bash
cp terraform.tfvars.example terraform.tfvars   # set supabase_commit!
terraform init
terraform plan          # read this out loud — it's the whole pitch
terraform apply
terraform output studio_url
terraform output -raw dashboard_credentials
```

Watch the boot (cloud-init takes ~6 min, mostly image pull):

```bash
terraform output -raw boot_progress   # gives you a ready-made SSM command
```

## Things worth pausing on live

**The EIP is known before the instance exists.** That's why `SUPABASE_PUBLIC_URL`
is correct on the first boot — Terraform's dependency graph resolves the address
*before* rendering the boot script. Trap 2 from Part 1 becomes structurally
impossible. This is the single best "oh" moment in the whole build.

**Terraform has no HMAC function**, so the anon/service_role JWTs can't be signed
in HCL. They're derived at boot in `user-data.sh` from the secret. Nice side
effect: those keys never touch your laptop or your shell history.

**Secrets are in state, in plaintext.** Say this out loud. Terraform doesn't make
secrets vanish, it moves where they live — which is why the S3 backend sets
`encrypt = true`. Being honest about this buys more credibility than skipping it.

**`use_lockfile = true`** (see `versions.tf`) — since Terraform 1.10, S3 does its
own state locking and the old DynamoDB lock table is obsolete. Most tutorials
still tell people to create that table.

**Why Postgres stays in Docker instead of moving to RDS:** Supabase's Postgres
image ships extensions (pgsodium, pg_graphql, pgjwt, wrappers) that stock RDS
doesn't have. Moving to RDS breaks auth and the API. Worth saying — it's the kind
of constraint that separates a demo from a tutorial.

## The closing beat

```bash
# kill it the same way you killed the manual box
aws ec2 terminate-instances --instance-ids $(terraform output -raw instance_id)
terraform apply -auto-approve
```

Same IP. Same URL. **Same data**, because the volume outlived the instance.
The manual box needed 25 minutes of clicking; this one needed one command.

## Teardown — actually do this on camera

```bash
terraform destroy
```

Audiences remember who cleans up. Note `recovery_window_in_days = 0` on the
secret, so destroy really destroys rather than leaving a 30-day scheduled
deletion behind.
