# Part 3 — The same stack on DigitalOcean

The advanced segment: prove that Terraform is multi-cloud but a Terraform config
is not. Full analysis in [`../docs/aws-vs-digitalocean.md`](../docs/aws-vs-digitalocean.md).

## Run it

```bash
export DIGITALOCEAN_TOKEN=dop_v1_...
cp terraform.tfvars.example terraform.tfvars   # set ssh_public_key, pin the commit
terraform init
terraform plan
terraform apply

terraform output studio_url
terraform output -raw dashboard_credentials
terraform output -raw boot_progress    # ready-made ssh tail command
```

Boot takes ~6 minutes, same as AWS — the image pull dominates on both.

## Live beats

**Diff the two directories on screen.** 17 infrastructure resources vs. 8. The
audience expects "same config, different provider" and gets two different
programs that happen to produce the same running service.

**Then curl the metadata endpoint from the droplet:**

```bash
curl http://169.254.169.254/metadata/v1/user-data | grep JWT_SECRET
```

Every credential, in plaintext, readable by any process on the box. Not a bug in
this config — a capability DigitalOcean doesn't have. The AWS build kept secrets
out of the launch config because IAM gave the instance an identity to
authenticate with; there's nothing here to port that to.

That's the whole lesson in one command.

## Files

| File | Note |
|---|---|
| `network.tf` | One VPC replaces five AWS resources — plus the deny-all-outbound gotcha |
| `droplet.tf` | Reserved IP allocated before the droplet, so URLs are right on first boot |
| `secrets.tf` | Mostly a comment explaining what can't be done here |
| `storage.tf` | Volume resolved by *name*; AWS resolved by ID |
| `user-data.sh` | Same shape as AWS, minus the Secrets Manager fetch |
