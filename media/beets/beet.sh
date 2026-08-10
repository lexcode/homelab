#!/usr/bin/env bash
#
# Convenience wrapper around `docker compose exec beets ...`.
# Run from the media/ directory (or anywhere — the script finds it itself).
#
# Nothing here imports automatically: every import subcommand is interactive and
# prompts before moving files into the library.

set -u

stack_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
  cat >&2 <<'EOF'
Usage: beet.sh <command> [args...]

Commands:
  shell                 Interactive shell inside the beets container
  beet <args...>        Run an arbitrary beet command (e.g. beet.sh beet ls -a)

  import                Interactive import of /music-inbox, grouping a flat
                        directory of files into albums (--group-albums)
  import-tree           Interactive import of /music-inbox where files are
                        already in per-album directories (no grouping)
  import-singles        Import /music-inbox as standalone tracks (--singletons)
  retry <path>          Re-prompt for one file/dir you previously chose Skip on
                        (--noincremental; see note below)

  stats                 Library totals (tracks, albums, size, time)
  ls [query]            List what is in the library
  dupes                 Report duplicate albums
  missing               Report albums with tracks missing
  check                 Verify FLAC integrity across the library (slow)
  inbox                 List what is currently sitting in /music-inbox

Every import is interactive. Nothing is moved without a confirmation at the prompt.

Note on Skip: with import.incremental on (the default here), choosing [S]kip at a
prompt is remembered — re-running import/import-singles/import-tree on the same
inbox will silently skip that item again with no prompt ("Skipped N paths"), rather
than asking a second time. Use `retry <path>` to deliberately revisit one skipped
item; it passes --noincremental so beets forgets that one decision and prompts again.
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 2
fi

command=$1
shift

# -it so beets' import prompts work; the compose project is pinned to media/.
run() {
  (cd "$stack_dir" && docker compose exec -it beets "$@")
}

case $command in
  shell)
    run bash "$@"
    ;;
  beet)
    run beet "$@"
    ;;
  import)
    run beet import --group-albums /music-inbox "$@"
    ;;
  import-tree)
    run beet import /music-inbox "$@"
    ;;
  import-singles)
    run beet import --singletons /music-inbox "$@"
    ;;
  retry)
    if [[ $# -eq 0 ]]; then
      printf 'Usage: beet.sh retry <path under /music-inbox>\n' >&2
      exit 2
    fi
    target=$1
    shift
    run beet import --singletons --noincremental "$target" "$@"
    ;;
  stats)
    run beet stats "$@"
    ;;
  ls)
    run beet ls "$@"
    ;;
  dupes)
    run beet duplicates --album "$@"
    ;;
  missing)
    run beet missing --album "$@"
    ;;
  check)
    run beet badfiles "$@"
    ;;
  inbox)
    run find /music-inbox -type f -printf '%P\n' "$@"
    ;;
  -h | --help | help)
    usage
    exit 0
    ;;
  *)
    printf 'Unknown command: %s\n\n' "$command" >&2
    usage
    exit 2
    ;;
esac
