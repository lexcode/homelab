# Documents stack (paperless-ngx + paperless-gpt)

AI-powered document management. [paperless-ngx](https://docs.paperless-ngx.com/) handles storage, search, and the web UI. [paperless-gpt](https://github.com/icereed/paperless-gpt) sits alongside it and uses an LLM to automatically OCR scans, generate titles, tags, and correspondents.

## Architecture

```
Raspberry Pi 5 (server)          Desktop / main machine
┌──────────────────────┐         ┌─────────────────────┐
│  paperless-ngx :8000 │         │  Ollama  :11434      │
│  paperless-gpt :8080 │────────▶│  - minicpm-v (OCR)   │
│  redis (broker)      │  LAN    │  - qwen3:8b (tagging)│
└──────────────────────┘         └─────────────────────┘
```

The Raspberry Pi 5 is not powerful enough for LLM inference. Ollama runs on the desktop and is exposed on the LAN so the Pi can reach it. See [Ollama LAN setup](#ollama-lan-setup) if it's not accessible yet.

## Services

| Service | Port | Purpose |
|---|---|---|
| `paperless-ngx` | `8000` | Document storage, search, web UI |
| `paperless-gpt` | `8811` | AI tagging, OCR, title generation |
| `broker` | — | Redis message queue (required by paperless-ngx, internal only) |

## Models (Ollama)

| Model | Role |
|---|---|
| `minicpm-v` | Vision OCR — reads raw document scans/images and extracts text |
| `qwen3:8b` | Text LLM — generates titles, tags, and correspondents from extracted text |

Both models load on demand; Ollama unloads them after 5 minutes of inactivity.

## Quick start

### 1. Environment file

```bash
cp .env.example .env
```

Edit `.env` and fill in:

| Variable | How to get it |
|---|---|
| `PAPERLESS_SECRET_KEY` | `python3 -c "import secrets; print(secrets.token_hex(32))"` |
| `PAPERLESS_API_TOKEN` | See step 3 below |
| `OLLAMA_HOST` | LAN IP of your desktop, e.g. `http://192.168.0.118:11434` |
| `PUID` / `PGID` | Run `id` on the Pi to get your user/group IDs |
| `TZ` | Your timezone, e.g. `Europe/Lisbon` |

### 2. Pull Ollama models (on the desktop)

```bash
ollama pull minicpm-v
ollama pull qwen3:8b
```

### 3. Start paperless-ngx first and create an admin user

```bash
cd documents
docker compose up -d broker paperless-ngx
```

Wait ~20 seconds, then create a superuser:

```bash
docker compose exec paperless-ngx python3 manage.py createsuperuser
```

Generate the API token for that user:

```bash
docker compose exec paperless-ngx python3 manage.py drf_create_token <username>
```

Paste the token into `.env` as `PAPERLESS_API_TOKEN`.

### 4. Start the full stack

```bash
docker compose up -d
```

| URL | What |
|---|---|
| `http://<pi-ip>:8000` | paperless-ngx UI |
| `http://<pi-ip>:8811` | paperless-gpt UI |

## Usage

paperless-gpt processes documents by tag:

| Tag | Effect |
|---|---|
| `paperless-gpt` | Queue for **manual** review — you approve suggestions in the UI |
| `paperless-gpt-auto` | **Automatic** — title, tags, and correspondent applied without review |
| `paperless-gpt-ocr-auto` | **Automatic OCR** — runs vision OCR then updates the document |

Tag a document in paperless-ngx, then visit the paperless-gpt UI to review or monitor progress.

## Ollama LAN setup

Ollama must listen on the LAN interface (not just `127.0.0.1`) for the Pi to reach it.

On the desktop (Arch Linux / Omarchy):

```bash
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
Environment=OLLAMA_HOST=0.0.0.0:11434
EOF
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

Verify from the Pi:

```bash
curl -sS http://<desktop-ip>:11434/api/version
```

## Data layout

```
documents/
├── compose.yml
├── .env                  # not committed
├── .env.example
└── data/                 # not committed (gitignored)
    ├── paperless-ngx/
    │   ├── data/         # paperless database and index
    │   ├── media/        # stored documents
    │   ├── export/       # manual exports
    │   └── consume/      # drop files here to auto-import
    ├── paperless-gpt/
    │   ├── prompts/      # customisable AI prompt templates
    │   ├── hocr/         # hOCR output (if enabled)
    │   └── pdf/          # enhanced PDF output (if enabled)
    └── redis/            # broker persistence
```

Drop files into `data/paperless-ngx/consume/` and they will be automatically imported.
