# Run of show — ~50 min

Times are from rehearsal targets, not guesses. The two long waits are marked;
both have prepared filler.

## Part 1 — Manual (25 min)

| # | Time | Beat | Notes |
|---|---|---|---|
| 1 | 0:00 | Frame it: "managed Supabase is $25/mo. What are you paying for?" | promises the payoff |
| 2 | 0:02 | Launch EC2 in console — t3.medium, 30GB, SG :8000 | say why micro fails |
| 3 | 0:05 | `aws ssm start-session` — no SSH key, no bastion | reliable surprise |
| 4 | 0:07 | `10-install-docker.sh` then `20-fetch-supabase.sh` | ~2 min |
| 5 | 0:09 | `00-preflight.sh` first; later `40-configure-env.sh`, `50-up.sh` | |
| 6 | 0:11 | **WAIT ~5 min: image pull** | ⚠️ architecture diagram, 13 containers |
| 7 | 0:16 | Studio loads. First payoff. | drop URL in chat |
| 8 | 0:18 | **Trap 1** — JWT mismatch, 401s | paste key into jwt.io |
| 9 | 0:21 | **Trap 2** — `localhost` URLs | have chat confirm it fails for them too |
| 10 | 0:23 | **Trap 3** — hand-edit, terminate, it's gone | → "what if the machine were code?" |

## Part 2 — Terraform (20 min)

| # | Time | Beat | Notes |
|---|---|---|---|
| 11 | 0:25 | Walk the SECURITY section of `main.tf` — no :22, no :5432 | least privilege, visible |
| 12 | 0:28 | Walk the SECRETS section — and admit state holds plaintext | credibility beat |
| 13 | 0:31 | `terraform plan` — read it aloud | this is the pitch |
| 14 | 0:34 | `terraform apply` | ~2 min for AWS resources |
| 15 | 0:36 | **WAIT ~6 min: cloud-init** | ⚠️ tail the boot log; explain EIP-known-before-boot |
| 16 | 0:42 | Studio up, correct URL **first try** | trap 2 now impossible |

## The close (5 min)

| # | Time | Beat |
|---|---|---|
| 17 | 0:44 | Terminate the Terraform instance |
| 18 | 0:45 | `terraform apply` — same IP, same URL, **same data** |
| 19 | 0:48 | `terraform destroy` on camera |

## Filler for the two waits

**Wait 1 (image pull, ~5 min)** — the 13 containers: Kong is the only front door;
GoTrue does auth; PostgREST turns tables into a REST API; Realtime tails the WAL;
Storage fronts S3-compatible objects; Studio is just a client of all of them.
Point out that managed Supabase runs this same stack, per tenant.

**Wait 2 (cloud-init, ~6 min)** — tail `/var/log/supabase-boot.log` on screen and
narrate. Good moment for the Terraform-has-no-HMAC detour and why the JWTs get
signed at boot instead.

## If it breaks live

| Symptom | Cause | Fix |
|---|---|---|
| Containers OOM-killed | undersized instance | you're on micro — `00-preflight.sh` would have caught it |
| Studio loads, all 401 | JWT mismatch | that's trap 1, arriving early — lean in |
| Studio loads, nothing responds | `SUPABASE_PUBLIC_URL` | that's trap 2 — lean in |
| `analytics` crash-looping | Logflare vars, version drift | you're not on the pinned SHA |
| cloud-init silent | check `/var/log/supabase-boot.log` | volume may not have attached |

Two of the five failure modes *are* scheduled content. If they show up early,
you're not recovering — you're ahead of schedule.
