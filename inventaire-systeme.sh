#!/usr/bin/env bash
# =============================================================================
# inventaire-systeme.sh — Inventaire complet d'une machine Fedora Server
# Génère un rapport Markdown dans le dossier où se trouve le script.
# Usage : sudo ./inventaire-systeme.sh
# =============================================================================

set -u

# --- Vérification des droits root -------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit être lancé avec sudo : sudo $0" >&2
  exit 1
fi

# --- Fichier de sortie : dossier du script ----------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="$(hostname -s)"
OUT="${SCRIPT_DIR}/inventaire_${HOST}_$(date +%Y%m%d_%H%M%S).md"
: > "$OUT"

# --- Helpers ----------------------------------------------------------------
have() { command -v "$1" &>/dev/null; }
h2()   { printf '\n## %s\n\n' "$1" >> "$OUT"; echo "  → $1"; }
h3()   { printf '\n### %s\n\n' "$1" >> "$OUT"; }

# run "Titre" "commande" : exécute (timeout 60s) et met la sortie en bloc de code.
# Si le premier binaire de la commande est absent, le signale au lieu d'échouer.
run() {
  local title="$1" cmd="$2" bin res
  bin="$(awk '{print $1}' <<< "$cmd")"
  h3 "$title"
  if ! have "$bin"; then
    echo "_\`$bin\` non installé._" >> "$OUT"
    return
  fi
  res="$(timeout 60 bash -c "$cmd" 2>&1)"
  [[ -z "$res" ]] && res="(aucune sortie)"
  printf '```\n%s\n```\n' "$res" >> "$OUT"
}

# versions "Titre" "bin:args" ... : tableau des outils présents et de leur version
versions() {
  local title="$1"; shift
  local entry bin args v found=0
  h3 "$title"
  printf '| Outil | Version |\n|---|---|\n' >> "$OUT"
  for entry in "$@"; do
    bin="${entry%%:*}"; args="${entry#*:}"
    if have "$bin"; then
      # shellcheck disable=SC2086
      v="$(timeout 10 "$bin" $args 2>&1 | grep -m1 -v '^\s*$' | tr '|' '/')"
      echo "| \`$bin\` | ${v:-?} |" >> "$OUT"
      found=1
    fi
  done
  (( found )) || echo "| _aucun détecté_ | |" >> "$OUT"
}

echo "Inventaire en cours → $OUT"

# =============================================================================
# En-tête et synthèse
# =============================================================================
source /etc/os-release 2>/dev/null
CPU_MODEL="$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo | xargs)"
RAM_TOTAL="$(free -h | awk '/^Mem:/{print $2}')"
VIRT="$(systemd-detect-virt 2>/dev/null || echo none)"

cat >> "$OUT" <<EOF
# Inventaire système — ${HOST}

