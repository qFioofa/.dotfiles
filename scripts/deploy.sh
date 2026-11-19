#!/usr/bin/env bash
# Deploy every configuration repository tracked by this hub.
#
# Reads config/repos.tsv, skips entries that do not support the current OS, and
# runs each repo's own deploy script from inside that repo directory. Several
# deploy scripts resolve paths relative to the current directory, so the cd is
# required.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$HUB_DIR/config/repos.tsv"

DRY_RUN=0
DO_UPDATE=0
FAIL_FAST=0
DO_LIST=0
ONLY=""
SKIP=""
EXTRA=()

usage() {
    cat <<EOF
Deploy all configuration repositories.

Usage: $0 [options]

Options:
  -n, --dry-run          Print what would run, change nothing
  -u, --update           Run scripts/sync.sh before deploying
  -o, --only LIST        Only these repos (comma separated, name or path)
  -s, --skip LIST        Skip these repos (comma separated)
  -x, --extra-args ARGS  Extra flags appended to every deploy script
      --fail-fast        Stop at the first failed deploy
  -l, --list             List entries for the current OS and exit
  -h, --help             Show this help

Examples:
  $0 --dry-run
  $0 --only nvim,zsh
  $0 --update --extra-args "-r"
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

detect_os() {
    local kernel
    kernel="$(uname -s)"
    case "$kernel" in
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl; else echo linux; fi
            ;;
        Darwin) echo darwin ;;
        MINGW*|MSYS*|CYGWIN*) echo win ;;
        *) printf '%s\n' "$kernel" | tr '[:upper:]' '[:lower:]' ;;
    esac
}

list_match() {
    local needle="$1" list="$2" item
    [ -n "$list" ] || return 1
    IFS=',' read -r -a items <<< "$list"
    for item in "${items[@]}"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1; shift ;;
        -u|--update) DO_UPDATE=1; shift ;;
        -o|--only) [[ $# -ge 2 ]] || die "missing value for $1"; ONLY="$2"; shift 2 ;;
        -s|--skip) [[ $# -ge 2 ]] || die "missing value for $1"; SKIP="$2"; shift 2 ;;
        -x|--extra-args) [[ $# -ge 2 ]] || die "missing value for $1"; read -r -a EXTRA <<< "$2"; shift 2 ;;
        --fail-fast) FAIL_FAST=1; shift ;;
        -l|--list) DO_LIST=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"

OS_NAME="$(detect_os)"
case "$OS_NAME" in
    wsl) OS_MATCH="linux" ;;
    *) OS_MATCH="$OS_NAME" ;;
esac

if [[ $DO_LIST -eq 1 ]]; then
    printf '%-6s %-24s %-32s %-8s %s\n' order name path branch deploy
    while IFS=$'\t' read -r order name path branch deploy os_field args_field; do
        os_field="${os_field%$'\r'}"
        case ",$os_field," in
            *",$OS_MATCH,"*) printf '%-6s %-24s %-32s %-8s %s\n' "$order" "$name" "$path" "$branch" "$deploy" ;;
        esac
    done < <(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST")
    exit 0
fi

if [[ $DO_UPDATE -eq 1 ]]; then
    "$SCRIPT_DIR/sync.sh"
fi

total=0 ok=0 failed=0 skipped=0
failed_names=()

while IFS=$'\t' read -r order name path branch deploy os_field args_field; do
    os_field="${os_field%$'\r'}"
    args_field="${args_field%$'\r'}"
    [ -n "${name:-}" ] || continue

    if list_match "$name" "$ONLY" || list_match "$path" "$ONLY"; then :; elif [ -n "$ONLY" ]; then
        continue
    fi
    if list_match "$name" "$SKIP" || list_match "$path" "$SKIP"; then
        continue
    fi

    total=$((total + 1))

    if ! list_match "$OS_MATCH" "${os_field//[[:space:]]/}"; then
        printf '[%d] %-24s skip (os: %s)\n' "$total" "$name" "$os_field"
        skipped=$((skipped + 1))
        continue
    fi

    if [ "$deploy" = "-" ] || [ -z "$deploy" ]; then
        printf '[%d] %-24s skip (no deploy script)\n' "$total" "$name"
        skipped=$((skipped + 1))
        continue
    fi

    repo_dir="$HUB_DIR/$path"
    if [ ! -d "$repo_dir" ]; then
        printf '[%d] %-24s FAIL (not cloned: %s)\n' "$total" "$name" "$path"
        failed=$((failed + 1)); failed_names+=("$name")
        [ "$FAIL_FAST" -eq 1 ] && break
        continue
    fi

    script="$repo_dir/$deploy"
    if [ ! -f "$script" ]; then
        printf '[%d] %-24s FAIL (missing %s)\n' "$total" "$name" "$deploy"
        failed=$((failed + 1)); failed_names+=("$name")
        [ "$FAIL_FAST" -eq 1 ] && break
        continue
    fi

    dargs=()
    if [ "$args_field" != "-" ] && [ -n "$args_field" ]; then
        read -r -a dargs <<< "$args_field"
    fi

    rev="$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    printf '\n==> [%d] %s (%s @ %s)\n' "$total" "$name" "$path" "$rev"

    if [ "$DRY_RUN" -eq 1 ]; then
        cmd_args="${dargs[*]:-}${EXTRA[*]:+ ${EXTRA[*]}}"
        printf '    [dry-run] cd %s && bash %s%s\n' "$path" "$deploy" "${cmd_args:+ $cmd_args}"
        ok=$((ok + 1))
        continue
    fi

    if ( cd "$repo_dir" && bash "./$deploy" "${dargs[@]}" "${EXTRA[@]}" ); then
        ok=$((ok + 1))
    else
        printf '    FAIL: %s/scripts deploy exited non-zero\n' "$name" >&2
        failed=$((failed + 1)); failed_names+=("$name")
        [ "$FAIL_FAST" -eq 1 ] && break
    fi
done < <(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST")

printf '\n---- summary ----\n'
printf 'ok: %d  failed: %d  skipped: %d  total: %d\n' "$ok" "$failed" "$skipped" "$total"
if [ "$failed" -gt 0 ]; then
    printf 'failed: %s\n' "${failed_names[*]}" >&2
    printf 'hint: pass --extra-args "-b" (backup) or "-r" (remove) if a script refused an existing config\n' >&2
    exit 1
fi
