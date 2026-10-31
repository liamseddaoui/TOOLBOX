#!/bin/bash
# Status line Claude Code : contexte, limites 5 h et 7 j, heure du prochain reset 5 h
# Pas de "set -e" ici : un code de sortie non nul vide la status line.
export LC_ALL=C

input=$(cat)

# Un seul appel jq ; "-" = valeur absente (rate_limits n'existe qu'après la 1re réponse, abonnés Pro/Max)
IFS=$'\t' read -r MODEL CTX H5 H5R D7 < <(jq -r '
  def pct: if . == null then "-" else (round | tostring) end;
  [ (.model.display_name // "?"),
    (.context_window.used_percentage | pct),
    (.rate_limits.five_hour.used_percentage | pct),
    (.rate_limits.five_hour.resets_at // "-" | tostring),
    (.rate_limits.seven_day.used_percentage | pct)
  ] | join("\t")' <<<"$input" 2>/dev/null)
: "${MODEL:=?}" "${CTX:=-}" "${H5:=-}" "${H5R:=-}" "${D7:=-}"

# Palette 256 couleurs
R=$'\033[0m'; B=$'\033[1m'
DIM=$'\033[38;5;240m'; LBL=$'\033[38;5;246m'; MOD=$'\033[38;5;183m'; HI=$'\033[38;5;255m'
fg() { printf '\033[38;5;%sm' "$1"; }

# Couleur selon le niveau : vert < 50, jaune < 75, orange < 90, rouge au-delà
tone() {
  if   [ "$1" -ge 90 ]; then echo 203
  elif [ "$1" -ge 75 ]; then echo 208
  elif [ "$1" -ge 50 ]; then echo 221
  else echo 114; fi
}

# Barre fine : segments pleins colorés, reste en gris
bar() {
  local p=$1 w=$2 i filled
  [ "$p" -gt 100 ] && p=100
  filled=$(( (p * w + 50) / 100 ))
  [ "$p" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
  fg "$(tone "$p")"
  for ((i = 0; i < filled; i++)); do printf '━'; done
  printf '%s' "$DIM"
  for ((i = 0; i < w - filled; i++)); do printf '─'; done
  printf '%s' "$R"
}

# Segment "libellé barre pourcentage" ; "-" affiche une barre vide
seg() {
  local label=$1 p=$2 w=$3 i line=""
  if [ "$p" = "-" ]; then
    for ((i = 0; i < w; i++)); do line+='─'; done
    printf '%s%s %s%s –%s' "$LBL" "$label" "$DIM" "$line" "$R"
  else
    printf '%s%s%s %s %s%s%s%%%s' "$LBL" "$label" "$R" "$(bar "$p" "$w")" "$(fg "$(tone "$p")")" "$B" "$p" "$R"
  fi
}

# Largeur des barres selon le terminal (COLUMNS est fourni par Claude Code)
COLS=${COLUMNS:-120}; [[ $COLS =~ ^[0-9]+$ ]] || COLS=120
if   [ "$COLS" -ge 110 ]; then WC=10; WL=8
elif [ "$COLS" -ge 85 ];  then WC=6;  WL=5
else WC=4; WL=4; fi

# Heure du prochain reset de la fenêtre de 5 h, avec le temps restant
RESET=""
if [[ $H5R =~ ^[0-9]+$ ]]; then
  LEFT=$(( H5R - $(date +%s) ))
  if [ "$LEFT" -gt 0 ]; then
    if [ "$LEFT" -ge 3600 ]; then REL="$(( LEFT / 3600 ))h$(printf '%02d' $(( LEFT % 3600 / 60 )))"
    else REL="$(( (LEFT + 59) / 60 ))min"; fi
    RESET=" ${DIM}↻${R} ${HI}${B}$(date -d "@$H5R" +%H:%M)${R} ${DIM}(${REL})${R}"
  fi
fi
LIMIT=""
[[ $H5 =~ ^[0-9]+$ ]] && [ "$H5" -ge 100 ] && LIMIT=" ${B}$(fg 196)LIMITE${R}"

SEP="${DIM} │ ${R}"
printf '%s\n' "${MOD}${B}${MODEL}${R}${SEP}$(seg ctx "$CTX" "$WC")${SEP}$(seg 5h "$H5" "$WL")${LIMIT}${RESET}${SEP}$(seg 7j "$D7" "$WL")"
