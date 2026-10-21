#!/usr/bin/env bash
# =============================================================================
# DEPLOY.sh — Configuration ZSH à thèmes + starter pack d'outils
# Usage  : bash DEPLOY.sh [-y] [--theme NOM] [--stack full|none|a,b,c] [-h]
# Shells : lançable depuis bash, zsh ou sh (se relance automatiquement sous bash)
# OS     : Debian/Ubuntu et dérivés, Fedora/RHEL et dérivés (détection
#          automatique via /etc/os-release), macOS. Arch/openSUSE/Alpine :
#          partie ZSH uniquement.
# Arch   : x86_64 et arm64 (VM sur Mac Apple Silicon comprises)
#
# Déroulé :
#   Phase 0 — Reconnaissance : OS, famille, architecture, gestionnaire de
#             paquets, prérequis (zsh, git, curl, couleurs 256)
#   Phase 1 — Choix : thème ZSH, starter pack (complet, à la carte ou aucun)
#   Phase 2 — ZSH : prérequis, plugins, ~/.zshrc, shell par défaut
#   Phase 3 — Starter pack : installation outil par outil, un échec n'arrête
#             pas les suivants, bilan final
#
# Les binaires téléchargés hors gestionnaire de paquets (Node, Go, kubectl,
# uv, PowerShell) sont vérifiés par SHA-256 avant installation.
# =============================================================================

# Relance sous bash si lancé via sh/zsh (tableaux et `local` requis)
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

# -E : le trap ERR s'applique aussi dans les fonctions
# pipefail : l'échec d'une commande au milieu d'un pipe n'est plus masqué
set -Eeo pipefail

# -----------------------------------------------------------------------------
# Couleurs (désactivées si le terminal ne les supporte pas)
# -----------------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

info()    { printf "${CYAN}▸ %s${NC}\n" "$*"; }
success() { printf "${GREEN}✅ %s${NC}\n" "$*"; }
warn()    { printf "${YELLOW}⚠️  %s${NC}\n" "$*"; }
error()   { printf "${RED}❌ %s${NC}\n" "$*" >&2; }
header()  { printf "\n${CYAN}══════════════════════════════════════════\n  %s\n══════════════════════════════════════════${NC}\n\n" "$*"; }

# =============================================================================
# CATALOGUE — thèmes et starter pack
# =============================================================================

# Thèmes : 4 codes 256 couleurs = début · milieu · fin du dégradé · chemin.
# À garder synchronisé avec ZSH_THEMES dans le ~/.zshrc embarqué plus bas.
THEME_LIST=(sunlight military cyberpunk)

theme_colors() {
    case "$1" in
        sunlight)  echo "166 214 220 39" ;;
        military)  echo "58 112 65 112" ;;
        cyberpunk) echo "67 117 51 51" ;;
    esac
}

theme_label() {
    case "$1" in
        sunlight)  echo "orange sombre → orange clair → jaune, chemin en bleu vif" ;;
        military)  echo "vert militaire → vert pomme → vert marais" ;;
        cyberpunk) echo "bleu métallique → bleu ciel → bleu fluo" ;;
    esac
}

# Aperçu du dégradé en blocs de couleur
theme_preview() {
    local c
    for c in $(theme_colors "$1"); do
        if [ -n "$NC" ]; then printf '\033[38;5;%sm██\033[0m' "$c"; else printf '[%s]' "$c"; fi
    done
}

# Starter pack : ordre d'affichage du menu, et ordre d'installation
# (dépendances d'abord : node avant npm, go/node/gcc/gtk avant wails, uv avant tldr)
STACK_MENU=(docker kubectl git npm node golang nano tree tldr gcc uv psql wails gtk pip powershell)
STACK_ORDER=(git gcc nano tree pip psql node npm golang kubectl docker uv tldr gtk wails powershell)

stack_desc() {
    case "$1" in
        docker)     echo "Moteur de conteneurs + compose et buildx" ;;
        kubectl)    echo "CLI Kubernetes" ;;
        git)        echo "Gestion de versions" ;;
        npm)        echo "Gestionnaire de paquets JS (fourni avec Node)" ;;
        node)       echo "Node.js LTS" ;;
        golang)     echo "Go, dernière version stable" ;;
        nano)       echo "Éditeur de texte" ;;
        tree)       echo "Arborescence de dossiers" ;;
        tldr)       echo "Pages d'aide simplifiées (installé via uv)" ;;
        gcc)        echo "Compilateurs C/C++ et make" ;;
        uv)         echo "Gestionnaire Python d'Astral" ;;
        psql)       echo "Client PostgreSQL" ;;
        wails)      echo "Applications desktop Go + webview" ;;
        gtk)        echo "GTK3 + WebKitGTK (webview de Wails)" ;;
        pip)        echo "pip pour Python 3" ;;
        powershell) echo "PowerShell 7 (pwsh)" ;;
    esac
}

stack_deps() {
    case "$1" in
        npm)   echo "node" ;;
        tldr)  echo "uv" ;;
        wails) echo "golang node gcc gtk" ;;
    esac
}

# -----------------------------------------------------------------------------
# Options et mode non interactif
# -----------------------------------------------------------------------------
ASSUME_YES=0
OPT_THEME=""
OPT_STACK=""

usage() {
    cat <<'EOF'
Usage : bash DEPLOY.sh [options]
  -y, --yes            Mode non interactif : répond oui à tout, ne lance pas zsh à la fin.
                       Nécessite sudo sans mot de passe, ou une exécution en root.
  --theme NOM          sunlight | military | cyberpunk   (défaut en -y : sunlight)
  --stack CHOIX        full | none | liste séparée par des virgules (ex : docker,golang,uv)
                       (défaut en -y : none). Outils : docker kubectl git npm node golang
                       nano tree tldr gcc uv psql wails gtk pip powershell
  -h, --help           Cette aide
Variable d'environnement :
  BREW_INSTALL_SHA256  Empreinte SHA-256 attendue de l'installeur Homebrew (macOS).
                       Obligatoire en mode -y si Homebrew doit être installé.
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes)  ASSUME_YES=1 ;;
            --theme)   OPT_THEME="${2:-}"; shift ;;
            --stack)   OPT_STACK="${2:-}"; shift ;;
            -h|--help) usage; exit 0 ;;
            *)         error "Option inconnue : $1"; usage >&2; exit 1 ;;
        esac
        shift
    done

    if [ -n "$OPT_THEME" ] && [ -z "$(theme_colors "$OPT_THEME")" ]; then
        error "Thème inconnu : $OPT_THEME (sunlight | military | cyberpunk)"
        exit 1
    fi
}

# Sans terminal ni -y, échoue explicitement au lieu de laisser `read` tomber sur EOF
require_tty() {
    if [ ! -t 0 ]; then
        error "Aucun terminal interactif : relancez avec -y pour un usage automatisé."
        exit 1
    fi
}

