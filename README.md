# Knowledge Portal

A self-hosted, AI-enhanced learning platform running on Unraid NAS. Serves offline copies of Wikipedia, Project Gutenberg, Stack Overflow, and 7 other knowledge sources — accessible from any device on the home network.

This is **Step 1** of a larger vision: a unified portal integrating textbooks, lectures, workbooks, local LLMs, and vector search for semantic discovery across all sources.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Unraid NAS (192.168.1.152 / Tower)                 │
│                                                     │
│  ┌──────────────────────┐  ┌──────────────────────┐ │
│  │  knowledge-portal    │  │  knowledge-portal-   │ │
│  │  (kiwix-serve)       │  │  tools (Debian Slim) │ │
│  │                      │  │                      │ │
│  │  Serves all .zim     │  │  Downloads & updates │ │
│  │  files on port 8081  │  │  ZIM library files   │ │
│  └──────────┬───────────┘  └──────────┬───────────┘ │
│             │ :ro                     │ :rw         │
│             └──────────┬──────────────┘             │
│                        │                            │
│         /mnt/user/knowledge/library/                │
│         ├── wikipedia_en_all_maxi_2025-08.zim       │
│         ├── wiktionary_en_all_nopic_2025-09.zim     │
│         ├── gutenberg_en_all_YYYY-MM.zim            │
│         └── ...                                     │
└─────────────────────────────────────────────────────┘
```

### Two-Container Design

| Container | Base Image | Purpose | Mount | Lifecycle |
|-----------|-----------|---------|-------|-----------|
| `knowledge-portal` | kiwix-serve (Alpine) | Read-only ZIM server | `/data` :ro | Always running |
| `knowledge-portal-tools` | Debian Slim | Download, update, manage ZIMs | `/data` :rw | Run-once (setup + weekly cron) |

**Why separate containers?** Kiwix-serve is Alpine/BusyBox — no bash, no GNU wget, no GNU grep. Rather than fighting a minimal base image, the tools container uses Debian Slim with full GNU tooling. Each container does one job well.

## Repositories

| Repo | Visibility | Image | Purpose |
|------|-----------|-------|---------|
| [knowledge-portal](https://github.com/TheTechChild/knowledge-portal) | Public | `ghcr.io/thetechild/knowledge-portal` | Thin kiwix-serve wrapper that globs `/data/*.zim` |
| [knowledge-portal-tools](https://github.com/TheTechChild/knowledge-portal-tools) | Private | `ghcr.io/thetechild/knowledge-portal-tools` | Debian Slim downloader with setup + update scripts |

Both repos use GitHub Actions for CI/CD (build & push to GHCR on every push to `main`) and Dependabot for automated dependency monitoring.

## Knowledge Sources

| Source | ZIM Variant | Size | Description |
|--------|------------|------|-------------|
| Wikipedia | `wikipedia_en_all_maxi` | ~100GB | Full English Wikipedia with images |
| Project Gutenberg | `gutenberg_en_all` | ~206GB | 60,000+ public domain books |
| Wikisource | `wikisource_en_all_maxi` | ~18GB | Primary source texts |
| Stack Overflow | `stackoverflow.com_en_all` | ~15GB | Programming Q&A |
| Wiktionary | `wiktionary_en_all_nopic` | ~8GB | Dictionary & definitions |
| Wikibooks | `wikibooks_en_all_maxi` | ~5GB | Open textbooks |
| Wikiversity | `wikiversity_en_all_maxi` | ~2GB | Learning materials & courses |
| Wikivoyage | `wikivoyage_en_all_maxi` | ~1GB | Travel guides |
| Wikiquote | `wikiquote_en_all_maxi` | ~900MB | Notable quotations |
| PhET | `phet_en_all` | ~100MB | Interactive science simulations |

**Total**: ~356GB · **Language**: English only (for now)

**Excluded**: Khan Academy (no ZIM available), TED Talks (~79GB multilingual, excluded to save space)

## Infrastructure

### Unraid Share

- **Share name**: `knowledge`
- **Primary storage**: Cache (SSD) → moves to Array via Mover
- **Min free space**: 50GB
- **Path**: `/mnt/user/knowledge/`

### Directory Layout

```
/mnt/user/knowledge/
└── library/              # All .zim files live here (mounted as /data in containers)
    ├── wikipedia_en_all_maxi_2025-08.zim
    ├── wiktionary_en_all_nopic_2025-09.zim
    └── ...
```

### GHCR Authentication (NAS)

Docker on the NAS authenticates with GHCR using a classic PAT (`unraid-docker-pull`) with `read:packages` scope. Credentials stored in `/root/.docker/config.json`.

```bash
docker login ghcr.io -u TheTechChild
```

### Container Setup (Unraid Docker UI)

**Kiwix server** (always running):
- **Name**: `kiwix-wikipedia`
- **Image**: `ghcr.io/thetechild/knowledge-portal:latest`
- **Port**: 8081 → 8080
- **Volume**: `/mnt/user/knowledge/library` → `/data` (Read Only)
- **Restart**: unless-stopped
- **Access**: http://192.168.1.152:8081

**Tools / updater** (run-once via User Scripts):
- **Image**: `ghcr.io/thetechild/knowledge-portal-tools:latest`
- **Volume**: `/mnt/user/knowledge/library` → `/data` (Read/Write)
- **Restart**: no

## Operations

### Initial Setup (download all sources)

```bash
docker run -d --name knowledge-setup \
  -v /mnt/user/knowledge/library:/data \
  ghcr.io/thetechild/knowledge-portal-tools:latest \
  /scripts/setup.sh

# Follow progress
docker logs -f knowledge-setup

# Clean up after completion
docker rm knowledge-setup
```

### Weekly Updates

Run via Unraid User Scripts plugin (weekly schedule):

```bash
docker run --rm \
  -v /mnt/user/knowledge/library:/data \
  ghcr.io/thetechild/knowledge-portal-tools:latest \
  /scripts/update.sh

# Restart kiwix to pick up new files
docker restart kiwix-wikipedia
```

### After Downloads Complete

Restart the Kiwix container so it discovers all new ZIM files:

```bash
docker restart kiwix-wikipedia
```

All sources appear as "books" on the Kiwix landing page at http://192.168.1.152:8081.

## Design Decisions

### Conventions

1. **Separate containers for separate concerns** — don't cram everything into one image
2. **English only** for now — simplifies ZIM variant selection
3. **Containers managed through Unraid's Docker web UI** — not docker-compose (Unraid doesn't ship it)
4. **Private repo for tools** — contains download infrastructure, not needed publicly
5. **Public repo for the portal** — the kiwix-serve wrapper is generic and harmless
6. **Digest-pinned base images** in Dockerfiles for reproducible builds
7. **Dependabot** monitors both Docker base images and GitHub Actions versions

### CI/CD

- **`provenance: false`** on `build-push-action@v6` — GHCR doesn't properly serve OCI attestation manifests for private packages, causing "manifest unknown" errors on older Docker clients (including Unraid)
- Both repos use the same workflow pattern: build on push to `main`, push to GHCR with `latest` + short SHA tags

### Unraid-Specific

- **No docker-compose** — Unraid manages containers through its own XML templates / web UI
- **No tmux** by default — use `docker run -d` for long-running operations, or install tmux via Nerd Tools plugin
- **Slackware-based** — no apt/pacman; use Nerd Tools plugin for common utilities
- **Advanced View toggle** (top-right of Add Container page) reveals Post Arguments and Extra Parameters fields

## Future Plans

This portal is the foundation for a much larger learning system:

- [ ] **Calibre** — Book management (textbooks, technical references)
- [ ] **Ollama** — Local LLM for question answering and summarization
- [ ] **Vector database** — Semantic search across all knowledge sources
- [ ] **Unified portal frontend** — Single interface for browsing, searching, and learning
- [ ] **Lecture integration** — Downloaded video courses and educational content
- [ ] **Workbook system** — Interactive exercises tied to knowledge sources
