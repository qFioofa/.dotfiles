# .dotfiles

Hub repository for every qFioofa configuration. It tracks the individual
config repos as git submodules and provides one command to update them and one
command to deploy them.

## Layout

```
.dotfiles/
├── .gitmodules        submodule list (url, path, branch)
├── repos/             one submodule per config repository
├── config/repos.tsv   deploy order, OS support, flags
└── scripts/
    ├── bootstrap.sh   clone the hub with submodules on a new machine
    ├── sync.sh        move submodules to their latest upstream commit
    ├── status.sh      show hub / upstream / local-clone divergence
    ├── deploy.sh      deploy every repo (Linux/macOS/WSL)
    └── deploy.ps1     deploy every repo (Windows)
```

`repos/` holds read-only mirrors. Edit and push in the standalone clones
(`~/qf/<name>`); this hub pulls their latest commits. Submodule URLs use HTTPS
so CI and new machines work without SSH keys.

## Usage

```sh
# update all submodules to the latest upstream commit (pointers not committed)
./scripts/sync.sh

# update and record the new pointers in this repo
./scripts/sync.sh --commit

# update, commit and push
./scripts/sync.sh --push

# see what is pushed, ahead or behind
./scripts/status.sh --fetch

# deploy everything for this OS
./scripts/deploy.sh

# deploy selected repos, with a dry run first
./scripts/deploy.sh --dry-run --only nvim,zsh

# force a clean reinstall for scripts that accept -r
./scripts/deploy.sh --extra-args "-r"

# new machine
./scripts/bootstrap.sh
```

`deploy.sh` reads `config/repos.tsv`, skips entries that do not support the
current OS, and runs each repo's deploy script from inside that repo. The `cd`
matters because several deploy scripts resolve paths from the current directory.

## Auto-update

`.github/workflows/sync-submodules.yml` runs daily (and on demand). It fetches
the latest commit of every submodule, records the new pointers, and pushes a
single commit to this repo. No change means no commit.

Requirements:

- Actions workflow permissions must allow writes: **Settings → Actions →
  General → Workflow permissions → Read and write**.
- `main` must accept pushes from `github-actions[bot]` (no required review on
  the bot commit).
- A scheduled workflow in a public repo pauses after 60 days without commits.
  The daily sync keeps it active; use **Run workflow** to wake it manually.

## Adding a configuration

```sh
git submodule add -b <branch> git@github.com:qFioofa/<repo>.git repos/<name>
# add a row to config/repos.tsv (order, name, path, branch, deploy, os, args)
./scripts/deploy.sh --list
```

## Notes

- `os` is a comma list: `linux`, `darwin`, `win`. WSL matches `linux`.
- `args` holds flags passed to that repo's deploy script (`-` means none).
  Scripts that refuse an existing config use `-b` (backup) here.
- `qFioofa` (profile README) is intentionally not tracked.
- `physical-keyboard.nvim` tracks the `develop` branch.

## Pending upstream pushes

These local repos are not fully represented on GitHub yet, so the hub cannot
deploy them until the first push happens:

- `qFioofa-StarShip`: `scripts/` and `starship.toml` are still untracked
  locally, so the remote has no deploy script. Commit and push in `~/qf/starship`;
  its manifest row in `config/repos.tsv` is commented out until then.
- `qFioofa-Tele`: the remote repository is empty. Its manifest row in
  `config/repos.tsv` is commented out until the first push.
