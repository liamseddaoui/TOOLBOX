#!/usr/bin/env bash
# Déploie la status line Claude Code : copie statusline.sh vers ~/.claude et déclare statusLine dans settings.json
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/statusline.sh"
CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
STAMP=$(date +%Y%m%d-%H%M%S)
BAK="aucune (fichier créé)"

command -v jq >/dev/null || { echo "jq est requis : sudo dnf install -y jq" >&2; exit 1; }
[ -f "$SRC" ] || { echo "statusline.sh introuvable à côté de ce script" >&2; exit 1; }
bash -n "$SRC" || { echo "erreur de syntaxe dans statusline.sh" >&2; exit 1; }

install -d -m 700 "$CLAUDE_DIR"
[ -f "$DEST" ] && cp -p "$DEST" "$DEST.bak-$STAMP"
install -m 755 "$SRC" "$DEST"

if [ -f "$SETTINGS" ]; then
  jq empty "$SETTINGS" 2>/dev/null || { echo "$SETTINGS n'est pas du JSON valide : rien modifié" >&2; exit 1; }
  BAK="$SETTINGS.bak-$STAMP"
  cp -p "$SETTINGS" "$BAK"
else
  echo '{}' > "$SETTINGS"
fi
TMP=$(mktemp "$CLAUDE_DIR/settings.XXXXXX")
jq --arg cmd "$DEST" '.statusLine = {type: "command", command: $cmd, padding: 1, refreshInterval: 60}' "$SETTINGS" > "$TMP"
mv "$TMP" "$SETTINGS"
chmod 600 "$SETTINGS"
echo "Status line : $DEST"
echo "Réglage     : statusLine ajouté dans $SETTINGS (sauvegarde : $BAK)"

# Aperçus : modèle, contexte %, 5 h %, secondes avant reset 5 h, 7 j %
mock() {
  jq -nc --arg m "$1" --argjson c "$2" --argjson h "$3" --argjson r "$4" --argjson d "$5" \
    '{model: {display_name: $m}, context_window: {used_percentage: $c},
      rate_limits: {five_hour: {used_percentage: $h, resets_at: ((now | floor) + $r)},
                    seven_day: {used_percentage: $d, resets_at: ((now | floor) + 300000)}}}'
}
echo; echo "1. session normale";        mock "Sonnet 5.5" 34.2 23.5 8000 41.2 | COLUMNS=120 "$DEST"
echo "2. charge élevée";               mock "Sonnet 5.5" 62 88.4 1500 76.8 | COLUMNS=120 "$DEST"
echo "3. limite de 5 h atteinte";      mock "Opus 5.5" 91 100 4300 93 | COLUMNS=120 "$DEST"
echo "4. début de session";            echo '{"model":{"display_name":"Sonnet 5.5"}}' | COLUMNS=120 "$DEST"
echo "5. terminal étroit (80 col.)";   mock "Sonnet 5.5" 34.2 23.5 8000 41.2 | COLUMNS=80 "$DEST"