# Question oui/non : 0 = oui. En -y répond oui.
ask() {
    if [ "$ASSUME_YES" = 1 ]; then return 0; fi
    require_tty
    local reply
    printf "%s (Y/n) : " "$1"
    read -r reply || reply=n
    case "$reply" in
        [Nn]*) return 1 ;;
        *)     return 0 ;;
    esac
}

# Élévation : vide en root (VM/conteneur sans sudo), sudo sinon
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
TARGET_USER="${USER:-$(id -un)}"

# =============================================================================
# PHASE 0 — RECONNAISSANCE
# =============================================================================

# -----------------------------------------------------------------------------
# OS, famille (debian / rhel / macos / other) et architecture
# -----------------------------------------------------------------------------
OS_FAMILY="other"
ARCH="unsupported"

detect_os() {
    OS_NAME="$(uname)"

    if [ "$OS_NAME" = "Darwin" ]; then
        OS_FAMILY="macos"
        info "OS détecté : macOS"
    else
        # Expose ID, ID_LIKE, VERSION_CODENAME, UBUNTU_CODENAME, PRETTY_NAME…
        # shellcheck disable=SC1091
        if [ -r /etc/os-release ]; then . /etc/os-release; fi
        case " ${ID:-} ${ID_LIKE:-} " in
            *" debian "*|*" ubuntu "*)            OS_FAMILY="debian" ;;
            *" rhel "*|*" fedora "*|*" centos "*) OS_FAMILY="rhel" ;;
        esac
        info "OS détecté : ${PRETTY_NAME:-Linux} — famille : $OS_FAMILY"
    fi

    case "$(uname -m)" in
        x86_64|amd64)  ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac
    info "Architecture : $(uname -m)"

    CURRENT_SHELL=$(basename "${SHELL:-unknown}")
    info "Shell par défaut actuel : $CURRENT_SHELL"
    if [ "$CURRENT_SHELL" = "zsh" ]; then
        warn "Zsh est déjà le shell par défaut — on va juste mettre à jour la config."
    fi
}

# -----------------------------------------------------------------------------
# Gestionnaire de paquets (détection seule : Homebrew n'est proposé que s'il
# manque réellement quelque chose sur macOS)
# -----------------------------------------------------------------------------
PKG_MANAGER="none"

detect_package_manager() {
    local pm
    for pm in brew apt-get dnf pacman zypper apk; do
        if command -v "$pm" >/dev/null 2>&1; then
            PKG_MANAGER="${pm%-get}"
            break
        fi
    done

    if [ "$PKG_MANAGER" = "none" ]; then
        warn "Aucun gestionnaire de paquets connu — requis seulement s'il manque des prérequis."
    else
        success "Gestionnaire de paquets : $PKG_MANAGER"
    fi
}

# Rafraîchit l'index une fois par phase (apt uniquement ; dnf le gère seul)
pkg_refresh() {
    if [ "$PKG_MANAGER" = "apt" ]; then
        $SUDO apt-get update -qq || warn "Index apt partiellement actualisé (dépôt injoignable ?)"
    fi
}

pkg_install() {
    case "$PKG_MANAGER" in
        brew)   brew install "$@" ;;
        apt)    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" ;;
        dnf)    $SUDO dnf install -y -q "$@" ;;
        # -S sans -y : pas de synchronisation partielle de la base (déconseillée sur Arch)
        pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
        zypper) $SUDO zypper --non-interactive install "$@" ;;
        apk)    $SUDO apk add "$@" ;;
        *)      error "Gestionnaire de paquets inconnu, installation manuelle requise pour : $*"; return 1 ;;
    esac
}

# Paquet dont le nom diffère entre familles : pkg_for <debian> <rhel>
pkg_for() {
    # shellcheck disable=SC2086  # découpage voulu : plusieurs paquets possibles
    if [ "$OS_FAMILY" = "debian" ]; then pkg_install $1; else pkg_install $2; fi
}

# Présence réelle d'un outil. Sur macOS, /usr/bin/git est un leurre qui ouvre
# une fenêtre d'installation tant que les Command Line Tools sont absents.
tool_present() {
    command -v "$1" >/dev/null 2>&1 || return 1
    if [ "$1" = "git" ] && [ "$OS_NAME" = "Darwin" ] && [ "$(command -v git)" = "/usr/bin/git" ]; then
        xcode-select -p >/dev/null 2>&1 || return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Audit des prérequis ZSH : zsh, git, curl. Le prompt lit RAM/CPU directement
# dans le système (/proc, sysctl) : plus besoin de bc, top ou free.
# -----------------------------------------------------------------------------
MISSING_REQUIRED=()

detect_prerequisites() {
    header "AUDIT DES PRÉREQUIS"

    local tool
    for tool in zsh git curl; do
        if tool_present "$tool"; then
            success "$tool présent ($(command -v "$tool"))"
        else
            warn "$tool absent ou inutilisable"
            MISSING_REQUIRED+=("$tool")
        fi
    done

    local colors_count
    colors_count=$(tput colors 2>/dev/null || echo 0)
    if [ "$colors_count" -ge 256 ] 2>/dev/null; then
        success "Terminal 256 couleurs détecté"
    else
        warn "Terminal limité à $colors_count couleurs : les dégradés s'afficheront de façon dégradée."
        warn "Vérifiez TERM (ex: export TERM=xterm-256color) une fois zsh actif."
    fi
}

# =============================================================================
# PHASE 1 — CHOIX
# =============================================================================

THEME="sunlight"
STACK_SELECTED=""   # liste « mot mot mot », triée dans l'ordre d'installation
STACK_ADDED_DEPS=""

choose_theme() {
    if [ -n "$OPT_THEME" ]; then THEME="$OPT_THEME"; return 0; fi
    if [ "$ASSUME_YES" = 1 ]; then return 0; fi
    require_tty

    header "THÈME ZSH"
    local i reply
    for i in "${!THEME_LIST[@]}"; do
        printf "  %d) %-10s " "$((i + 1))" "${THEME_LIST[$i]}"
        theme_preview "${THEME_LIST[$i]}"
        printf "  %s\n" "$(theme_label "${THEME_LIST[$i]}")"
    done
    printf "\n"

    while :; do
        printf "Thème [1-%d, défaut 1] : " "${#THEME_LIST[@]}"
        read -r reply || reply=""
        reply="${reply:-1}"
        if [[ "$reply" =~ ^[0-9]+$ ]] && [ "$reply" -ge 1 ] && [ "$reply" -le "${#THEME_LIST[@]}" ]; then
            THEME="${THEME_LIST[$((reply - 1))]}"
            break
        fi
        warn "Choix invalide."
    done
    success "Thème : $THEME"
}

stack_supported() {
    case "$OS_FAMILY" in
        macos)       return 0 ;;
        debian|rhel) [ "$ARCH" != "unsupported" ] ;;
        *)           return 1 ;;
    esac
}

