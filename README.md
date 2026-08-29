# Content Lab — Self-hosted Supabase on AWS: by hand, then as code

A live-demo pair. Part 1 builds self-hosted Supabase on EC2 manually and hits
three real failures. Part 2 rebuilds it in Terraform, where each failure becomes
structurally impossible.

The Terraform half only lands emotionally if the audience just watched you
suffer. Don't skip the pain.

```
01-manual/       six numbered steps: preflight, docker, fetch, keys, env, up
02-terraform/    AWS -- VPC, EIP, Secrets Manager, EBS, SSM, cloud-init
03-digitalocean/ the same stack, rewritten for a second provider
docs/            run-of-show, and the AWS/DO comparison
```

Optional Part 3 makes a point worth its own segment: **Terraform is multi-cloud,
but a Terraform config is not.** 17 infrastructure resources on AWS, 8 on
DigitalOcean, and not one line shared. See
[`docs/aws-vs-digitalocean.md`](docs/aws-vs-digitalocean.md).

## Part 1 at a glance

```bash
./00-preflight.sh                            # RAM, disk, OS, egress
./10-install-docker.sh                       # engine + compose plugin
SUPABASE_COMMIT=<sha> ./20-fetch-supabase.sh # pinned clone, seeds .env
./40-configure-env.sh <PUBLIC_IP>            # calls 30- to mint the JWTs
./50-up.sh                                   # pull, start, wait for Kong
```

Each step is idempotent, prints the next one, and can be re-run without unwinding
the steps before it. `run-all.sh` chains them for rehearsal — not for live.

## Before you go live

- [ ] **Pin `supabase_commit`.** Upstream's `.env.example` changes shape between
      releases. Rehearse and present on the same SHA.
      `git ls-remote https://github.com/supabase/supabase.git HEAD`
- [ ] **Rehearse once end to end** (`run-all.sh`), mainly to time the image pull
      on the day's network.
- [ ] **Set a budget alert.** Good on camera anyway.
- [ ] **Pre-launch the Part 1 instance** if you're tight on time — the Docker
      install is two unglamorous minutes.

## Cost

| | |
|---|---|
| 2 × t3.medium | ~$0.083/hr combined |
| 50 GB gp3 | ~$0.005/hr |
| EIP (while attached) | free |
| Secrets Manager | $0.40/mo, prorated |

A 2-hour session with rehearsal is well under **$1**. It bills whether or not
you're watching, so run the teardown live at the end.

## Part 3 at a glance

```bash
export DIGITALOCEAN_TOKEN=dop_v1_...
cd 03-digitalocean && terraform apply
# then, on the droplet:
curl http://169.254.169.254/metadata/v1/user-data | grep JWT_SECRET
```

That last command is the segment: every credential in plaintext, readable by any
process on the box. Not a bug in the config — DigitalOcean droplets have no
machine identity, so there is no Secrets Manager equivalent to port to.

## Verified

The AWS build validates and plans clean (22 resources, no cycles), the AMI lookup
resolves to current Ubuntu 24.04, `user-data.sh` renders to syntactically valid
bash, and the JWT generator's signatures verify against an independent HMAC
implementation — with `--mismatch` confirmed to produce invalid ones. Every shell
script parses clean.

The DigitalOcean build validates, formats clean, and its dependency graph is an
acyclic DAG with the reserved IP correctly ordered before the droplet. It has not
been planned against a live account — that needs a `DIGITALOCEAN_TOKEN`, which
isn't set here.

Neither build has been applied against a live account, and the Ubuntu-only steps
(00, 10, 20, 50) have not run on a real instance. Do a rehearsal run.
