#!/usr/bin/env bash
#
# install.sh - bootstrap this dotfiles repo on a Fedora machine.
#
# Installs the Dank Linux desktop (DankMaterialShell) with its official
# installer, plus herdr, OpenCode v2, ai-jail, tar, nvim (+ LazyVim deps),
# oh-my-zsh, fastfetch, powerlevel10k and a Nerd Font, then loads the dotfiles
# in this repo into $HOME.
#
# Usage:
#   ./install.sh            # install everything, symlink dotfiles into $HOME
#   ./install.sh --dry-run  # show what would happen, change nothing
#
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
OMZ_CUSTOM="$ZSH_DIR/custom"
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"

# Where the installers below drop their binaries; make them visible to this script.
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

# MesloLGS NF is the font powerlevel10k is designed around (see font.md in the
# bundled theme). Fedora has no Nerd Font package, so it is fetched directly.
FONT_BASE_URL="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20"

DRY_RUN=0

usage() {
  cat <<'EOF'
Bootstrap this dotfiles repo on Fedora.

Installs Dank Linux (DMS + greeter), ghostty, herdr (+ the vim-herdr-navigation
plugin), OpenCode v2, ai-jail, tar, nvim, oh-my-zsh, fastfetch, powerlevel10k
and MesloLGS NF, then links these dotfiles into $HOME.

Usage: ./install.sh [-n|--dry-run] [-h|--help]
EOF
  exit "${1:-0}"
}

while (($#)); do
  case "$1" in
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help)    usage 0 ;;
    *)            echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Helpers
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

# as_root <cmd...>
as_root() { run sudo "$@"; }

# mkdir -p, but only when needed and only once per directory (keeps dry-run quiet)
declare -A _MADE_DIRS=()
ensure_dir() { # <dir>
  local d="$1"
  [[ -n "$d" && ! -d "$d" && -z "${_MADE_DIRS[$d]:-}" ]] || return 0
  _MADE_DIRS[$d]=1
  run mkdir -p -- "$d"
}

