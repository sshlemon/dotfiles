#!/usr/bin/env bash
#
# install.sh - bootstrap this dotfiles repo on a Fedora machine.
#
# Installs: Dank Linux (DMS) packages, tar, nvim (+ LazyVim deps), oh-my-zsh,
# fastfetch and powerlevel10k, then loads the dotfiles in this repo into $HOME.
#
# Usage:
#   ./install.sh                 # full install, dotfiles symlinked into $HOME
#   ./install.sh --dry-run       # show what would happen, change nothing
#   ./install.sh --copy          # copy dotfiles instead of symlinking them
#   ./install.sh --only link     # packages|shell|fastfetch|link (repeatable)
#   ./install.sh --with-greeter  # also install dms-greeter (greetd login screen)
#   ./install.sh --yes           # assume yes, do not prompt (also chsh)
#
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
OMZ_CUSTOM="$ZSH_DIR/custom"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
DRY_RUN=0
COPY_MODE=0
ASSUME_YES=0
WITH_GREETER=0
STEPS=()

usage() {
  cat <<'EOF'
Bootstrap this dotfiles repo on Fedora.

Installs Dank Linux (DMS), tar, nvim (+ LazyVim deps), oh-my-zsh,
fastfetch and powerlevel10k, then loads these dotfiles into $HOME.

Usage: ./install.sh [options]

  -n, --dry-run      show what would happen, change nothing
      --copy         copy dotfiles instead of symlinking them
      --link         symlink dotfiles (default)
      --only STEP    run just one step: packages|shell|fastfetch|link
                     (repeatable, e.g. --only packages --only link)
      --with-greeter also install dms-greeter (greetd login screen)
  -y, --yes          never prompt (implies chsh to zsh)
  -h, --help         show this help
EOF
  exit "${1:-0}"
}

while (($#)); do
  case "$1" in
    -n|--dry-run)     DRY_RUN=1 ;;
    --copy)           COPY_MODE=1 ;;
    --link)           COPY_MODE=0 ;;
    -y|--yes)         ASSUME_YES=1 ;;
    --with-greeter)   WITH_GREETER=1 ;;
    --only)           shift; [[ $# ]] || { echo "--only needs a value" >&2; exit 2; }
                      STEPS+=("$1") ;;
    -h|--help)        usage 0 ;;
    *)                echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

