# Home Server Plan (Single Node, Portable)

## Goals

- Run multiple services reliably on a single machine
- Keep setup **reproducible**, **portable**, and **low-maintenance**
- Avoid multi-node orchestration (no Swarm, no Kubernetes)
- Treat server configuration as code
- Make hardware swaps boring and fast
- **Test on any laptop, deploy to any target** – same repo, same commands

---

## Core Principles

1. **Everything is code**
   - All Docker and service configuration lives in Git
   - No manual snowflake changes on the server

2. **Single-node simplicity**
   - One Docker engine
   - Docker Compose for orchestration
   - No clustering, no leader election, no distributed state

3. **Stateless containers, stateful data**
   - Containers can be destroyed and recreated at any time
   - Persistent data lives in `./data/` (local storage, gitignored)

4. **Hardware-agnostic**
   - Same repo works on:
     - MacBook Pro (for testing)
     - Raspberry Pi (ARM64)
     - Mac mini, Linux server, VM
   - Multi-arch Docker images handle CPU differences
   - No code changes between dev and prod

---

## Technology Choices

### Container Runtime
- Docker Engine
- Docker Compose v2 (`docker compose`)

Reason:
- Widely supported
- Stable
- Minimal cognitive overhead
- Portable across OS and hardware

---

## Configuration Management

- Git repository as the **source of truth**
- No secrets committed
- `.env` files for environment-specific values

```
.env            # not committed (secrets + machine-specific config)
.env.example    # committed template
```

### Required Environment Variables

```bash
# User/Group IDs (use `id -u` and `id -g` to get your values)
PUID=1000
PGID=1000

# Timezone
TZ=America/Los_Angeles

# Data paths (relative to repo, works on any machine)
DATA_ROOT=./data
```

### Platform Portability

The same repository works on:
- **macOS** (MacBook Pro, Mac mini) – for development and testing
- **Linux ARM64** (Raspberry Pi) – for production
- **Linux x86_64** (VMs, servers) – alternative production

How this works:
- Docker abstracts the OS differences
- Multi-arch images run on both ARM64 and x86_64
- Paths are relative to the repo, not absolute system paths
- `.env` handles any machine-specific overrides

---

## Service Management

- Each service defined in `docker-compose.yml`
- Optional grouping via multiple compose files if needed later

### Port Conflicts on Dev Machine

If standard ports conflict with other software on your dev machine, override them in `.env`:

```bash
# .env (not committed)
RESILIO_WEB_PORT=8889
RESILIO_SYNC_PORT=55556
```

`docker-compose.yml` uses these with defaults: `${RESILIO_WEB_PORT:-8888}`. On production, omit these variables to use standard ports.

---

## Repository Structure

```
homehq/
├── docker-compose.yml
├── .env.example
├── .env                  # not committed, machine-specific
├── .gitignore
├── plan.md
├── nginx/                # reverse proxy (version-controlled)
│   ├── nginx.conf
│   └── html/
│       └── index.html    # static dashboard
├── data/                 # all persistent data lives here (gitignored)
│   └── resilio-sync/
│       ├── config/       # service configuration
│       └── sync/         # synced files
├── scripts/
│   ├── backup.sh
│   ├── restore.sh
│   └── update.sh
└── docs/
    └── recovery.md
```

**Key point:** The `data/` directory is gitignored. It stores all persistent state and is the only thing that needs to be backed up.

---

## Docker Compose Guidelines

### General Rules

- Prefer official images or LinuxServer.io images (multi-arch)
- **Require multi-arch images** (must work on both ARM64 and x86_64)
- Avoid `latest` tags where possible
- Explicit container names
- Use `${DATA_ROOT}/<service>/` for all volume mounts

---

### Resource Safety (Optional but Recommended)

- Set memory limits for heavier services

```yaml
services:
  app:
    mem_limit: 512m
```

- Prevent one misbehaving container from killing the host

---

### Networking

- Use a single default Docker network unless isolation is required
- Expose as few ports as possible
- Prefer reverse proxy for HTTP services

---

## Services

### Resilio Sync

Peer-to-peer file synchronization using the BitTorrent protocol.

**Use case:** Sync files between devices without relying on cloud services.

**Image:** `lscr.io/linuxserver/resilio-sync` (LinuxServer.io, multi-arch)

**Docker Compose:**

