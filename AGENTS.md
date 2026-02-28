# AGENTS.md — Knowledge Portal

> Agentic coding guide for this repository.

## Project Overview

A self-hosted, AI-enhanced learning platform running on Unraid NAS. Serves offline copies of Wikipedia, Project Gutenberg, Stack Overflow, and 7 other knowledge sources (~356GB total) accessible from any device on the home network via Kiwix.

## Project Structure

```
knowledge-portal/
├── Dockerfile              # Thin kiwix-serve wrapper (Alpine base)
├── docker-compose.yml      # Two-container orchestration (kiwix + tools)
├── .env                    # Configuration (paths, ports)
├── .dockerignore
├── .gitignore
├── README.md               # Full architecture & operations guide
└── .github/                # CI/CD workflows (GitHub Actions)
```

## Architecture

**Two-container design:**
- `knowledge-portal` (kiwix-serve, Alpine): Read-only ZIM server on port 8080 (mapped to 8081)
- `knowledge-portal-tools` (Debian Slim, separate repo): Download/update ZIM files

**Storage:** `/mnt/user/knowledge/library/` on Unraid NAS (mounted as `/data` in containers)

**Knowledge sources:** Wikipedia, Gutenberg, Stack Overflow, Wiktionary, Wikibooks, Wikiversity, Wikivoyage, Wikiquote, Wikisource, PhET

## Build & Run Commands

```bash
# Start kiwix server (via docker-compose)
docker compose up -d

# Initial setup (download all sources)
docker run -d --name knowledge-setup \
  -v /mnt/user/knowledge/library:/data \
  ghcr.io/thetechild/knowledge-portal-tools:latest \
  /scripts/setup.sh

# Weekly updates
docker run --rm \
  -v /mnt/user/knowledge/library:/data \
  ghcr.io/thetechild/knowledge-portal-tools:latest \
  /scripts/update.sh

# Restart kiwix to pick up new ZIM files
docker restart kiwix-wikipedia
```

## Conventions

1. **Separate containers for separate concerns** — kiwix-serve (minimal Alpine) vs tools (full Debian)
2. **Digest-pinned base images** in Dockerfile for reproducible builds
3. **English-only ZIM variants** for now (simplifies selection)
4. **Unraid-managed containers** — no docker-compose on NAS itself; use Unraid Docker UI
5. **GitHub Actions CI/CD** — build & push to GHCR on every push to `main`
6. **Dependabot monitoring** for base images and Actions versions
7. **`provenance: false`** on build-push-action to avoid GHCR manifest issues with older Docker clients

## Known Limitations / Gotchas

- **Kiwix-serve is Alpine/BusyBox** — no bash, no GNU wget/grep. Tools container uses Debian Slim for full GNU tooling.
- **No docker-compose on Unraid** — containers managed via Unraid's web UI, not CLI
- **GHCR authentication** — NAS requires classic PAT (`unraid-docker-pull`) with `read:packages` scope in `/root/.docker/config.json`
- **Min free space** — Keep 50GB free on Unraid share for staging downloads
- **Healthcheck uses wget** — Requires wget in container (present in kiwix-serve image)
- **Future expansion** — Planned: Calibre, Ollama, vector DB, unified frontend, lecture integration

