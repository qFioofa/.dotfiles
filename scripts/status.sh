#!/usr/bin/env bash
# Show how each config repository relates to its remote and to the local clone.
# Read-only: no commits, no pushes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$HUB_DIR/config/repos.tsv"
LOCAL_ROOT="${LOCAL_ROOT:-$HOME/qf}"

FETCH=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--fetch) FETCH=1; shift ;;
        -h|--help)
            cat <<EOF
Usage: $0 [--fetch]

  -f, --fetch   Fetch origin in the hub submodules before reporting

Local clones are read from $LOCAL_ROOT (override with LOCAL_ROOT=...).
EOF
            exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

[ -f "$MANIFEST" ] || { echo "manifest not found: $MANIFEST" >&2; exit 1; }

count_ahead() {
    git -C "$1" rev-list --count "$2..HEAD" 2>/dev/null || echo 0
}
count_behind() {
    git -C "$1" rev-list --count "HEAD..$2" 2>/dev/null || echo 0
}

printf '%-24s %-10s %-10s %-10s %s\n' name hub upstream local changes

while IFS=$'\t' read -r _ name path branch _ _ _; do
    branch="${branch%$'\r'}"
    repo="$HUB_DIR/$path"

    if [ ! -d "$repo" ]; then
        printf '%-24s %-10s %-10s %-10s %s\n' "$name" "-" "-" "-" "not cloned"
        continue
    fi

    [ "$FETCH" -eq 1 ] && git -C "$repo" fetch --quiet origin 2>/dev/null

    hub_rev="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo '?')"
    up_rev="$(git -C "$repo" rev-parse --short "origin/$branch" 2>/dev/null || echo '?')"
    hub_behind="$(count_behind "$repo" "origin/$branch")"
    [ "$hub_behind" != "0" ] && hub_rev="$hub_rev (-$hub_behind)"

    local_state="-"; dirty="-"
    local_dir="$LOCAL_ROOT/$name"
    if [ -d "$local_dir/.git" ]; then
        [ "$FETCH" -eq 1 ] && git -C "$local_dir" fetch --quiet origin 2>/dev/null
        local_rev="$(git -C "$local_dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
        dirty="$(git -C "$local_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
        lbranch="$(git -C "$local_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
        ahead="$(count_ahead "$local_dir" "origin/$lbranch")"
        behind="$(count_behind "$local_dir" "origin/$lbranch")"
        local_state="$local_rev"
        [ "$ahead" != "0" ] && local_state="$local_state +$ahead"
        [ "$behind" != "0" ] && local_state="$local_state -$behind"
    else
        local_state="no clone"
    fi

    printf '%-24s %-10s %-10s %-10s %s\n' "$name" "$hub_rev" "$up_rev" "$local_state" "$dirty"
done < <(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST")

cat <<EOF

Legend:
  hub      submodule commit ("(-N)" = N commits behind its tracked branch)
  upstream commit of origin/<branch>
  local    clone in $LOCAL_ROOT ("+N" ahead, "-N" behind its origin)
  changes  uncommitted files in the local clone
EOF
