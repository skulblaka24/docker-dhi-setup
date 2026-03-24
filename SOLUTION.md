# Docker Hardening Migration

## App Architecture

![Alt text](assets/app_architecture.svg)

## Image Choices

All four images were pulled from `dhi.io`. Using my own Docker Cloud account as it is free.

| Service  | Before         | After                                         |
| -------- | -------------- | --------------------------------------------- |
| API      | `python:3.11`  | `dhi.io/python:3.11-alpine3.23` (multi-stage) |
| Database | `postgres:15`  | `dhi.io/postgres:15-alpine3.22`               |
| Cache    | `redis:7`      | `dhi.io/redis:7-debian13`                     |
| Proxy    | `nginx:latest` | `dhi.io/nginx:1.29.6-alpine3.23`              |

I tried to use only non-root images, without shells or package managers, with the minimal vuln as possible.

#### Python

Python dev image:
![Alt text](assets/python-dev.png)
Accessible here: [Python dev image list on dhi.io](https://hub.docker.com/hardened-images/catalog/dhi/python/images?search=3.11&distributions=alpine+3.23&variants=dev)

Python runtime image:
![Alt text](assets/python-runtime.png)
Accessible here: [Python runtime image list on dhi.io](https://hub.docker.com/hardened-images/catalog/dhi/python/images?search=3.11&distributions=alpine+3.23&variants=runtime)

#### Postgres

![Alt text](assets/postgres.png)
Accessible here: [Postgres image list on dhi.io](https://hub.docker.com/hardened-images/catalog/dhi/postgres/images?search=15)

#### Redis

![Alt text](assets/redis.png)
Accessible here: [Redis image list on dhi.io](https://hub.docker.com/hardened-images/catalog/dhi/redis/images?page=0)

#### Nginx

![Alt text](assets/nginx.png)
Accessible here: [Nginx image list on dhi.io](https://hub.docker.com/hardened-images/catalog/dhi/nginx/images?distributions=alpine+3.23)

### Why Docker Hardened Images? Instead of Chainguard images for example.

- **Zero known CVEs** at publish time — Docker continuously patches and republishes.
- **Distroless runtime** — no shell, no package manager, minimal binaries.
- **Non-root by default** — all DHI images run as an unprivileged user out of the box.
- **Supply-chain transparency** — every image ships with a signed SBOM, SLSA Build Level 3 provenance, and VEX metadata.
- **Drop-in compatible** — same env vars and entrypoints as upstream Docker Official Images.
- **Apache 2.0 licensed** — no vendor lock-in, no hidden restrictions.

### Image variant notes

- **Postgres / Nginx / Python**: Alpine variants chosen for smallest footprint.
- **Redis**: DHI only offers Debian 13 for Redis — no Alpine variant exists. At ~64 MB it remains significantly smaller than the original `redis:7` (~117 MB).

---

## Dockerfile Changes (API)

#### Multi-stage build using Alpine:

```
Stage 1 (builder): dhi.io/python:3.11-alpine3.23-dev
  → has pip; installs deps into /install with --target
  → requirements.txt copied first for better layer caching

Stage 2 (runtime): dhi.io/python:3.11-alpine3.23
  → distroless; receives /app/lib and app.py only
  → PYTHONPATH=/app/lib set so Python finds packages
  → no USER directive needed — DHI runs as non-root by default
```

***Nota***:
Had to use `--target` instead of `--prefix` and copy packages to `/app/lib` with `PYTHONPATH` set accordingly, as Alpine Python was not looking at the right place with the previous structure.

#### Concerns:

| Concern | Before | After |
|---------|--------|-------|
| Base image | `python:3.11` (full Debian) | DHI distroless Python Alpine |
| Shell in runtime | Yes | No |
| pip in runtime | Yes | No |
| Runs as root | Yes | No |
| CVEs in base | High (200+) | ~0 |

***Nota***:
For the estimated CVEs, I scanned the images using Docker Scout (e.g., `docker scout cves python:3.11`)

---

## docker-compose Changes

| Change | Detail |
|--------|--------|
| All image tags | Replaced with DHI equivalents from `dhi.io`, pinned by digest for reproducibility |
| Network segmentation | Split into `frontend` (nginx↔host) and `backend` (api↔db↔redis, internal only) |
| Postgres volume mount | Changed from `/var/lib/postgresql/data` to `/var/lib/postgresql` — DHI uses a versioned subdir (`/var/lib/postgresql/15/data`) so the parent must be mounted |
| Redis security | Added `--requirepass ${REDIS_PASSWORD:-redispass}` — DHI Redis defaults to `protected-mode yes`, which blocks inter-container traffic without a password |
| Redis healthcheck | Added `-a ${REDIS_PASSWORD:-redispass}` to `redis-cli ping` so the healthcheck itself authenticates |
| Redis password in API env | Added `REDIS_PASSWORD` env var so the Flask app can authenticate |
| Read-only filesystems | All services use `read_only: true` with `tmpfs` for directories needing writes |
| Capabilities | `cap_drop: ALL` on all services; only specific caps re-added where strictly needed (`SETUID`/`SETGID`/`DAC_OVERRIDE` for postgres init, `NET_BIND_SERVICE` for nginx port 80) |
| No new privileges | `no-new-privileges:true` set on all services |
| Resource limits | CPU and memory limits defined for all services via `deploy.resources` |
| Health check tuning | Added `start_period` to all healthchecks to avoid false failures during init |
| API image name | Added `image: dhi-taskapi:latest` so the built image is named and tagged |

## app.py Changes

Added `REDIS_PASSWORD` env var reading and passed it to the Redis client constructor:

```python
redis_password = os.getenv('REDIS_PASSWORD', None)
cache = redis.Redis(
    host=redis_host,
    port=redis_port,
    password=redis_password,  # added
    ...
)
```

---

## Size Comparison (approximate)

| Service | Before | After | Reduction |
|---------|--------|-------|-----------|
| API | ~1.15 GB | ~106 MB | ~91% |
| postgres | ~445 MB | ~289 MB | ~35% |
| redis | ~117 MB | ~64 MB | ~45% |
| nginx | ~161 MB | ~11 MB | ~93% |
| **Total** | **~1.87 GB** | **~470 MB** | **~75%** |

***Nota***:
Ran `docker images` after build to confirm the sizes.

---

## Security Improvements Summary

1. No shell in any runtime container → prevents interactive exploitation post-RCE (Remote Code Execution).
2. No root processes across all four services → limits blast radius of any escape.
3. No package managers at runtime → prevents in-container software installation.
4. Redis password authentication enabled → removes unauthenticated access vector.
5. Signed SBOMs + SLSA L3 provenance → full supply-chain auditability.
6. Unpinned `nginx:latest` eliminated → deterministic, security-patched builds.
7. All images pinned by digest → fully reproducible builds, immune to tag mutation.
8. Read-only filesystems on all containers → prevents runtime filesystem tampering.
9. All Linux capabilities dropped → minimal privilege surface per container.
10. Network segmentation → backend services unreachable from the host directly.

---

## Possible Security Improvements

**Secrets management** — replace plaintext env var defaults with Docker secrets or a vault.

**HTTPS / TLS termination** — add TLS via Let's Encrypt or Traefik or in the app.