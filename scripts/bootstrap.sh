#!/usr/bin/env bash
# Set up this hub on a new machine: clone it with all submodules, then deploy.
set -euo pipefail

HUB_URL="${DOTFILES_URL:-https://github.com/qFioofa/.dotfiles.git}"
TARGET="${DOTFILES_DIR:-$HOME/qf/.dotfiles}"
DEPLOY=1

usage() {
    cat <<EOF
Bootstrap the dotfiles hub on a new machine.

Usage: $0 [options]

Options:
  -d, --dir DIR    Clone target directory (default: $TARGET)
  -u, --url URL    Hub repository URL (default: $HUB_URL)
      --no-deploy  Clone and init submodules, but do not deploy
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir) [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 2; }; TARGET="$2"; shift 2 ;;
        -u|--url) [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 2; }; HUB_URL="$2"; shift 2 ;;
        --no-deploy) DEPLOY=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -d "$TARGET/.git" ]; then
    echo "Hub already present: $TARGET"
    git -C "$TARGET" submodule update --init --recursive
else
    echo "Cloning $HUB_URL -> $TARGET"
    mkdir -p "$(dirname "$TARGET")"
    git clone --recurse-submodules "$HUB_URL" "$TARGET"
fi

if [ "$DEPLOY" -eq 1 ]; then
    echo "Deploying all configurations..."
    exec "$TARGET/scripts/deploy.sh"
fi

echo "Done. Deploy later with: $TARGET/scripts/deploy.sh"