((${#STEPS[@]})) || STEPS=(packages shell fastfetch link)

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'
else
  C_RESET="" C_BLUE="" C_GREEN="" C_YELLOW="" C_RED=""
fi

step() { printf '\n%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '  · %s\n' "$*"; }
warn() { printf '%s  ! %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
die()  { printf '%s  ✗ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 1; }

# run <cmd...> - execute, or print only, when --dry-run is active
run() {
  if ((DRY_RUN)); then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

want_step() {
  local s
  for s in "${STEPS[@]}"; do [[ "$s" == "$1" ]] && return 0; done
  return 1
}

# mkdir -p, but only when needed and only once per directory (keeps dry-run quiet)
declare -A _MADE_DIRS=()
ensure_dir() { # <dir>
  local d="$1"
  [[ -n "$d" && ! -d "$d" && -z "${_MADE_DIRS[$d]:-}" ]] || return 0
  _MADE_DIRS[$d]=1
  run mkdir -p -- "$d"
}

confirm() {
  ((ASSUME_YES)) && return 0
  [[ -t 0 ]] || return 1
  local reply
  read -r -p "  $1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
preflight() {
  step "Preflight"

  [[ -f /etc/os-release ]] || die "cannot read /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != fedora ]]; then
    warn "this script targets Fedora, detected '${ID:-unknown}'"
    confirm "continue anyway?" || die "aborted"
  else
    ok "${PRETTY_NAME:-Fedora}"
  fi

  command -v dnf >/dev/null || die "dnf not found; run this on Fedora"

  local s
  for s in "${STEPS[@]}"; do
    case "$s" in
      packages|shell|fastfetch|link) ;;
      *) die "unknown step '$s' (expected: packages, shell, fastfetch, link)" ;;
    esac
  done

  if ((DRY_RUN == 0)) && ! ((EUID == 0)) && ! command -v sudo >/dev/null; then
    die "sudo is required to install packages (or run as root)"
  fi
  ok "repo: $REPO_DIR"
  ((COPY_MODE)) && info "mode: copy" || info "mode: symlink"
  if ((DRY_RUN)); then info "dry-run: no changes will be made"; fi
}

# as_root <cmd...>
as_root() {
  if ((EUID == 0)); then run "$@"; else run sudo "$@"; fi
}

# ---------------------------------------------------------------------------
# Packages: Dank Linux, nvim + friends, tar, fastfetch
# ---------------------------------------------------------------------------
COPR_REPOS=(avengemedia/danklinux avengemedia/dms)
DANK_PKGS=(dms dms-cli danksearch quickshell)
EXTRA_PKGS=()
# LazyVim (nvim config in this repo) needs these to work out of the box.
BASE_PKGS=(tar neovim fastfetch zsh git curl dnf-plugins-core
           ripgrep fd-find gcc make unzip)

install_packages() {
  step "Packages"

  ((WITH_GREETER)) && EXTRA_PKGS+=(dms-greeter)

  # COPR repos
  local repo
  for repo in "${COPR_REPOS[@]}"; do
    # copr writes /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:<owner>:<name>.repo
    if ls /etc/yum.repos.d/ 2>/dev/null | grep -q "${repo//\//:}"; then
      ok "copr '${repo}' already enabled"
    else
      info "enabling copr '${repo}'"
      as_root dnf copr enable -y "$repo"
    fi
  done

  local pkg
  for pkg in "${BASE_PKGS[@]}" "${DANK_PKGS[@]}" ${EXTRA_PKGS[@]+"${EXTRA_PKGS[@]}"}; do
    if rpm -q --whatprovides "$pkg" >/dev/null 2>&1 || rpm -q "$pkg" >/dev/null 2>&1; then
      ok "$pkg already installed"
    else
      info "installing $pkg"
      as_root dnf install -y "$pkg"
    fi
  done
}

# ---------------------------------------------------------------------------
# Shell: oh-my-zsh, powerlevel10k, zsh plugins
# ---------------------------------------------------------------------------
clone_if_missing() { # <url> <dest> <label>
  local url="$1" dest="$2" label="$3"
  if [[ -d "$dest/.git" ]]; then
    ok "$label already present"
    return
  fi
  [[ -e "$dest" ]] && { warn "$dest exists but is not a git checkout; leaving it alone"; return; }
  info "cloning $label"
  ensure_dir "$(dirname -- "$dest")"
  run git clone --depth=1 "$url" "$dest"
}

install_shell() {
  step "Shell (oh-my-zsh, powerlevel10k, plugins)"

  # Non-interactive clone: avoids the oh-my-zsh installer clobbering ~/.zshrc.
  clone_if_missing https://github.com/ohmyzsh/ohmyzsh.git "$ZSH_DIR" "oh-my-zsh"
  clone_if_missing https://github.com/romkatv/powerlevel10k.git \
    "$OMZ_CUSTOM/themes/powerlevel10k" "powerlevel10k"

  # Plugins referenced by plugins=(...) in .zshrc
  clone_if_missing https://github.com/zsh-users/zsh-autosuggestions.git \
    "$OMZ_CUSTOM/plugins/zsh-autosuggestions" "zsh-autosuggestions"
  clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$OMZ_CUSTOM/plugins/zsh-syntax-highlighting" "zsh-syntax-highlighting"

  # Make zsh the login shell so the config is actually used.
  local zsh_bin current
  zsh_bin="$(command -v zsh || true)"
  current="$(getent passwd "$(id -un)" | cut -d: -f7)"
  if [[ -z "$zsh_bin" ]]; then
    warn "zsh not found in PATH; skipping chsh"
  elif [[ "$current" == "$zsh_bin" ]]; then
    ok "login shell is already $zsh_bin"
  elif confirm "set $zsh_bin as login shell for $(id -un)?"; then
    info "changing login shell"
    if ((DRY_RUN)); then
      printf '  [dry-run] chsh -s %s %s\n' "$zsh_bin" "$(id -un)"
    else
      chsh -s "$zsh_bin" "$(id -un)" || warn "chsh failed; run 'chsh -s $zsh_bin' manually"
    fi
  else
    info "skipped chsh (log in with: $zsh_bin)"
  fi
}

# ---------------------------------------------------------------------------
# fastfetch presets (the .zshrc runs: fastfetch --config os/fedora)
# ---------------------------------------------------------------------------
install_fastfetch() {
  step "fastfetch presets"
  local src="$REPO_DIR/.local/share/fastfetch" dest="$HOME/.local/share/fastfetch"
  if [[ -f "$dest/presets/os/fedora.jsonc" ]]; then
    ok "presets already available"
  elif [[ -f "$src/presets/os/fedora.jsonc" ]]; then
    ok "presets are part of this repo; will be linked in the dotfiles step"
  else
    warn "no presets found at $src; 'fastfetch --config os/fedora' will fail"
  fi
  local nerd="MesloLGS NF"
  command -v fc-list >/dev/null && fc-list 2>/dev/null | grep -qi 'nerd font' \
    && nerd="a Nerd Font"
  info "powerlevel10k icons need $nerd (not installed automatically)"
}

# ---------------------------------------------------------------------------
# Dotfiles: link/copy the repo tree into $HOME
# ---------------------------------------------------------------------------
BACKUP_DIR=""

backup_path() { # <relative-path>
  local rel="$1"
  [[ -n "$BACKUP_DIR" ]] || BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
  local target="$BACKUP_DIR/$rel"
  ensure_dir "$(dirname -- "$target")"
  run mv "$HOME/$rel" "$target"
  info "backed up existing $rel -> $BACKUP_DIR/$rel"
}

# Files this repo owns inside $HOME: tracked files under .zshrc, .config and .local.
# Untracked/runtime state (PIDs, sockets, plugin checkouts, secrets) is left alone.
repo_files() {
  local paths=(.zshrc .config .local)

  if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$REPO_DIR" ls-files -z -- "${paths[@]}" | tr '\0' '\n'
    return
  fi

  # No git metadata (e.g. a downloaded tarball): walk the tree but honour .gitignore.
  local prune=() negate=() line
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"   # ltrim
    line="${line%"${line##*[![:space:]]}"}"   # rtrim
    [[ -n "$line" ]] || continue
    if [[ "$line" == !* ]]; then
      negate+=("${line#!}")
    else
      prune+=("${line%/\*}")
    fi
  done < <([[ -f "$REPO_DIR/.gitignore" ]] && cat "$REPO_DIR/.gitignore")

  local f p n skip
  while IFS= read -r f; do
    f="${f#./}"
    skip=0
    for p in .git "${prune[@]}"; do
      [[ "$f" == "$p" || "$f" == "$p"/* ]] && skip=1
    done
    for n in "${negate[@]}"; do
      [[ "$f" == "$n" ]] && skip=0
    done
    ((skip)) || printf '%s\n' "$f"
  done < <(cd "$REPO_DIR" && find "${paths[@]}" -type f 2>/dev/null)
}

apply_dotfiles() {
  step "Dotfiles -> $HOME"
  ((COPY_MODE)) && info "copying files (repo stays untouched)" \
                 || info "symlinking files into $HOME (repo is the source of truth)"

  local rel src dest n=0
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    src="$REPO_DIR/$rel"
    dest="$HOME/$rel"
    [[ -e "$src" ]] || continue

    # already linked to this repo?
    if [[ -L "$dest" ]] && [[ "$(readlink -f -- "$dest")" == "$(readlink -f -- "$src")" ]]; then
      n=$((n + 1))
      continue
    fi

    # something of the user's own lives there -> move it aside first
    [[ -e "$dest" || -L "$dest" ]] && backup_path "$rel"

    ensure_dir "$(dirname -- "$dest")"
    if ((COPY_MODE)); then
      run cp -a -- "$src" "$dest"
    else
      run ln -s -- "$src" "$dest"
    fi
    n=$((n + 1))
  done < <(repo_files)

  ok "$n file(s) handled"
  if [[ -n "$BACKUP_DIR" ]]; then
    ((DRY_RUN)) && info "backups would go to: $BACKUP_DIR" || info "backups: $BACKUP_DIR"
  fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
summary() {
  step "Done"
  cat <<EOF
  Next steps:
    1. Start a new zsh session (or run: exec zsh).
    2. Run 'p10k configure' to build ~/.p10k.zsh (not tracked in this repo).
    3. Install a Nerd Font in your terminal so powerlevel10k renders.
    4. nvim bootstraps LazyVim on first launch (needs network).
EOF
  if [[ "$HOME" != "/home/user" ]]; then
    warn "this repo's .zshrc hardcodes /home/user/... paths;"
    warn "edit $( [[ $COPY_MODE == 1 ]] && echo "$HOME/.zshrc" || echo "$REPO_DIR/.zshrc" ) for user '$(id -un)'."
  fi
}

# ---------------------------------------------------------------------------
main() {
  preflight
  want_step packages  && install_packages
  want_step shell     && install_shell
  want_step fastfetch && install_fastfetch
  want_step link      && apply_dotfiles
  summary
}

main "$@"
