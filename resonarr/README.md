# Resonarr

Resonarr is deployed as two containers from the same immutable GHCR image:
the HTTP API and the persistent queue worker. The API is routed by Traefik at
`RESONARR_HOSTNAME`; the worker has no published port.

## First deployment

1. Merge [Resonarr backend PR #21](https://github.com/lexcode/resonarr-backend/pull/21), wait for its `main` publish job, and make the GHCR package pullable by this Raspberry Pi. From the Pi, verify it with `docker pull ghcr.io/lexcode/resonarr-backend:latest`.
2. Copy the template and replace `sha-replace-with-published-commit` with the published immutable SHA tag:

   ```bash
   cp .env.example .env
   ```

3. Configure a public hostname in the Cloudflare Tunnel before using Spotify OAuth. The default `resonarr.lexcode.dev` is a one-label hostname covered by this repository's documented `*.lexcode.dev` wildcard. In the Cloudflare Zero Trust tunnel dashboard, add `RESONARR_HOSTNAME` as a public hostname (the template value is `resonarr.lexcode.dev`) with service **HTTP** and URL `http://traefik:8081`. Port 8081 is Traefik's dedicated Docker-private Cloudflare entrypoint; it is not published on the host and does not redirect the Tunnel's already-HTTPS public requests. The tunnel runs in Docker, so do not use `127.0.0.1` as its origin. See the proxy stack's [public-hostname instructions](../proxy/README.md#public-hostnames) for the routing model.
4. Set the Spotify client ID/secret, a generated `BETTER_AUTH_SECRET`, and the operator credentials. `RESONARR_HOSTNAME` and `SPOTIFY_REDIRECT_URI` name the public API; register that exact callback URI in Spotify. `RESONARR_WEB_ORIGIN` is the separate Vercel frontend origin (the template value is `app-resonarr.lexcode.dev`, a sibling one-label subdomain of the API's `resonarr.lexcode.dev`) that is allowed by CORS and receives the post-Spotify redirect. Configure that hostname as the Vercel project's custom domain — a `*.vercel.app` preview URL is a different registrable domain and cannot hold a session (`resonarr-backend` ADR 0009).
5. Load the completed local values for the following commands, then create the writable bind mounts. The image runs as the `node` user (UID 1000), so ownership must allow UID 1000 to create the SQLite database, staging files, and music files:

   ```bash
   set -a; . ./.env; set +a
   mkdir -p data downloads-staging "$RESONARR_MUSIC_HOST_PATH"
   sudo chown -R 1000:1000 data downloads-staging "$RESONARR_MUSIC_HOST_PATH"
   ```

6. Start the proxy once to create Resonarr's private network, then validate and start Resonarr:

   ```bash
   cd ../proxy
   docker compose up -d

   cd ../resonarr
   docker compose --env-file .env.example config --quiet
   docker compose up -d
   curl --fail --location "https://$RESONARR_HOSTNAME/health"
   ```

On first boot, visit the API through the configured frontend and complete Spotify OAuth. The backend redirects back to `RESONARR_WEB_ORIGIN`; it permits browser requests only from that origin.

## Operations

`./data` holds the SQLite state, `./downloads-staging` holds incomplete worker output, and `RESONARR_MUSIC_HOST_PATH` is the permanent music library. Back up `data` and music. Do not use the Beets inbox or its automatic importer: Resonarr finalizes completed files itself, and failed or partial downloads remain outside `/music`.

For a deliberate update, change `RESONARR_IMAGE` to a newer published SHA tag, then run `docker compose pull && docker compose up -d`. Check API and worker state with `bash scripts/status.sh resonarr` from the repository root. Roll back by restoring the previous SHA tag and repeating that command.

To start it at boot:

```bash
sudo cp ../systemd/resonarr.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now resonarr.service
```

The proxy owns the Docker-private `resonarrnetwork`, so it must start before Resonarr. Install the updated `proxy.service` too when enabling boot startup; `resonarr.service` starts it automatically through its systemd dependency.