BACKUP_DIR=""
backup_path() { # <absolute-path>
  local path="$1"
  [[ -n "$BACKUP_DIR" ]] || BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
  local target="$BACKUP_DIR/${path#"$HOME"/}"
  ensure_dir "$(dirname -- "$target")"
  run mv -- "$path" "$target"
  info "backed up $path -> $target"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
preflight() {
  step "Preflight"

  local id=""
  [[ -f /etc/os-release ]] && id="$(. /etc/os-release && echo "$ID")"
  [[ "$id" == fedora ]] || die "this script targets Fedora (detected: ${id:-unknown})"
  command -v dnf >/dev/null || die "dnf not found"
  ((EUID != 0)) || die "run this as your normal user; the Dank Linux installer refuses to run as root"
  command -v sudo >/dev/null || die "sudo is required"
  ok "Fedora, repo: $REPO_DIR"
  ((DRY_RUN)) || return 0
  info "dry-run: no changes will be made"
}

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------
# What the Dank stack has to have before we consider it installed.
DANK_MARKERS=(dms dms-cli dms-greeter ghostty)
# Official Dank Linux installer; brings in DMS plus its deps.
DANK_INSTALLER_URL="https://install.danklinux.com"
# This desktop is built around Hyprland + ghostty. dankinstall needs both for
# unattended mode (their COPRs and packages are its business, not ours).
COMPOSITOR=hyprland
TERMINAL=ghostty
# tar, nvim + what LazyVim needs, fonts for the shell prompt, and bubblewrap
# (ai-jail's Linux sandbox backend).
# zoxide is used by the eval in .zshrc.
BASE_PKGS=(tar neovim fastfetch zsh git curl zoxide dnf-plugins-core fontconfig
           ripgrep fd-find gcc make unzip google-noto-color-emoji-fonts
           bubblewrap)

install_packages() {
  step "Packages"

  local pkg
  for pkg in "${BASE_PKGS[@]}"; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
      ok "$pkg already installed"
    else
      info "installing $pkg"
      as_root dnf install -y "$pkg"
    fi
  done

  install_dank_linux

  if command -v bwrap >/dev/null 2>&1; then
    ok "bubblewrap present (ai-jail's Linux backend)"
  else
    warn "bubblewrap missing; ai-jail needs it to sandbox"
  fi
}

install_dank_linux() {
  local pkg missing=0
  for pkg in "${DANK_MARKERS[@]}"; do
    rpm -q "$pkg" >/dev/null 2>&1 || missing=1
  done
  if ((missing == 0)); then
    ok "Dank Linux already installed (${DANK_MARKERS[*]})"
    return
  fi

  # Prime sudo so the installer's headless mode has cached credentials.
  as_root -v

  # --compositor and --term together switch it to unattended mode; -y confirms.
  # Deliberately no --replace-configs*: this repo owns ~/.config, and the
  # dotfiles step below puts its own configs in place.
  info "installing Dank Linux (compositor: $COMPOSITOR, terminal: $TERMINAL)"
  run sh -c "curl -fsSL $DANK_INSTALLER_URL | sh -s -- \
--compositor $COMPOSITOR --term $TERMINAL -y --dms-greeter --danksearch"
}

# ---------------------------------------------------------------------------
# Fonts: MesloLGS NF (powerlevel10k) - emoji font comes with BASE_PKGS
# ---------------------------------------------------------------------------
install_fonts() {
  step "Fonts"

  if command -v fc-list >/dev/null && fc-list 2>/dev/null | grep -qi 'MesloLGS NF'; then
    ok "MesloLGS NF already installed"
    return
  fi

  ensure_dir "$FONT_DIR"
  local variant encoded file
  for variant in Regular Bold Italic "Bold Italic"; do
    encoded="${variant// /%20}"
    file="MesloLGS NF $variant.ttf"
    if [[ -f "$FONT_DIR/$file" ]]; then
      ok "$file already downloaded"
      continue
    fi
    info "downloading $file"
    run curl -fsSL --retry 3 -o "$FONT_DIR/$file" "$FONT_BASE_URL$encoded.ttf"
  done
  run fc-cache -f "$FONT_DIR"
  ok "MesloLGS NF available (set it as your terminal font)"
}

# ---------------------------------------------------------------------------
# Shell: oh-my-zsh + powerlevel10k and plugins from this repo
# ---------------------------------------------------------------------------
clone_if_missing() { # <url> <dest> <label>
  local url="$1" dest="$2" label="$3"
  if [[ -d "$dest/.git" ]]; then
    ok "$label already present"
    return
  fi
  info "cloning $label"
  ensure_dir "$(dirname -- "$dest")"
  run git clone --depth=1 "$url" "$dest"
}

# Powerlevel10k and zsh-autosuggestions already live in this repo, so use those
# instead of cloning them again. Only clone when a fresh checkout has no content.
use_from_repo_or_clone() { # <repo-rel-dir> <dest> <marker-file> <url> <label>
  local rel="$1" dest="$2" marker="$3" url="$4" label="$5"
  local src="$REPO_DIR/$rel"

  [[ -f "$src/$marker" ]] || { clone_if_missing "$url" "$dest" "$label"; return; }

  if [[ -L "$dest" ]] && [[ "$(readlink -f -- "$dest")" == "$(readlink -f -- "$src")" ]]; then
    ok "$label already linked from dotfiles"
    return
  fi
  [[ -e "$dest" || -L "$dest" ]] && backup_path "$dest"
  ensure_dir "$(dirname -- "$dest")"
  run ln -s -- "$src" "$dest"
  ok "$label linked from dotfiles"
}

install_shell() {
  step "Shell (oh-my-zsh, powerlevel10k, plugins)"

  # Plain clone: the oh-my-zsh installer would overwrite ~/.zshrc.
  if [[ -d "$ZSH_DIR/.git" ]]; then
    ok "oh-my-zsh already present"
  else
    info "cloning oh-my-zsh"
    ensure_dir "$(dirname -- "$ZSH_DIR")"
    run git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$ZSH_DIR"
  fi

  use_from_repo_or_clone .oh-my-zsh/custom/themes/powerlevel10k \
    "$OMZ_CUSTOM/themes/powerlevel10k" powerlevel10k.zsh-theme \
    https://github.com/romkatv/powerlevel10k.git powerlevel10k

  use_from_repo_or_clone .oh-my-zsh/custom/plugins/zsh-autosuggestions \
    "$OMZ_CUSTOM/plugins/zsh-autosuggestions" zsh-autosuggestions.plugin.zsh \
    https://github.com/zsh-users/zsh-autosuggestions.git zsh-autosuggestions

  # Not in the repo, so always cloned. Referenced by plugins=(...) in .zshrc.
  clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$OMZ_CUSTOM/plugins/zsh-syntax-highlighting" zsh-syntax-highlighting

  # Make zsh the login shell so the config is actually used.
  local zsh_bin current
  zsh_bin="$(command -v zsh || true)"
  current="$(getent passwd "$(id -un)" | cut -d: -f7)"
  if [[ -z "$zsh_bin" ]]; then
    warn "zsh not found in PATH; skipping chsh"
  elif [[ "$current" == "$zsh_bin" ]]; then
    ok "login shell is already $zsh_bin"
  else
    info "setting login shell to $zsh_bin"
    run chsh -s "$zsh_bin" "$(id -un)" || warn "chsh failed; run 'chsh -s $zsh_bin' manually"
  fi
}

# ---------------------------------------------------------------------------
# Dotfiles: symlink the repo tree into $HOME
# ---------------------------------------------------------------------------
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

link_dotfiles() {
  step "Dotfiles -> $HOME"

  local rel src dest n=0
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    src="$REPO_DIR/$rel"
    dest="$HOME/$rel"
    [[ -e "$src" ]] || continue

    if [[ -L "$dest" ]] && [[ "$(readlink -f -- "$dest")" == "$(readlink -f -- "$src")" ]]; then
      n=$((n + 1))
      continue
    fi

    # something of the user's own lives there -> move it aside first
    [[ -e "$dest" || -L "$dest" ]] && backup_path "$dest"

    ensure_dir "$(dirname -- "$dest")"
    run ln -s -- "$src" "$dest"
    n=$((n + 1))
  done < <(repo_files)

  ok "$n file(s) linked"
  if [[ -n "$BACKUP_DIR" ]]; then
    ((DRY_RUN)) && info "backups would go to: $BACKUP_DIR" || info "backups: $BACKUP_DIR"
  fi

  # .zshrc runs: fastfetch --config os/fedora
  if ((DRY_RUN)); then
    info "fastfetch preset os/fedora: verified once linked"
  elif [[ -f "$HOME/.local/share/fastfetch/presets/os/fedora.jsonc" ]]; then
    ok "fastfetch preset os/fedora available"
  else
    warn "fastfetch preset os/fedora is missing; 'fastfetch --config os/fedora' will fail"
  fi
}

# ---------------------------------------------------------------------------
# Tools: herdr (+ its vim navigation plugin), OpenCode v2 and ai-jail
# ---------------------------------------------------------------------------
# The plugin's actions are bound to ctrl+h/j/k/l in ~/.config/herdr/config.toml,
# so this step runs after the dotfiles are in place.
HERDR_PLUGIN="paulbkim-dev/vim-herdr-navigation"
# ai-jail publishes prebuilt release binaries, so no Rust toolchain is needed.
AI_JAIL_REPO="akitaonrails/ai-jail"

install_tools() {
  step "Agent tools"
  local plugin="${HERDR_PLUGIN##*/}"

  if command -v herdr >/dev/null 2>&1; then
    ok "herdr already installed ($(herdr --version 2>/dev/null))"
  else
    info "installing herdr"
    run sh -c "curl -fsSL https://herdr.dev/install.sh | sh"
  fi

  local oc_version=""
  if command -v opencode >/dev/null 2>&1; then
    oc_version="$(opencode --version 2>/dev/null)"
    oc_version="${oc_version##* }"   # "opencode v2.0.29" -> "v2.0.29"
  fi
  if [[ "$oc_version" == v2* ]]; then
    ok "OpenCode already installed ($oc_version)"
  elif [[ -n "$oc_version" ]]; then
    warn "found OpenCode $oc_version; this repo expects v2"
  else
    info "installing OpenCode v2"
    run bash -c "curl -fsSL https://opencode.ai/v2/install | bash"
  fi

  install_ai_jail

  if ! command -v herdr >/dev/null 2>&1; then
    warn "herdr is not on PATH; skipping the $plugin plugin"
    return
  fi
  if herdr plugin list 2>/dev/null | grep -q "$plugin"; then
    ok "$plugin plugin already installed"
  else
    info "installing herdr plugin $HERDR_PLUGIN"
    run herdr plugin install -y "$HERDR_PLUGIN"
  fi
}

install_ai_jail() {
  if command -v ai-jail >/dev/null 2>&1; then
    ok "ai-jail already installed ($(ai-jail --version 2>/dev/null))"
    return
  fi
  if [[ "$(uname -m)" != x86_64 ]]; then
    warn "no prebuilt ai-jail for $(uname -m); use 'cargo install --locked ai-jail'"
    return
  fi

  local asset="ai-jail-linux-x86_64.tar.gz"
  local base="https://github.com/$AI_JAIL_REPO/releases/latest/download"
  local tmp
  if ((DRY_RUN)); then
    tmp="${TMPDIR:-/tmp}/ai-jail-install.$$"
  else
    tmp="$(mktemp -d)"
  fi

  info "installing ai-jail"
  ensure_dir "$tmp"
  run curl -fsSL -o "$tmp/$asset" "$base/$asset"
  run curl -fsSL -o "$tmp/$asset.sha256" "$base/$asset.sha256"

  if ((DRY_RUN)); then
    info "the download is verified against the published .sha256"
  else
    local expected actual
    expected="$(awk '{print $1}' "$tmp/$asset.sha256")"
    actual="$(sha256sum "$tmp/$asset" | awk '{print $1}')"
    if [[ -z "$expected" || "$expected" != "$actual" ]]; then
      rm -rf "$tmp"
      die "ai-jail checksum mismatch (expected '${expected:-none}', got '$actual')"
    fi
  fi

  run tar -xzf "$tmp/$asset" -C "$tmp"
  ensure_dir "$HOME/.local/bin"
  run install -m755 "$tmp/ai-jail" "$HOME/.local/bin/ai-jail"
  run rm -rf "$tmp"
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
    3. Set your terminal font to "MesloLGS NF".
    4. nvim bootstraps LazyVim on first launch (needs network).
    5. cd into a project and run 'herdr'; run 'opencode' and use /connect for a provider.
EOF
  if [[ "$HOME" != "/home/user" ]]; then
    warn "this repo's .zshrc hardcodes /home/user/... paths;"
    warn "edit $REPO_DIR/.zshrc for user '$(id -un)'."
  fi
}

# ---------------------------------------------------------------------------
main() {
  preflight
  install_packages
  install_fonts
  install_shell
  link_dotfiles
  install_tools
  summary
}

main "$@"