is_stack_item() {
    case " ${STACK_MENU[*]} " in *" $1 "*) return 0 ;; esac
    return 1
}

# Ajoute les dépendances puis réordonne selon STACK_ORDER
resolve_stack() {
    local raw=" $1 " item dep
    for item in $1; do
        for dep in $(stack_deps "$item"); do
            case "$raw" in
                *" $dep "*) ;;
                *) raw="$raw$dep "; STACK_ADDED_DEPS="$STACK_ADDED_DEPS $dep" ;;
            esac
        done
    done

    STACK_SELECTED=""
    for item in "${STACK_ORDER[@]}"; do
        case "$raw" in *" $item "*) STACK_SELECTED="$STACK_SELECTED $item" ;; esac
    done
    STACK_SELECTED="${STACK_SELECTED# }"
    STACK_ADDED_DEPS="${STACK_ADDED_DEPS# }"
}

choose_stack() {
    if ! stack_supported; then
        if [ -n "$OPT_STACK" ] && [ "$OPT_STACK" != "none" ]; then
            warn "Starter pack disponible uniquement sur Debian, RHEL (x86_64/arm64) et macOS : ignoré."
        fi
        return 0
    fi

    local picked="" item

    if [ -n "$OPT_STACK" ]; then
        case "$OPT_STACK" in
            full) picked="${STACK_MENU[*]}" ;;
            none) picked="" ;;
            *)
                for item in $(printf '%s' "$OPT_STACK" | tr ',' ' '); do
                    if ! is_stack_item "$item"; then error "Outil inconnu : $item"; exit 1; fi
                    picked="$picked $item"
                done
                ;;
        esac
    elif [ "$ASSUME_YES" = 1 ]; then
        picked=""
    else
        require_tty
        header "STARTER PACK OUTILS & TECHNOS"
        local i reply
        for i in "${!STACK_MENU[@]}"; do
            printf "  %2d) %-11s %s\n" "$((i + 1))" "${STACK_MENU[$i]}" "$(stack_desc "${STACK_MENU[$i]}")"
        done
        printf "\n"

        while :; do
            printf "Installer le pack complet ? [o]ui / [n]on / [c]hoisir (défaut n) : "
            read -r reply || reply=""
            case "${reply:-n}" in
                [OoYy]*) picked="${STACK_MENU[*]}"; break ;;
                [Nn]*)   picked=""; break ;;
                [Cc]*)
                    # Redemande les numéros jusqu'à une saisie entièrement valide
                    local n ok=0
                    while [ "$ok" = 0 ]; do
                        printf "Numéros séparés par des espaces ou des virgules (ex : 1 6 11) : "
                        read -r reply || reply=""
                        picked=""; ok=1
                        for n in $(printf '%s' "$reply" | tr ',' ' '); do
                            if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#STACK_MENU[@]}" ]; then
                                picked="$picked ${STACK_MENU[$((n - 1))]}"
                            else
                                warn "Numéro invalide : $n"; ok=0
                            fi
                        done
                        if [ -z "$picked" ]; then ok=0; fi
                    done
                    break
                    ;;
                *) warn "Réponse invalide." ;;
            esac
        done
    fi

    resolve_stack "$picked"
    if [ -n "$STACK_SELECTED" ]; then
        success "Starter pack : $STACK_SELECTED"
        if [ -n "$STACK_ADDED_DEPS" ]; then info "Dépendances ajoutées : $STACK_ADDED_DEPS"; fi
    fi
}

# =============================================================================
# PHASE 2 — ZSH
# =============================================================================

# -----------------------------------------------------------------------------
# Homebrew : l'installeur est téléchargé dans un fichier, son empreinte est
# affichée et vérifiée contre BREW_INSTALL_SHA256 si fournie. Sans empreinte :
# confirmation explicite en interactif, refus en mode -y.
# -----------------------------------------------------------------------------
BREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

ensure_homebrew() {
    if [ "$PKG_MANAGER" = "brew" ]; then return 0; fi

    info "Homebrew requis : téléchargement de l'installeur (sans exécution)..."
    local installer sum brew_bin
    installer=$(mktemp)
    curl -fsSL "$BREW_INSTALL_URL" -o "$installer"
    sum=$(shasum -a 256 "$installer" | awk '{print $1}')
    info "SHA-256 de l'installeur : $sum"

    if [ -n "${BREW_INSTALL_SHA256:-}" ]; then
        if [ "$sum" != "$BREW_INSTALL_SHA256" ]; then
            rm -f "$installer"
            error "Empreinte différente de BREW_INSTALL_SHA256 : installeur refusé."
            exit 1
        fi
        success "Empreinte conforme à BREW_INSTALL_SHA256"
    elif [ "$ASSUME_YES" = 1 ]; then
        rm -f "$installer"
        error "Mode -y : installeur Homebrew non vérifiable. Définissez BREW_INSTALL_SHA256 ou préinstallez Homebrew."
        exit 1
    else
        warn "Aucune empreinte de référence : inspectez $installer avant d'accepter."
        if ! ask "Exécuter l'installeur Homebrew ?"; then
            rm -f "$installer"
            error "Homebrew est requis pour continuer sur macOS."
            exit 1
        fi
    fi

    if [ "$ASSUME_YES" = 1 ]; then
        NONINTERACTIVE=1 /bin/bash "$installer"
    else
        /bin/bash "$installer"
    fi
    rm -f "$installer"

    # L'installeur n'ajoute pas brew au PATH du shell courant (Apple Silicon : /opt/homebrew)
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$brew_bin" ]; then
            eval "$("$brew_bin" shellenv)"
            break
        fi
    done
    if ! command -v brew >/dev/null 2>&1; then
        error "Homebrew installé mais introuvable dans le PATH."
        exit 1
    fi

    PKG_MANAGER="brew"
    success "Homebrew installé"
}

install_prerequisites() {
    if [ "${#MISSING_REQUIRED[@]}" -eq 0 ]; then
        return 0
    fi

    info "Installation des prérequis manquants : ${MISSING_REQUIRED[*]}..."

    if [ "$OS_NAME" = "Darwin" ]; then
        ensure_homebrew
    elif [ "$PKG_MANAGER" = "none" ]; then
        error "Aucun gestionnaire de paquets : installez manuellement ${MISSING_REQUIRED[*]} puis relancez."
        exit 1
    else
        pkg_refresh
    fi

    pkg_install "${MISSING_REQUIRED[@]}"

    local tool still_missing=()
    for tool in "${MISSING_REQUIRED[@]}"; do
        tool_present "$tool" || still_missing+=("$tool")
    done

    if [ "${#still_missing[@]}" -gt 0 ]; then
        error "Échec d'installation pour : ${still_missing[*]} — installez-les manuellement puis relancez."
        exit 1
    fi

    success "Tous les prérequis manquants sont installés."
}

