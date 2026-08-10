# Beets image for the media stack.
#
# The container has no daemon and no scheduled import: it idles on `sleep infinity`
# and every import is driven manually via `docker compose exec` (see media/README.md),
# so match quality can be reviewed before anything is moved into the library.
FROM python:3.13-slim

# fpcalc (libchromaprint-tools) backs the `chroma` acoustic-fingerprint plugin, which is
# what identifies SpotiFLAC files whose embedded tags are too thin to match on their own.
# `flac` backs the `badfiles` plugin's integrity checks.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        flac \
        libchromaprint-tools \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "beets[chroma,fetchart]"

# BEETSDIR is where beets looks for config.yaml and (per config.yaml) keeps library.db.
# Compose bind-mounts it to ./data/beets so both survive container rebuilds.
# HOME points at the same place because beets writes state relative to it when run
# as an arbitrary UID that has no /etc/passwd entry.
ENV BEETSDIR=/config \
    HOME=/config

WORKDIR /music-inbox

CMD ["sleep", "infinity"]