_Généré le $(date '+%d/%m/%Y à %H:%M:%S') par \`$(basename "$0")\`_

## Synthèse

| Élément | Valeur |
|---|---|
| Hostname (FQDN) | $(hostname -f 2>/dev/null || hostname) |
| OS | ${PRETTY_NAME:-inconnu} |
| Noyau | $(uname -r) |
| Architecture | $(uname -m) |
| Virtualisation (hôte) | ${VIRT} |
| CPU | ${CPU_MODEL} — $(nproc) threads |
| RAM | ${RAM_TOTAL} |
| Uptime | $(uptime -p) |
| SELinux | $(getenforce 2>/dev/null || echo n/a) |
| IP principale | $(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}') |
| Paquets RPM | $(rpm -qa | wc -l) |
EOF

# =============================================================================
# Système
# =============================================================================
h2 "Système"
run "hostnamectl"            "hostnamectl"
run "Locale et fuseau"       "localectl status; echo; timedatectl"
run "Ligne de commande noyau" "cat /proc/cmdline"
run "Cible systemd par défaut" "systemctl get-default"

# =============================================================================
# Matériel
# =============================================================================
h2 "Matériel"
run "Carte mère / BIOS"      "dmidecode -t system -t baseboard -t bios | grep -E 'Manufacturer|Product Name|Version|Release Date|Serial'"
run "CPU"                    "lscpu"
run "Support virtualisation matérielle (vmx/svm)" "grep -Ewo 'vmx|svm' /proc/cpuinfo | sort -u; ls -l /dev/kvm 2>&1"
run "Mémoire"                "free -h; echo; dmidecode -t memory | grep -E '^\s+(Size|Type|Speed|Locator):' | grep -v 'No Module'"
run "Périphériques PCI"      "lspci"
run "GPU"                    "lspci | grep -Ei 'vga|3d|display'"
run "NVIDIA (si présent)"    "nvidia-smi"
run "Périphériques USB"      "lsusb"
run "Capteurs"               "sensors"

# =============================================================================
# Stockage
# =============================================================================
h2 "Stockage"
run "Disques et partitions"  "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,ROTA"
run "Occupation"             "df -hT -x tmpfs -x devtmpfs -x overlay"
run "LVM"                    "pvs; echo; vgs; echo; lvs"
run "RAID logiciel"          "cat /proc/mdstat"
run "Btrfs"                  "btrfs filesystem show"
run "/etc/fstab"             "grep -v '^\s*#' /etc/fstab | grep -v '^\s*$'"
run "Swap"                   "swapon --show"
run "Santé SMART"            "for d in \$(smartctl --scan | awk '{print \$1}'); do echo \"== \$d\"; smartctl -H \$d | tail -n2; done"

# =============================================================================
# Réseau
# =============================================================================
h2 "Réseau"
run "Interfaces"             "ip -br addr"
run "Liens"                  "ip -br link"
run "Routes"                 "ip route; echo; ip -6 route"
run "DNS"                    "resolvectl status 2>/dev/null || cat /etc/resolv.conf"
run "NetworkManager"         "nmcli -t device status; echo; nmcli connection show"
run "Ports en écoute"        "ss -tulpn"
run "Firewalld"              "firewall-cmd --state; firewall-cmd --get-active-zones; echo; firewall-cmd --list-all"
run "nftables (règles brutes)" "nft list ruleset | head -n 100"

# =============================================================================
# Sécurité
# =============================================================================
h2 "Sécurité"
run "SELinux"                "sestatus"
run "Politique crypto"       "update-crypto-policies --show"
run "Utilisateurs humains (UID ≥ 1000)" "awk -F: '\$3>=1000 && \$3<65534 {print \$1\" (uid=\"\$3\", shell=\"\$7\")\"}' /etc/passwd"
run "Groupe wheel (sudo)"    "getent group wheel"
run "Règles sudoers custom"  "grep -rhv '^\s*#' /etc/sudoers.d/ 2>/dev/null | grep -v '^\s*$'"
run "SSH (paramètres clés)"  "sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|x11forwarding|allowusers|allowgroups) '"
run "Fail2ban"               "fail2ban-client status"
run "Auditd"                 "systemctl is-active auditd"
run "Dernières connexions"   "last -n 15 -a"
run "Échecs d'authentification (24h)" "journalctl _COMM=sshd --since '24 hours ago' --no-pager | grep -ci 'failed'"

# =============================================================================
# Paquets et mises à jour
# =============================================================================
h2 "Paquets et mises à jour"
run "Dépôts actifs"          "dnf repolist"
run "Groupes / environnements installés" "dnf group list --installed"
run "Mises à jour disponibles" "dnf -q check-update | grep -c '\.' ; echo '(nombre de paquets)'"
run "Historique DNF récent"  "dnf history list | head -n 15"
run "Paquets installés récemment" "rpm -qa --last | head -n 25"
run "Flatpak"                "flatpak list --app"
run "Snap"                   "snap list"

# =============================================================================
# Stack logicielle
# =============================================================================
h2 "Stack logicielle"
versions "Langages et runtimes" \
  "python3:--version" "pip3:--version" "node:--version" "npm:--version" \
  "go:version" "rustc:--version" "cargo:--version" "java:-version" \
  "php:--version" "ruby:--version" "perl:--version" "dotnet:--version" \
  "gcc:--version" "clang:--version" "make:--version" "cmake:--version"

versions "Conteneurs et orchestration" \
  "podman:--version" "buildah:--version" "skopeo:--version" \
  "docker:--version" "docker-compose:--version" "podman-compose:--version" \
  "kubectl:version --client" "helm:version --short" "k3s:--version" \
  "kind:version" "minikube:version" "crictl:--version" "containerd:--version"

versions "Virtualisation" \
  "virsh:--version" "qemu-kvm:--version" "qemu-system-x86_64:--version" "vagrant:--version"

versions "Serveurs web, BDD et middleware" \
  "nginx:-v" "httpd:-v" "caddy:version" "haproxy:-v" \
  "postgres:--version" "psql:--version" "mysql:--version" "mariadb:--version" \
  "redis-server:--version" "mongod:--version" "sqlite3:--version"

versions "DevOps / IaC / outillage" \
  "git:--version" "ansible:--version" "terraform:version" "tofu:version" \
  "packer:version" "jq:--version" "yq:--version" "curl:--version" \
  "rsync:--version" "tmux:-V" "vim:--version" "cockpit-bridge:--version"

versions "IA / GPU" \
  "nvidia-smi:--version" "nvcc:--version" "ollama:--version" "rocm-smi:--version"

run "Modules Python globaux (pip)" "pip3 list 2>/dev/null | head -n 50"
run "Paquets npm globaux"     "npm -g ls --depth=0"

# =============================================================================
# Conteneurs et VM (état)
# =============================================================================
h2 "Conteneurs et machines virtuelles"
run "Podman — conteneurs"    "podman ps -a"
run "Podman — images"        "podman images"
run "Podman — réseaux / volumes" "podman network ls; echo; podman volume ls"
run "Docker — conteneurs"    "docker ps -a"
run "Libvirt — VM"           "virsh list --all"
run "Libvirt — réseaux / pools" "virsh net-list --all; echo; virsh pool-list --all"

# =============================================================================
# Services et planification
# =============================================================================
h2 "Services et planification"
run "Services actifs"        "systemctl list-units --type=service --state=running --no-pager --no-legend"
run "Services activés au boot" "systemctl list-unit-files --type=service --state=enabled --no-pager --no-legend"
run "Unités en échec"        "systemctl --failed --no-pager"
run "Timers systemd"         "systemctl list-timers --all --no-pager"
run "Crontabs"               "cat /etc/crontab 2>/dev/null; ls -1 /etc/cron.d/ 2>/dev/null; for u in \$(cut -d: -f1 /etc/passwd); do c=\$(crontab -l -u \$u 2>/dev/null); [ -n \"\$c\" ] && echo \"== \$u\" && echo \"\$c\"; done"

# =============================================================================
# Performance et santé
# =============================================================================
h2 "Performance et santé"
run "Charge"                 "uptime"
run "Top processus (CPU)"    "ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -n 15"
run "Top processus (RAM)"    "ps -eo pid,user,%cpu,%mem,comm --sort=-%mem | head -n 15"
run "Pression ressources (PSI)" "for r in cpu memory io; do echo \"== \$r\"; cat /proc/pressure/\$r; done"
run "Erreurs du boot courant" "journalctl -p err -b --no-pager | tail -n 40"
run "Taille du journal"      "journalctl --disk-usage"

# --- Fin : rend le fichier à l'utilisateur qui a lancé sudo ------------------
[[ -n "${SUDO_USER:-}" ]] && chown "$SUDO_USER": "$OUT"
echo "Terminé : $OUT"