# -----------------------------------------------------------------------------
# Tâches en arrière-plan dont le statut est réellement récupéré.
# Le sous-shell désactive le trap ERR (sinon un message « Erreur ligne »
# parasite par tâche) mais garde set -e : toute commande en échec le termine
# avec un code non nul, que wait <pid> remonte ensuite.
# Attention : lancé depuis un `if`, bash ignorerait set -e dans le sous-shell ;
# c'est pourquoi le lancement reste une instruction simple, seul `wait` est testé.
# -----------------------------------------------------------------------------
BG_PIDS=()
BG_NAMES=()

spawn() {   # spawn <nom affiché> <commande...>
    local name=$1; shift
    ( trap - ERR; "$@" ) &
    BG_PIDS+=("$!")
    BG_NAMES+=("$name")
}

clone_plugin() {   # clone_plugin <dépôt> <destination>
    local repo=$1 dest=$2 name
    name=$(basename "$dest")
    if [ -d "$dest" ]; then
        success "$name déjà présent"
        return 0
    fi
    git clone --quiet --depth=1 "$repo" "$dest"
    success "$name installé"
}

GIT_PLUGIN_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/git/git.plugin.zsh"

# Plugin git : aliases oh-my-zsh (ga, gst, gco, gp, gl, gcmsg…)
fetch_git_plugin() {
    local dest=~/.zsh/plugins/git/git.plugin.zsh
    if [ -f "$dest" ]; then
        success "Plugin git déjà présent"
        return 0
    fi
    mkdir -p "${dest%/*}"
    # Fichier temporaire : un téléchargement interrompu ne laisse pas un plugin tronqué
    curl -fsSL "$GIT_PLUGIN_URL" -o "$dest.tmp"
    mv "$dest.tmp" "$dest"
    success "Plugin git installé"
}

install_plugins() {
    info "Installation des plugins Zsh (en parallèle)..."
    mkdir -p ~/.zsh/plugins
    BG_PIDS=(); BG_NAMES=()

    spawn "Syntax Highlighting" clone_plugin \
        https://github.com/zsh-users/zsh-syntax-highlighting.git \
        ~/.zsh/plugins/zsh-syntax-highlighting
    spawn "Autosuggestions" clone_plugin \
        https://github.com/zsh-users/zsh-autosuggestions \
        ~/.zsh/plugins/zsh-autosuggestions
    spawn "Enhanced Completions" clone_plugin \
        https://github.com/zsh-users/zsh-completions \
        ~/.zsh/plugins/zsh-completions
    spawn "Git aliases" fetch_git_plugin

    # wait <pid> renvoie le code de sortie de chaque tâche (wait seul renvoie toujours 0)
    local i failed=()
    for i in "${!BG_PIDS[@]}"; do
        wait "${BG_PIDS[$i]}" || failed+=("${BG_NAMES[$i]}")
    done

    if [ "${#failed[@]}" -gt 0 ]; then
        error "Échec d'installation : ${failed[*]} (réseau ?) — relancez, le script est idempotent."
        exit 1
    fi
    success "Plugins prêts"
}

# -----------------------------------------------------------------------------
# Écriture du ~/.zshrc (heredoc en 'EOF' : aucune expansion, les variables zsh
# restent littérales) et du thème choisi dans ~/.zsh/theme
# -----------------------------------------------------------------------------
write_zshrc() {
    info "Écriture de ~/.zshrc..."

    if [ -f ~/.zshrc ]; then
        local backup
        backup=~/.zshrc.backup.$(date +%Y%m%d_%H%M%S)
        cp ~/.zshrc "$backup"
        info "Ancien .zshrc sauvegardé → $backup"
    fi

    cat > ~/.zshrc << 'ZSHRC_EOF'
# Configuration ZSH — thèmes en dégradé · RAM/CPU/Disque · Git à droite
# ========================================
# CONFIGURATION DE BASE
# ========================================

autoload -U colors && colors
autoload -Uz add-zsh-hook
setopt PROMPT_SUBST AUTO_CD CORRECT EXTENDED_GLOB

HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS HIST_SAVE_NO_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS

autoload -U compinit && compinit -u

# ========================================
# CONFIGURATION VISUELLE DES FICHIERS
# ========================================

export CLICOLOR=1
export LSCOLORS=ExGxBxDxCxEgEdxbxgxcxd
export LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.zst=01;31:*.tzst=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.wim=01;31:*.swm=01;31:*.dwm=01;31:*.esd=01;31:*.jpg=01;35:*.jpeg=01;35:*.mjpg=01;35:*.mjpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.ogv=01;35:*.ogx=01;35:*.py=01;33:*.js=01;33:*.json=01;33:*.yml=01;33:*.yaml=01;33:*.toml=01;33:*.ini=01;33:*.cfg=01;33:*.conf=01;33:*.log=00;37:*.md=01;37:*.txt=00;37:*.sh=01;32:*.bash=01;32:*.zsh=01;32:*.fish=01;32'

zstyle ':completion:*' menu select
zstyle ':completion:*' group-name ''
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '%B%F{blue}── %d ──%f%b'
zstyle ':completion:*:messages' format '%F{green}%d%f'
zstyle ':completion:*:warnings' format '%F{red}No matches for: %d%f'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin

# ========================================
# THÈMES — dégradés 256 couleurs
# ========================================
# Valeurs : début · milieu · fin du dégradé · couleur du chemin
#   sunlight  : orange sombre · orange clair · jaune · bleu vif (chemin distinct)
#   military  : vert militaire · vert pomme · vert marais
#   cyberpunk : bleu métallique · bleu ciel · bleu fluo
typeset -gA ZSH_THEMES=(
    sunlight  '166 214 220 39'
    military  '58 112 65 112'
    cyberpunk '67 117 51 51'
)

_apply_theme() {
    [[ -n $1 && -n ${ZSH_THEMES[$1]} ]] || return 1
    local -a c; c=(${=ZSH_THEMES[$1]})
    T1=$c[1] T2=$c[2] T3=$c[3] TP=$c[4] ZSH_THEME_NAME=$1
}

# Change de thème immédiatement et le mémorise pour les prochains shells
change_theme() {
    if ! _apply_theme "$1"; then
        echo "Usage: change_theme [${(j:|:)${(@ok)ZSH_THEMES}}]"
        return 1
    fi
    print -r -- "$1" > ~/.zsh/theme
}

if [[ -r ~/.zsh/theme ]] && _apply_theme "$(<~/.zsh/theme)"; then :; else _apply_theme sunlight; fi

# ========================================
# MÉTRIQUES SYSTÈME ET GIT
# ========================================
# Calculées une seule fois par prompt dans un hook precmd, sans sous-shell
# pour le prompt lui-même. Les segments produits contiennent des séquences
# de prompt (%F, %%) : ils ne sont destinés qu'à PROMPT/RPROMPT.

typeset -gi _cpu_pct=0 _cpu_total=0 _cpu_idle=0 _ram_pct=0 _dsk_pct=0
typeset -g  _ram_txt="" _sys_seg="" _git_seg=""

if [[ $OSTYPE == darwin* ]]; then
    typeset -gi _mem_total=$(sysctl -n hw.memsize) _page=$(sysctl -n hw.pagesize) _ncpu=$(sysctl -n hw.ncpu)
fi

# Couleur selon seuils : _lvl <valeur> <seuil jaune> <seuil rouge> → $REPLY
_lvl() {
    if   (( $1 >= $3 )); then REPLY=red
    elif (( $1 >= $2 )); then REPLY=yellow
    else REPLY=green
    fi
}

# RAM utilisée / totale, ex. « 1.3Go / 16Go »
_ram_update() {
    local -i used=0 total=0
    if [[ $OSTYPE == darwin* ]]; then
        # Mémoire utilisée façon Moniteur d'activité : active + câblée + compressée
        local line; local -i act=0 wired=0 comp=0
        for line in ${(f)"$(vm_stat)"}; do
            case $line in
                "Pages active:"*)                 act=${line//[^0-9]/} ;;
                "Pages wired down:"*)             wired=${line//[^0-9]/} ;;
                "Pages occupied by compressor:"*) comp=${line//[^0-9]/} ;;
            esac
        done
        total=$_mem_total
        used=$(( (act + wired + comp) * _page ))
    else
        local k v rest; local -i t=0 a=0
        while read -r k v rest; do
            case $k in
                MemTotal:)     t=$v ;;
                MemAvailable:) a=$v; break ;;
            esac
        done < /proc/meminfo
        total=$(( t * 1024 ))
        used=$(( (t - a) * 1024 ))
    fi
    if (( total <= 0 )); then _ram_txt="?"; _ram_pct=0; return; fi
    _ram_pct=$(( 100 * used / total ))
    printf -v _ram_txt '%.1fGo / %.0fGo' $(( used / 1073741824.0 )) $(( total / 1073741824.0 ))
}