```yaml
services:
  resilio-sync:
    image: lscr.io/linuxserver/resilio-sync:latest
    container_name: resilio-sync
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${DATA_ROOT}/resilio-sync/config:/config
      - ${DATA_ROOT}/resilio-sync/sync:/sync
    ports:
      - "${RESILIO_WEB_PORT:-8888}:8888"
      - "${RESILIO_SYNC_PORT:-55555}:55555"
    restart: unless-stopped
```

**Ports:**
- `8888` – Web UI
- `55555` – BitTorrent sync traffic

**Volumes:**
- `/config` – Settings and state
- `/sync` – Synced files

**First-time setup:**
1. Access web UI at `http://localhost:8888/` (or alternate port if using override)
2. Create a username/password
3. Add folders from `/sync` directory

**Notes:**
- Works identically on macOS (testing) and Linux (production)
- Free tier supports unlimited devices with basic features

---

### Nginx (Reverse Proxy)

Central entry point for all HTTP services.

**Use case:** Serve a dashboard and proxy requests to internal services.

**Image:** `nginx:alpine` (multi-arch, ~8MB)

**Docker Compose:**

```yaml
services:
  nginx:
    image: nginx:alpine
    container_name: nginx
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/html:/usr/share/nginx/html:ro
    depends_on:
      - resilio-sync
    restart: unless-stopped
```

**Ports:**
- `80` – HTTP (dashboard and reverse proxy)

**Volumes (version-controlled):**
- `nginx/nginx.conf` – Nginx configuration
- `nginx/html/` – Static files (dashboard)

**Routes:**
- `/` – Static dashboard (index.html)

**Adding a new service:**
1. Add service to `docker-compose.yml` with port mapping
2. Add link to `nginx/html/index.html`

**Note:** Services with their own web UI (like Resilio Sync) are exposed on their own ports rather than proxied through nginx. This avoids issues with apps that expect to be served from root.

---

## Data & Persistence

### Local Storage

- All persistent data stored in `./data/` (bind mounts)
- Never rely on container filesystem for data
- The `data/` directory is gitignored

```
data/
└── <service-name>/
    ├── config/    # service configuration
    └── <other>/   # service-specific data
```

---

### Backups

- Backup = copy the `data/` directory
- That's the only thing you need to back up

Approach:
- Scheduled backup script (e.g., rsync, tar)
- Backups stored:
  - External disk
  - Another machine
  - Cloud (optional)

---

## Secrets Management

- Secrets stored in:
  - `.env` files
  - Or Docker secrets (optional, later)

Rules:
- `.env` is never committed
- `.env.example` documents required variables
- Rotate secrets by editing env + restarting containers

---

## Deployment Workflow

### Initial Setup (Any Machine)

Works the same on your MacBook Pro (for testing) or Raspberry Pi (for production).

1. Install Docker Desktop (macOS) or Docker Engine (Linux)
2. Clone repo
3. Create `.env` from template
4. Start services

```bash
git clone <repo>
cd homehq
cp .env.example .env
# Edit .env (usually just PUID/PGID)
docker compose up -d
```

**That's it.** The `data/` directory is created automatically on first run.

---

### Updating Services

```bash
git pull
docker compose pull
docker compose up -d
```

Optional:
- Automated updates via Watchtower (only for non-critical services)

---

## Hardware Migration Plan

When changing hardware (e.g. MacBook → Pi, or Pi → Mac mini):

1. Stop services on old machine: `docker compose down`
2. Copy `data/` directory to new machine
3. Clone repo on new machine
4. Copy or recreate `.env`
5. `docker compose up -d`

**That's the entire migration.** The `data/` directory contains all state.

Target downtime: minutes, not hours.

---

## Monitoring & Management

### Recommended

- Portainer (single instance)
  - View containers
  - Restart services
  - Inspect logs
  - Manage stacks from Compose

### Optional

- Basic host monitoring (CPU, RAM, disk)
- Log rotation via Docker defaults

---

## What This Plan Explicitly Avoids

- Kubernetes
- Docker Swarm
- Multi-node clustering
- Complex service meshes
- Over-engineering

Reason:
- Home server requirements do not justify the complexity
- Reliability comes from simplicity and reproducibility

---

## Definition of "Done"

This setup is successful if:

- The entire server can be rebuilt from Git + `data/` backup
- Test on MacBook, deploy to Pi – same commands, same behavior
- A hardware swap is routine (copy `data/`, run `docker compose up`)
- Services survive restarts without manual intervention
- Maintenance does not require remembering tribal knowledge

---

## Future Extensions (Optional)

- Multiple compose profiles (dev / prod)
- Encrypted offsite backups
- Automated health checks
- CI to validate compose files

Only add when there is a real need.
