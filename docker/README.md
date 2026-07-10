# 🐳 Normsar Silo — Self-Hosted Docker Distribution

Run a complete, sovereign Normsar Silo on **any VM** using the open-source
Supabase stack — no hosted Supabase account required. One `git clone`, one
script, one `docker compose up`.

This bundle packages:

- The full open-source **Supabase stack** (Postgres + pgvector, Auth, REST,
  Realtime, Storage, Kong gateway, Edge Functions runtime, Studio).
- The **Silo database schema** (auto-applied on first boot).
- All **Silo edge functions** (`send-message`, `normsar-ai`, `feed-ai`,
  `authenticate-hub-user`, …).
- **Caddy** for automatic HTTPS (Let's Encrypt) — required for Web Push, the
  PWA, and the Hub push relay.
- A `bootstrap.sh` that generates every secret for you.

## Requirements

- A Linux VM with **Docker** + **Docker Compose v2** and **≥ 4 GB RAM**.
- **Ports 80 and 443** open to the internet.
- A **domain name** whose A record points at the VM (needed for a real TLS
  certificate). You can trial locally with `localhost` first.

## Install (5 steps)

```bash
git clone https://github.com/sengtha/Normsar-Silo.git
cd Normsar-Silo/docker

# 1. Generate all secrets + wire your domain into .env
./bootstrap.sh --domain silo.example.com --email you@example.com
#    (local trial:  ./bootstrap.sh --domain localhost)

# 2. (optional) open .env and add feature keys — see "Optional features" below
nano .env

# 3. Bring the stack up
docker compose up -d

# 4. Watch it come healthy (Ctrl-C to stop watching)
docker compose ps
docker compose logs -f db          # first boot applies the Silo schema

# 5. Point https://silo.example.com at this VM — Caddy fetches a cert on first hit.
```

Your Silo API is now at `https://silo.example.com`. The Studio admin UI is
reachable through the same domain (login: `supabase` / the dashboard password
printed by `bootstrap.sh`).

## Register your Silo with the Hub

The values a Silo owner needs for the [Silo Manager](https://normsar.io/silo-manager):

- **Project URL:** `https://silo.example.com`
- **Anon Key:** the `ANON_KEY` value in your `.env`

## Optional features

All are wired and off-by-default until you set their keys in `.env`, then
`docker compose up -d` to apply:

| Feature | Keys to set |
| :--- | :--- |
| **AI** (assistant + RAG search) | `GEMINI_API_KEY` |
| **Push notifications** (via Hub) | `HUB_URL`, `HUB_SILO_API_KEY` |
| **Cloudflare Durable Objects** | `CF_DO_URL`, `CF_DO_SECRET_KEY` |
| **Lit Protocol E2EE** | `LIT_API_KEY`, `LIT_PKP_PUBLIC_KEY` |

## How it fits together

```
Internet ──443──▶ Caddy (auto-TLS) ──▶ Kong gateway ─┬─▶ Auth (GoTrue)
                                                      ├─▶ REST (PostgREST)
                                                      ├─▶ Realtime (WebSockets)
                                                      ├─▶ Storage  ──▶ Postgres
                                                      └─▶ Edge Functions ──▶ Postgres
```

- The **Silo schema** is mounted into Postgres' init directory and applied
  once, on first boot, after Supabase's own baseline migrations.
- The **edge functions** are mounted straight from `../supabase/setup/functions`
  (single source of truth) behind a request router.
- `SILO_JWT_SECRET` is bound to the stack's `JWT_SECRET` so tokens the Silo
  mints validate against its own Auth/REST/Realtime.
- The upload bucket + storage policies are applied by a one-shot
  `storage-init` container once the Storage service is ready (its schema is
  created at runtime, after Postgres init).

## Common operations

```bash
docker compose logs -f <service>     # tail a service (auth, realtime, functions, …)
docker compose restart functions     # reload after editing a function or .env
docker compose down                  # stop (keeps data in named volumes)
docker compose down -v               # stop AND wipe all data (irreversible)
./bootstrap.sh --domain … --force    # rotate ALL secrets (regenerates .env)
```

## Upgrading

```bash
git pull
docker compose pull       # get newer pinned images
docker compose up -d
```

The Silo schema is applied only on a *fresh* database. To add new schema
features to an existing Silo, run the matching `Fix_*.sql` from
`../supabase/setup/schema/` in Studio's SQL editor (they're idempotent).

## Notes & limits

- **HTTPS is mandatory** for Web Push / PWA / the Hub relay. With
  `--domain localhost` you get a self-signed cert (browsers warn), fine for
  smoke-testing but not for real devices.
- Kong's raw ports are bound to `127.0.0.1` by default — only Caddy is public.
- This bundle vendors Supabase's official self-hosting compose (Apache-2.0)
  and pins its image versions; update them with `git pull`.