# CPU : Linux = moyenne depuis le prompt précédent (/proc/stat, sans échantillonnage
# bloquant) ; macOS = somme des %CPU des processus rapportée au nombre de cœurs
_cpu_update() {
    if [[ $OSTYPE == darwin* ]]; then
        local v; float s=0
        for v in ${(f)"$(LC_ALL=C ps -A -o %cpu=)"}; do (( s += v )); done
        (( _cpu_pct = s / _ncpu ))
    else
        local -a f; read -rA f < /proc/stat
        local -i total=$(( f[2]+f[3]+f[4]+f[5]+f[6]+f[7]+f[8]+f[9] )) idle=$(( f[5]+f[6] ))
        local -i dt=$(( total - _cpu_total )) di=$(( idle - _cpu_idle ))
        _cpu_total=$total _cpu_idle=$idle
        if (( dt > 0 )); then _cpu_pct=$(( 100 * (dt - di) / dt )); fi
    fi
}

# Disque : taux d'occupation du volume qui contient le HOME
_disk_update() {
    local -a l; l=(${=${(f)"$(LC_ALL=C df -Pk -- $HOME 2>/dev/null)"}[2]})
    _dsk_pct=${${l[5]:-0}%\%}
}

# Git : [projet LÉGENDE branche] en un seul appel à git status
#   À COMMIT (rouge)  → changements locaux non commités (staged/unstaged/untracked)
#   À PUSH   (orange) → dépôt propre mais désynchronisé de la remote (ahead et/ou behind)
#   À JOUR   (vert)   → dépôt propre et synchronisé avec la remote
_git_update() {
    _git_seg=""
    local out; out=$(git status --porcelain=v2 --branch 2>/dev/null) || return 0

    local line head="" oid="" ab="" dirty=0
    for line in ${(f)out}; do
        case $line in
            "# branch.head "*) head=${line#\# branch.head } ;;
            "# branch.oid "*)  oid=${line#\# branch.oid } ;;
            "# branch.ab "*)   ab=${line#\# branch.ab } ;;
            "#"*) ;;
            *) dirty=1 ;;
        esac
    done
    [[ $head == "(detached)" ]] && head=${oid[1,7]}

    local -a abv; abv=(${=ab})
    local legend col
    if (( dirty )); then
        legend="À COMMIT" col=red
    elif [[ ${abv[1]} != (|+0) || ${abv[2]} != (|-0) ]]; then
        legend="À PUSH" col=208
    else
        legend="À JOUR" col=green
    fi

    local proj=${$(git rev-parse --show-toplevel 2>/dev/null):t}
    _git_seg="%F{$T2}[${proj//\%/%%} %F{$col}${legend}%F{$T2} ${head//\%/%%}]%f"
}

_prompt_precmd() {
    local LC_ALL=C   # point décimal garanti, quelle que soit la locale
    _git_update
    [[ $ZSH_PROMPT_MODE == full ]] || return 0

    _ram_update; _cpu_update; _disk_update
    local cr cc cd
    _lvl $_ram_pct 70 90; cr=$REPLY
    _lvl $_cpu_pct 40 70; cc=$REPLY
    _lvl $_dsk_pct 70 90; cd=$REPLY
    _sys_seg="%F{$T1}RAM%f %F{$cr}${_ram_txt}%f  %F{$T2}CPU%f %F{$cc}${_cpu_pct}%%%f  %F{$T3}DSK%f %F{$cd}${_dsk_pct}%%%f"
}
add-zsh-hook precmd _prompt_precmd

# ========================================
# PROMPT
# ========================================
# Ligne 1 : utilisateur@machine, chemin, RAM/CPU/disque
# Ligne 2 : statut de la dernière commande et invite
# À droite : statut Git puis heure

change_prompt() {
    case $1 in
        light)
            PROMPT='%F{$TP}%1~%f %F{$T2}❯%f '
            ;;
        full)
            PROMPT='%F{$T1}╭─%f %F{$T2}%n%f%F{$T1}@%f%F{$T3}%m%f in %F{$TP}%~%f  ${_sys_seg}
%F{$T1}╰─%f%(?.%F{green}✓.%F{red}✗)%f %F{$T2}❯%f '
            ;;
        *)
            echo "Usage: change_prompt [light|full]"
            return 1
            ;;
    esac
    ZSH_PROMPT_MODE=$1
    RPROMPT='${_git_seg:+$_git_seg }%F{$T3}%D{%H:%M:%S}%f'
}

