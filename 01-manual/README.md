# Part 1 — Manual (the pain)

Goal: get self-hosted Supabase running on one EC2 box **by hand**, hitting three
real failures on the way. The failures are the content. Part 2 then deletes each
one with Terraform.

## Launch the instance (console, on camera)

| Setting | Value | Say this out loud |
|---|---|---|
| AMI | Ubuntu 24.04 LTS | |
| Type | **t3.medium** | "free tier cannot run this — that's what managed services sell you" |
| Storage | **30 GB gp3** | images alone are ~8 GB |
| Security group | inbound **8000** from anywhere | |
| IAM profile | role with `AmazonSSMManagedInstanceCore` | no SSH key, no bastion |

Then get a shell **without SSH** — this reliably surprises people:

```bash
aws ssm start-session --target i-XXXXXXXX
```

## Bring it up

Numbered steps, run one at a time. Running them separately is the point: the
audience sees each piece land, and a failure costs you one step instead of the
whole build.

```bash
sudo -i
cd /path/to/01-manual

./00-preflight.sh                            # RAM, disk, OS, egress
./10-install-docker.sh                       # engine + compose plugin
SUPABASE_COMMIT=<sha> ./20-fetch-supabase.sh # pinned clone, seeds .env

cd /opt/supabase/supabase/docker
/path/to/01-manual/40-configure-env.sh <EC2_PUBLIC_IP>
/path/to/01-manual/50-up.sh                  # pull, start, wait for Kong
```

Each step prints the next one, so you never have to remember the order on camera.

`50-up.sh` blocks until Kong actually answers, rather than returning the moment
`compose up` exits — so "READY" means ready, not "containers created". The pull
inside it is **4–5 minutes**: that's your architecture segment. Put the
13-container diagram up and walk through Kong, GoTrue, PostgREST, Realtime,
Storage, and Studio while it downloads.

For rehearsal only, `sudo ./run-all.sh <IP>` runs the whole chain unattended.
Don't use it live — the separation *is* the demo.

## The three traps

Run each deliberately, let the audience diagnose it, then fix it.

### Trap 1 — JWT mismatch (~2 min to debug live)

```bash
./40-configure-env.sh <IP> --break jwt
docker compose up -d
```

Studio loads perfectly. Every API call 401s. The reveal: `ANON_KEY` and
`SERVICE_ROLE_KEY` aren't random strings, they're **HS256 JWTs signed with
`JWT_SECRET`**. Rotate the secret without regenerating both keys and you get
exactly this. Paste the anon key into jwt.io on screen — the payload is readable,
the signature is what fails.

Fix: `./40-configure-env.sh <IP> && docker compose up -d`

### Trap 2 — `localhost` in the public URLs

```bash
./40-configure-env.sh <IP> --break localhost
docker compose up -d
```

Studio renders. Everything fails. The reveal: `SUPABASE_PUBLIC_URL` is consumed
by the **browser**, not the server — so `localhost` resolves to the *viewer's*
laptop. Best taught by having someone in chat open it and get the same failure.

### Trap 3 — the box is a pet

```bash
docker compose exec db psql -U postgres -c "create table hotfix(id int);"
```

Then **terminate the instance**. The table, the data, the `.env`, the keys — all
gone. Nothing you did was written down anywhere.

That's the handoff line into Part 2: *"what if the machine were code?"*

## Scripts here

| File | Purpose |
|---|---|
| `00-preflight.sh` | Fails fast on RAM, disk, OS, or no egress |
| `10-install-docker.sh` | Docker Engine + compose plugin; safe to re-run |
| `20-fetch-supabase.sh` | Sparse/blobless clone at a pinned commit, seeds `.env` |
| `30-generate-keys.sh` | JWT secret + matching anon/service keys; `--mismatch` for trap 1 |
| `40-configure-env.sh` | Patches `.env` by key; `--break jwt\|localhost` |
| `50-up.sh` | Pull, start, block until Kong answers |
| `run-all.sh` | Rehearsal only — the whole chain unattended |

Each script is self-contained and idempotent, so you can re-run any single step
without unwinding the ones before it.

`40-configure-env.sh` patches upstream's `.env` **by key** rather than shipping a
full file, because upstream's `.env.example` changes shape between releases. It
calls `30-generate-keys.sh` for you — run 30 directly only to inspect the keys.
