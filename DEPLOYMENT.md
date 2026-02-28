# Deployment -- Knowledge Portal

Deploys to the Unraid NAS (Tower, 192.168.1.152) as a Docker container.

| | |
|---|---|
| **Container name** | `kiwix-wikipedia` |
| **Image** | `ghcr.io/thetechchild/knowledge-portal:latest` |
| **Network** | `bridge` |
| **Ports** | 80->8081 (Kiwix web UI) |
| **Data mount** | `/mnt/user/knowledge/library` -> `/data` (read-only) |
| **Template** | `/boot/config/plugins/dockerMan/templates-user/my-kiwix-wikipedia.xml` |
| **Autostart** | No -- requires manual start after NAS reboot |

## Deploying Updates

After pushing a new image to GHCR (via CI or manual `docker push`):

```
# 1. Pull the latest image
mcp_unraid-docker: pull_image(repository="ghcr.io/thetechchild/knowledge-portal", tag="latest")

# 2. Recreate the container with the new image
mcp_unraid-docker: recreate_container(
  name="kiwix-wikipedia",
  image="ghcr.io/thetechchild/knowledge-portal:latest",
  ports={"80/tcp": 8081},
  volumes=["/mnt/user/knowledge/library:/data:ro"],
  environment={"TZ": "America/Denver"}
)

# 3. Verify it started
mcp_unraid-docker: fetch_container_logs(container_id="kiwix-wikipedia", tail=20)
```

## After NAS Reboot

This container is NOT autostarted. Start it manually:
```
mcp_unraid-docker: start_container(container_id="kiwix-wikipedia")
```

## Monitoring

Use the `unraid-docker` MCP tools to manage this container:
- `list_containers` -- check running status
- `fetch_container_logs` -- view output
- `stop_container` / `start_container` -- lifecycle control

Full NAS integration docs: `~/archbox/docs/unraid-integration.md`