# ========================================
# PLUGINS EXTERNES
# ========================================

[[ -d ~/.zsh/plugins/zsh-completions ]] && fpath=(~/.zsh/plugins/zsh-completions/src $fpath)

[[ -f ~/.zsh/plugins/git/git.plugin.zsh ]] && source ~/.zsh/plugins/git/git.plugin.zsh

if [[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor)
    ZSH_HIGHLIGHT_STYLES[default]=none
    ZSH_HIGHLIGHT_STYLES[unknown-token]=fg=red,bold
    ZSH_HIGHLIGHT_STYLES[reserved-word]=fg=cyan,bold
    ZSH_HIGHLIGHT_STYLES[precommand]=fg=green,underline
    ZSH_HIGHLIGHT_STYLES[commandseparator]=fg=blue,bold
    ZSH_HIGHLIGHT_STYLES[path]=fg=blue,underline
    ZSH_HIGHLIGHT_STYLES[globbing]=fg=magenta,bold
    ZSH_HIGHLIGHT_STYLES[single-quoted-argument]=fg=yellow
    ZSH_HIGHLIGHT_STYLES[double-quoted-argument]=fg=yellow
    ZSH_HIGHLIGHT_STYLES[comment]=fg=black,bold
    ZSH_HIGHLIGHT_STYLES[arg0]=fg=green,bold
fi

if [[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=8,italic"
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
    ZSH_AUTOSUGGEST_USE_ASYNC=true
fi

# ========================================
# ENVIRONNEMENT
# ========================================

export EDITOR=nano
export PAGER=less
export LANG=fr_FR.UTF-8
export LC_ALL=fr_FR.UTF-8
export PATH="$HOME/.local/bin:$PATH"
[[ "$OSTYPE" == "darwin"* ]] && export PATH="/opt/homebrew/bin:$PATH"
[[ -d /usr/local/go/bin ]] && path=(/usr/local/go/bin $path)
[[ -d $HOME/go/bin ]] && path+=($HOME/go/bin)

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"

# ========================================
# PROMPT PAR DÉFAUT (full)
# ========================================

change_prompt full

# ========================================
# AIDE
# ========================================

zsh_help() {
    local t
    echo "🎨 ZSH — thème actuel : $ZSH_THEME_NAME"
    echo ""
    echo "📋 Commandes :"
    echo "  change_theme NOM        Changer de dégradé (mémorisé)"
    for t in ${(ok)ZSH_THEMES}; do
        local -a c; c=(${=ZSH_THEMES[$t]})
        print -P "      %F{$c[1]}██%F{$c[2]}██%F{$c[3]}██%f  $t"
    done
    echo "  change_prompt light     Prompt minimaliste"
    echo "  change_prompt full      Prompt complet RAM/CPU/disque (défaut)"
    echo "  zsh_help                Cette aide"
    echo ""
    echo "🌿 Git (à droite du prompt) : [projet LÉGENDE branche]"
    echo "  À COMMIT (rouge)  → changements locaux non commités"
    echo "  À PUSH   (orange) → dépôt propre mais désynchronisé de la remote"
    echo "  À JOUR   (vert)   → dépôt propre et synchronisé avec la remote"
    echo "  Aliases git chargés : ga gst gco gp gl gd gcmsg…"
    echo ""
    echo "📊 Monitoring : RAM: 1.3Go / 16Go   CPU: 12%   DSK: 45%"
    echo "  Valeurs en vert / jaune / rouge selon la charge (CPU ≥40/70 %, RAM et disque ≥70/90 %)"
    echo "  CPU sous Linux : moyenne depuis le prompt précédent"
    echo ""
    echo "🔧 Plugins :"
    [[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
        && echo "  ✅ Syntax Highlighting" || echo "  ❌ Syntax Highlighting"
    [[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
        && echo "  ✅ Autosuggestions"    || echo "  ❌ Autosuggestions"
    [[ -d ~/.zsh/plugins/zsh-completions ]] \
        && echo "  ✅ Enhanced Completions" || echo "  ❌ Enhanced Completions"
    [[ -f ~/.zsh/plugins/git/git.plugin.zsh ]] \
        && echo "  ✅ Git aliases"        || echo "  ❌ Git aliases"
}

echo "🟠 ZSH prêt — 'zsh_help' pour l'aide"
ZSHRC_EOF

    printf '%s\n' "$THEME" > ~/.zsh/theme
    success ".zshrc écrit (thème : $THEME)"
}

# -----------------------------------------------------------------------------
# Changement du shell par défaut vers Zsh
# -----------------------------------------------------------------------------
set_default_shell() {
    local zsh_bin
    zsh_bin=$(command -v zsh)

    if ! grep -qxF "$zsh_bin" /etc/shells 2>/dev/null; then
        info "Ajout de $zsh_bin dans /etc/shells..."
        echo "$zsh_bin" | $SUDO tee -a /etc/shells >/dev/null
    fi

    if [ "${SHELL:-}" != "$zsh_bin" ]; then
        info "Changement du shell par défaut vers $zsh_bin..."
        # Via sudo + nom d'utilisateur : pas d'invite de mot de passe propre à chsh,
        # donc compatible -y avec un sudo sans mot de passe (macOS comme Linux)
        $SUDO chsh -s "$zsh_bin" "$TARGET_USER" 2>/dev/null || $SUDO usermod -s "$zsh_bin" "$TARGET_USER"
        success "Shell par défaut → $zsh_bin"
    else
        success "Shell par défaut déjà sur Zsh"
    fi

    if [ "$OS_FAMILY" = "macos" ]; then
        if defaults write com.apple.Terminal NewWindowSettingsBehavior -int 0 2>/dev/null; then
            success "Terminal.app → 'Default login shell' activé"
        else
            warn "defaults write Terminal.app échoué (ignoré)"
        fi

        local plist=~/Library/Preferences/com.apple.Terminal.plist
        local default_profile
        default_profile=$(defaults read com.apple.Terminal "Default Window Settings" 2>/dev/null || echo "")
        if [ -n "$default_profile" ]; then
            /usr/libexec/PlistBuddy \
                -c "Delete 'Window Settings':'${default_profile}':CommandString" \
                "$plist" 2>/dev/null || true
            success "CommandString supprimé pour le profil '${default_profile}'"
        fi
    fi
}

# =============================================================================
# PHASE 3 — STARTER PACK
# =============================================================================

# Téléchargement vérifié : fetch_verified <url> <sha256 attendu> <destination>
fetch_verified() {
    if [ -z "$2" ]; then
        error "Empreinte de référence introuvable pour $1"
        return 1
    fi
    curl -fsSL "$1" -o "$3"
    if ! printf '%s  %s\n' "$2" "$3" | sha256sum -c --quiet - >/dev/null 2>&1; then
        rm -f "$3"
        error "Empreinte SHA-256 invalide : $1"
        return 1
    fi
}

# Node.js LTS : archive officielle vérifiée par SHASUMS256.txt, installée dans /usr/local
install_node() {
    local arch ver file tmp
    case "$ARCH" in amd64) arch="x64" ;; arm64) arch="arm64" ;; esac
    # index.json : une version par ligne, la plus récente en premier ; "lts" vaut false ou un nom
    ver=$(curl -fsSL https://nodejs.org/dist/index.json | awk -F'"' '/"lts":"/ && !v { v = $4 } END { print v }')
    if [ -z "$ver" ]; then error "Version LTS de Node introuvable"; return 1; fi
    file="node-$ver-linux-$arch.tar.gz"
    tmp=$(mktemp)
    fetch_verified "https://nodejs.org/dist/$ver/$file" \
        "$(curl -fsSL "https://nodejs.org/dist/$ver/SHASUMS256.txt" | awk -v f="$file" '$2 == f { print $1 }')" "$tmp"
    $SUDO tar -xzf "$tmp" -C /usr/local --strip-components=1 --no-same-owner \
        --exclude='*.md' --exclude='LICENSE'
    rm -f "$tmp"
}

# Go : dernière version stable, archive officielle vérifiée, installée dans /usr/local/go
install_go() {
    local ver file tmp
    ver=$(curl -fsSL "https://go.dev/VERSION?m=text" | awk 'NR == 1')
    file="$ver.linux-$ARCH.tar.gz"
    tmp=$(mktemp)
    fetch_verified "https://dl.google.com/go/$file" "$(curl -fsSL "https://dl.google.com/go/$file.sha256")" "$tmp"
    $SUDO rm -rf /usr/local/go
    $SUDO tar -xzf "$tmp" -C /usr/local --no-same-owner
    rm -f "$tmp"
}

# kubectl : binaire officiel de la version stable, vérifié
install_kubectl() {
    local ver url tmp
    ver=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
    url="https://dl.k8s.io/release/$ver/bin/linux/$ARCH/kubectl"
    tmp=$(mktemp)
    fetch_verified "$url" "$(curl -fsSL "$url.sha256")" "$tmp"
    $SUDO install -m 0755 "$tmp" /usr/local/bin/kubectl
    rm -f "$tmp"
}

# uv : archive de la dernière release GitHub, vérifiée par son .sha256
install_uv() {
    local triple url tmp dir
    case "$ARCH" in
        amd64) triple="x86_64-unknown-linux-gnu" ;;
        arm64) triple="aarch64-unknown-linux-gnu" ;;
    esac
    url="https://github.com/astral-sh/uv/releases/latest/download/uv-$triple.tar.gz"
    tmp=$(mktemp); dir=$(mktemp -d)
    fetch_verified "$url" "$(curl -fsSL "$url.sha256" | awk '{print $1}')" "$tmp"
    tar -xzf "$tmp" -C "$dir" --strip-components=1
    $SUDO install -m 0755 "$dir/uv" "$dir/uvx" /usr/local/bin/
    rm -rf "$tmp" "$dir"
}

# PowerShell 7 : archive de la dernière release GitHub, vérifiée via hashes.sha256
install_powershell() {
    local parch base line sum file tmp dest=/opt/microsoft/powershell/7
    case "$ARCH" in amd64) parch="x64" ;; arm64) parch="arm64" ;; esac
    base="https://github.com/PowerShell/PowerShell/releases/latest/download"
    # hashes.sha256 est en UTF-16 avec fins de ligne Windows, noms préfixés par « * »
    line=$(curl -fsSL "$base/hashes.sha256" | iconv -f UTF-16 -t UTF-8 | tr -d '\r' \
        | awk -v a="$parch" '{ f = $2; sub(/^\*/, "", f) } f ~ ("^powershell-[0-9.]+-linux-" a "\\.tar\\.gz$") { print $1, f }')
    if [ -z "$line" ]; then error "Archive PowerShell introuvable dans la dernière release"; return 1; fi
    sum="${line%% *}"; file="${line#* }"
    tmp=$(mktemp)
    fetch_verified "$base/$file" "$sum" "$tmp"
    pkg_for libicu-dev libicu
    $SUDO rm -rf "$dest"
    $SUDO mkdir -p "$dest"
    $SUDO tar -xzf "$tmp" -C "$dest" --no-same-owner
    $SUDO chmod +x "$dest/pwsh"
    $SUDO ln -sf "$dest/pwsh" /usr/local/bin/pwsh
    rm -f "$tmp"
}

# Docker : dépôt officiel docker.com (apt ou dnf selon la famille)
install_docker() {
    if [ "$OS_FAMILY" = "debian" ]; then
        local dist="debian" codename="${VERSION_CODENAME:-}"
        case " ${ID:-} ${ID_LIKE:-} " in
            *" ubuntu "*) dist="ubuntu"; codename="${UBUNTU_CODENAME:-$codename}" ;;
        esac
        pkg_install ca-certificates
        $SUDO install -m 0755 -d /etc/apt/keyrings
        $SUDO curl -fsSL "https://download.docker.com/linux/$dist/gpg" -o /etc/apt/keyrings/docker.asc
        $SUDO chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$dist $codename stable" \
            | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
        $SUDO apt-get update -qq
    else
        local repo="centos"
        case "${ID:-}" in fedora) repo="fedora" ;; rhel) repo="rhel" ;; esac
        $SUDO curl -fsSL "https://download.docker.com/linux/$repo/docker-ce.repo" -o /etc/yum.repos.d/docker-ce.repo
    fi

    pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    if [ -d /run/systemd/system ]; then
        $SUDO systemctl enable --now docker
    else
        warn "systemd absent : démarrez le démon Docker manuellement."
    fi
    if [ "$(id -u)" -ne 0 ]; then
        $SUDO usermod -aG docker "$TARGET_USER"
    fi
}

