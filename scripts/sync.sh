#!/usr/bin/env bash
# Move every submodule to the latest commit of its tracked branch and,
# optionally, record the new pointers in this hub.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

COMMIT=0
PUSH=0
QUIET=0
MESSAGE="chore: sync submodules ($(date -u +%F))"

usage() {
    cat <<EOF
Sync all submodules to their latest upstream commit.

Usage: $0 [options]

Options:
  -c, --commit         Commit updated submodule pointers in this hub
  -p, --push           Commit and push the hub (implies --commit)
  -m, --message MSG    Commit message (default: "$MESSAGE")
  -q, --quiet          Only print the summary
  -h, --help           Show this help
EOF
}

log() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--commit) COMMIT=1; shift ;;
        -p|--push) COMMIT=1; PUSH=1; shift ;;
        -m|--message) [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 2; }; MESSAGE="$2"; shift 2 ;;
        -q|--quiet) QUIET=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

cd "$HUB_DIR"

log "Syncing submodule URLs..."
git submodule sync --recursive >/dev/null

log "Fetching latest commits for every submodule..."
git submodule update --init --recursive --remote

if ! git status --porcelain -- repos | grep -q .; then
    log "Already up to date."
    exit 0
fi

log ""
log "Updated submodules:"
git --no-pager diff --submodule=short -- repos 2>/dev/null || git --no-pager submodule summary

if [ "$COMMIT" -eq 0 ]; then
    cat <<EOF

Pointers are not committed. Review them with:
  git status --short repos
Then record them with:
  $0 --commit
EOF
    exit 0
fi

git add --all -- repos
if git diff --cached --quiet -- repos; then
    log "Nothing to commit."
    exit 0
fi

git commit -m "$MESSAGE"
log "Committed: $MESSAGE"

if [ "$PUSH" -eq 1 ]; then
    git push origin HEAD
    log "Pushed to origin."
fi
