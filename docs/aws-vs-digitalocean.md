# Same stack, two providers — what actually ports

The segment this supports: **Terraform is multi-cloud; a Terraform config is not.**

There is no `terraform apply --provider=digitalocean`. `aws_instance` and
`digitalocean_droplet` are different resource types with different arguments.
Every resource gets rewritten. What you reuse is the workflow, not the code.

Show `02-terraform/` and `03-digitalocean/` side by side and count:

| | AWS | DigitalOcean |
|---|---|---|
| Infrastructure resources | **17** | **8** |
| `random_id` generators | 5 | 5 |
| Lines of HCL | ~330 | ~200 |

## The mapping

| Concept | AWS | DigitalOcean |
|---|---|---|
| The machine | `aws_instance` | `digitalocean_droplet` |
| Stable address | `aws_eip` + association | `digitalocean_reserved_ip` + assignment |
| Persistent disk | `aws_ebs_volume` + attachment | `digitalocean_volume` + attachment |
| Firewall | `aws_security_group` | `digitalocean_firewall` |
| Private network | VPC + subnet + IGW + route table + association (**5**) | `digitalocean_vpc` (**1**) |
| Machine identity | IAM role + policy + attachment + profile (**4**) | **nothing — no equivalent** |
| Secret storage | Secrets Manager secret + version (**2**) | **nothing — no equivalent** |
| Shell access | SSM Session Manager, no open port | SSH, `:22` open, key required |

## What ported cleanly

- **The reserved-IP-before-boot trick.** Both providers let you allocate an
  address as a standalone resource, so Terraform's dependency graph can feed it
  into the boot script. The public URLs are correct on first boot on both. The
  best beat in the AWS build survives the port intact.
- **The dependency graph itself.** You never ordered anything by hand on either.
- **Resolving the data volume by a stable device path.** AWS by volume ID, DO by
  volume name — same idea, different string.
- **JWT signing at boot.** Terraform has no HMAC function on *any* provider, so
  this was always going to happen in `user-data.sh`.
- **`plan`, `apply`, `destroy`, and state.** Genuinely identical. This is the
  real multi-cloud benefit, and it is a workflow benefit, not a code one.

## What did not port — and this is the segment

### 1. The droplet has no identity

On AWS, four IAM resources gave the instance an identity. It authenticated to
Secrets Manager *by existing*. Nothing sensitive appeared in the launch config.

DigitalOcean droplets have no equivalent, and DO has no secret manager for
droplets. So credentials get interpolated directly into `user_data` — where they
remain readable for the droplet's entire life at:

```
http://169.254.169.254/metadata/v1/user-data
```

by **any process on the box**, not just root. Curl it live. It is the most
concrete thing you will show all session.

Doing it properly on DO means an external store (Vault, Doppler, Infisical) —
which needs its own bootstrap token, which lands in `user_data` anyway. You
shrink the blast radius; you don't remove it.

> **The line to land:** the AWS config didn't just use different resource names.
> It depended on a *capability* that doesn't exist over here. Portability
> stops at the edge of what each cloud can actually do.

### 2. You have to open SSH

The AWS build had no port 22 and no key pair — Session Manager brokered the
shell through the instance role. DO has no equivalent, so `03-digitalocean/`
gains two variables (`ssh_public_key`, `ssh_allowed_cidr`) that have no AWS
counterpart, and the firewall opens a port the AWS build never had.

Fewer resources did not mean a smaller attack surface. It meant a larger one.

### 3. Outbound is deny-all

A gotcha that will eat someone's afternoon: once a `digitalocean_firewall`
exists, **outbound traffic is denied by default**. AWS security groups allow all
egress until you restrict it. Omit the outbound rules and the droplet can't
reach apt or Docker Hub, and cloud-init hangs with no useful error.

Worth showing deliberately if you have time — it's a great "read the provider
docs, not your assumptions" moment.

### 4. Less network to manage, less network control

One `digitalocean_vpc` instead of five AWS resources looks like a clean win. But
DO gives you no subnets, no gateways, no route tables — so the private-subnet-
behind-a-NAT design that AWS makes possible simply isn't available. Simplicity
and control are the same axis.

## The honest summary

| What you reuse | What you rewrite |
|---|---|
| The language | Every resource block |
| `plan` / `apply` / `destroy` | Every provider-specific argument |
| State and locking model | Every capability assumption |
| The dependency graph | The security architecture |
| Your own mental model | |

That's still worth a lot — moving between clouds with one tool and one workflow
beats learning CloudFormation and then learning `doctl`. Just not the "write
once, deploy anywhere" people expect when they first hear "multi-cloud."