# GTK3 + WebKitGTK (en-têtes de développement, requis pour compiler avec Wails)
install_gtk() {
    if [ "$OS_FAMILY" = "debian" ]; then
        pkg_install pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev
    else
        pkg_install pkgconf-pkg-config gtk3-devel
        # WebKitGTK 4.1 sur Fedora récent, 4.0 sur RHEL 9 et dérivés
        pkg_install webkit2gtk4.1-devel || pkg_install webkit2gtk3-devel
    fi
}

# macOS : tout passe par Homebrew
brew_item() {
    case "$1" in
        docker)     brew install --cask docker ;;
        powershell) brew install --cask powershell ;;
        node|npm)   brew install node ;;
        golang)     brew install go ;;
        psql)       brew install libpq; brew link --force libpq ;;
        tldr)       brew install tlrc ;;
        pip)        brew install python ;;
        gtk)        info "Inutile sur macOS : Wails utilise le WebKit natif." ;;
        wails)      go install github.com/wailsapp/wails/v2/cmd/wails@latest ;;
        *)          brew install "$1" ;;
    esac
}

install_item() {
    if [ "$OS_FAMILY" = "macos" ]; then brew_item "$1"; return; fi
    case "$1" in
        git|nano|tree) pkg_install "$1" ;;
        gcc)           pkg_for build-essential "gcc gcc-c++ make" ;;
        pip)           pkg_install python3-pip ;;
        psql)          pkg_for postgresql-client postgresql ;;
        node|npm)      install_node ;;
        golang)        install_go ;;
        kubectl)       install_kubectl ;;
        docker)        install_docker ;;
        uv)            install_uv ;;
        tldr)          uv tool install tldr ;;
        gtk)           install_gtk ;;
        wails)         go install github.com/wailsapp/wails/v2/cmd/wails@latest ;;
        powershell)    install_powershell ;;
    esac
}

