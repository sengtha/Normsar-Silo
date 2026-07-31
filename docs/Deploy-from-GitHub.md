# 🚀 Deploy a Silo from GitHub

Your Silo is a **sovereign environment** — you run it on infrastructure you
control, and Normsar never touches it. These paths all install the same
self-contained Docker stack (see [`docker/`](../docker/README.md)) straight
from this repository, on **your** server, with **your** credentials.

## What you need first

- A Linux VM you control (Ubuntu/Debian recommended), **≥ 4 GB RAM**.
- **Ports 80 and 443** open to the internet.
- A **domain name** whose DNS `A` record points at the VM (Caddy uses it to get
  an automatic HTTPS certificate — required for Web Push, the PWA, and the Hub
  relay).

---

## Option 1 — One command on your server (simplest)

SSH into your VM and run:

```bash
curl -fsSL https://raw.githubusercontent.com/sengtha/Normsar-Silo/main/install.sh \
  | sudo bash -s -- --domain silo.example.com --email you@example.com
```

That installs Docker, clones this repo to `/opt/normsar-silo`, generates all
secrets, and brings the stack up behind automatic HTTPS. Re-run the same
command any time to **update** in place.

### Auto-register (recommended)

Add a **claim token** and the Silo registers itself with the Hub during install
— no manual step, and a 1-month free trial starts automatically. Get the token
from the Silo Manager (<https://normsar.io/silo-manager> → **“Deploy a Silo”**),
which hands you the full command:

```bash
curl -fsSL https://raw.githubusercontent.com/sengtha/Normsar-Silo/main/install.sh \
  | sudo NORMSAR_CLAIM_TOKEN=<your-token> bash -s -- \
      --domain silo.example.com --email you@example.com
```

The installer writes the returned `HUB_SILO_API_KEY` (for push) and `HUB_URL`
into `.env` for you. The token is single-use and expires in 7 days.

Optional feature keys can also be passed as environment variables and are written
into `.env` automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/sengtha/Normsar-Silo/main/install.sh \
  | sudo GEMINI_API_KEY=... HUB_URL=https://hub.normsar.io HUB_SILO_API_KEY=... \
    bash -s -- --domain silo.example.com --email you@example.com
```

---

## Option 2 — Deploy from your own GitHub fork (Actions)

Fully sovereign: it runs from **your fork**, with **your secrets**, to **your**
server. Normsar is not involved.

1. **Fork** this repository (keep the fork public so the installer is fetchable).
2. In your fork: **Settings → Secrets and variables → Actions** → add:
   - `SSH_HOST` — your server's IP/hostname
   - `SSH_USER` — an SSH user with `sudo` (or `root`)
   - `SSH_PRIVATE_KEY` — a private key authorized on that server
   - *(optional)* `GEMINI_API_KEY`, `HUB_URL`, `HUB_SILO_API_KEY`
3. **Actions → Deploy Silo → Run workflow**, enter your **domain** and **email**.
   To auto-register, paste a claim token (Silo Manager → **“Deploy a Silo”**)
   into the **claim_token** input.

The workflow SSHes into your server and runs `install.sh` from your fork. Run
it again whenever you want to redeploy/update.

---

## Option 3 — Compose-native hosts (one-click-ish)

Platforms that deploy a `docker-compose` project directly from a Git repo. You
connect **your own** account and point it at this repo (or your fork):

- **Coolify** (self-hostable or their cloud) — add a *Docker Compose* resource
  from this repo; it builds, runs, and renews TLS. Great sovereign fit.
- **Elestio** — see [`host/elestio-setup.md`](../host/elestio-setup.md).
- **Zeabur / Sealos** — import the repo as a template.

> Not supported: app-only PaaS such as Vercel / Netlify / DigitalOcean App
> Platform — the Silo is a full stateful stack (Postgres, realtime, storage),
> so it needs a VM or a compose-capable host.

---

## After it's up

1. Watch it start: `cd /opt/normsar-silo/docker && docker compose logs -f`
2. **If you deployed with a claim token, you're done** — the Silo is already
   registered (it appears as *Trialing* in the Silo Manager) and its push key is
   set. Otherwise register it manually in the **Silo Manager**
   (<https://normsar.io/silo-manager> → **Register existing**) using:
   - **Project URL:** `https://silo.example.com`
   - **Anon Key:** the `ANON_KEY` value in `/opt/normsar-silo/docker/.env`
3. Push notifications work out of the box on an auto-registered Silo. On a
   manually registered one, reveal your `HUB_SILO_API_KEY` in the Silo Manager
   (your Silo → *Reveal push key*) and set it plus `HUB_URL` (see
   [Push-Notifications setup](https://github.com/sengtha/Normsar/blob/main/docs/Push-Notifications.md)).

## Updating later

```bash
# Option 1 host: just re-run the installer
curl -fsSL https://raw.githubusercontent.com/sengtha/Normsar-Silo/main/install.sh \
  | sudo bash -s -- --domain silo.example.com --email you@example.com

# or manually
cd /opt/normsar-silo && git pull && cd docker && docker compose pull && docker compose up -d
```

Existing schema upgrades ship as idempotent `Fix_*.sql` scripts in
`supabase/setup/schema/` — run any new ones in the Studio SQL editor.