# Vérifie qu'un outil est réellement utilisable (avant et après installation)
verify_item() {
    case "$1" in
        golang)     command -v go ;;
        pip)        command -v pip3 ;;
        powershell) command -v pwsh ;;
        gtk)
            [ "$OS_FAMILY" = "macos" ] && return 0
            pkg-config --exists gtk+-3.0 \
                && { pkg-config --exists webkit2gtk-4.1 || pkg-config --exists webkit2gtk-4.0; }
            ;;
        *)          command -v "$1" ;;
    esac >/dev/null 2>&1
}

STACK_OK=()
STACK_SKIPPED=()
STACK_FAILED=()

install_stack() {
    if [ -z "$STACK_SELECTED" ]; then return 0; fi
    header "PHASE 3 — STARTER PACK"

    # Emplacements des outils installés hors gestionnaire de paquets
    export PATH="/usr/local/go/bin:$HOME/go/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

    if [ "$OS_FAMILY" = "macos" ]; then ensure_homebrew; else pkg_refresh; fi

    local item
    for item in $STACK_SELECTED; do
        if verify_item "$item"; then
            success "$item déjà présent"
            STACK_SKIPPED+=("$item")
            continue
        fi
        info "Installation : $item — $(stack_desc "$item")"
        # Sous-shell en arrière-plan : set -e reste actif dedans (voir spawn),
        # et l'échec d'un outil n'interrompt pas les suivants
        ( trap - ERR; install_item "$item"; verify_item "$item" ) &
        if wait "$!"; then
            success "$item installé"
            STACK_OK+=("$item")
        else
            error "$item : échec d'installation"
            STACK_FAILED+=("$item")
        fi
    done
}

# -----------------------------------------------------------------------------
# Vérification finale et bilan
# -----------------------------------------------------------------------------
run_checks() {
    info "Vérifications ZSH..."
    command -v zsh >/dev/null 2>&1                && success "Zsh binaire"                || error "Zsh binaire manquant"
    tool_present git                              && success "Git binaire"                || error "Git binaire manquant"
    [ -f ~/.zshrc ]                               && success ".zshrc présent"             || error ".zshrc absent"
    [ -f ~/.zsh/theme ]                           && success "Thème : $(cat ~/.zsh/theme)" || warn "Fichier de thème absent"
    [ -d ~/.zsh/plugins/zsh-syntax-highlighting ] && success "Plugin syntax-highlighting" || warn "Plugin syntax-highlighting absent"
    [ -d ~/.zsh/plugins/zsh-autosuggestions ]     && success "Plugin autosuggestions"     || warn "Plugin autosuggestions absent"
    [ -d ~/.zsh/plugins/zsh-completions ]         && success "Plugin completions"         || warn "Plugin completions absent"
    [ -f ~/.zsh/plugins/git/git.plugin.zsh ]      && success "Plugin git (aliases)"       || warn "Plugin git absent"

    if [ -n "$STACK_SELECTED" ]; then
        printf "\n${BOLD}Starter pack${NC}\n"
        [ "${#STACK_OK[@]}" -gt 0 ]      && success "Installés     : ${STACK_OK[*]}"
        [ "${#STACK_SKIPPED[@]}" -gt 0 ] && info    "Déjà présents : ${STACK_SKIPPED[*]}"
        [ "${#STACK_FAILED[@]}" -gt 0 ]  && error   "En échec      : ${STACK_FAILED[*]} — relancez avec --stack $(printf '%s' "${STACK_FAILED[*]}" | tr ' ' ',')"
        case " ${STACK_OK[*]} " in
            *" docker "*) [ "$(id -u)" -ne 0 ] && info "Docker : groupe docker effectif à la prochaine connexion." ;;
        esac
        case " ${STACK_OK[*]} " in
            *" wails "*) [ "$OS_FAMILY" != "macos" ] && info "Wails : avec WebKitGTK 4.1, compilez avec -tags webkit2_41 (vérification : wails doctor)." ;;
        esac
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    header "PHASE 0 — RECONNAISSANCE"
    detect_os
    detect_package_manager
    detect_prerequisites

    header "PHASE 1 — CHOIX"
    choose_theme
    choose_stack

    printf "\n${BOLD}Récapitulatif${NC}\n"
    if [ "${#MISSING_REQUIRED[@]}" -gt 0 ] && [ "$OS_FAMILY" = "macos" ] && [ "$PKG_MANAGER" != "brew" ]; then
        printf "  • Installer Homebrew (installeur vérifié ou confirmé)\n"
    fi
    printf "  • Prérequis à installer : %s\n" "${MISSING_REQUIRED[*]:-aucun}"
    printf "  • Plugins ZSH + ~/.zshrc (sauvegarde auto) — thème %s " "$THEME"
    theme_preview "$THEME"
    printf "\n  • Zsh comme shell par défaut\n"
    printf "  • Starter pack : %s\n\n" "${STACK_SELECTED:-aucun}"

    ask "Continuer ?" || { info "Annulé."; exit 0; }

    header "PHASE 2 — ZSH"
    install_prerequisites
    install_plugins
    write_zshrc
    set_default_shell

    install_stack

    header "BILAN"
    run_checks

    local status=0
    [ "${#STACK_FAILED[@]}" -eq 0 ] || status=1

    if [ "$ASSUME_YES" = 1 ]; then
        info "Mode -y : Zsh sera actif à la prochaine connexion."
        exit "$status"
    fi

    printf "\nCommandes utiles dans zsh : ${CYAN}zsh_help${NC} · ${CYAN}change_theme${NC} · ${CYAN}change_prompt${NC}\n\n"
    if ask "Activer Zsh maintenant ?"; then
        exec zsh
    fi
    exit "$status"
}

trap 'error "Erreur ligne $LINENO — vérifiez les permissions et relancez."; exit 1' ERR

main "$@"
