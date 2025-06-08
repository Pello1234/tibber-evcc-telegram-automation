#!/bin/bash
set -euo pipefail

# === ENVFILE flexibel laden (Standard: .../token.env) ===
ENVFILE="${ENVFILE:-/home/pi/tibber-evcc-telegram-automation/token.env}"
if [ -f "$ENVFILE" ]; then
  set -a
  . "$ENVFILE"
  set +a
else
  echo "Fehler: $ENVFILE nicht gefunden!"
  exit 1
fi

# === ALLE Variablen werden aus der ENV geladen ===
# Erwartet werden:
# TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, EVCC_API, LOCKFILE, TOLERANZ_MIN, GUENSTIGE, LADEEMPFEHLUNG_SH

# --- Preisformatierung für Telegram ---
format_preis() {
  local raw="$1"
  if (( $(echo "$raw < 1" | bc -l) )); then
    printf "%.2f Cent" "$(echo "$raw * 100" | bc -l)" | sed 's/\./,/'
  else
    printf "%.2f €" "$raw" | sed 's/\./,/'
  fi
}

# --- Optionen ---
TESTMODE=false
IGNORE_LOCK=false
for arg in "$@"; do
  case $arg in
    --test)         TESTMODE=true;;
    --ignore-lock)  IGNORE_LOCK=true;;
  esac
done

NOW_EPOCH=$(date +"%s")
ZIEL_EPOCH=$(date -d "+1 hour" +"%s")    # Reminder eine Stunde vor Phase-Start

# --- Ladevorgang abfragen ---
is_charging=$(curl -s "$EVCC_API" | jq -r '.result.loadpoints[0].charging // .result.loadpoints[0].vehicleConnected')
if [[ "$is_charging" == "true" ]]; then
  echo "🚗 Das Auto lädt gerade – Reminder übersprungen."
  exit 0
fi

[ ! -f "$GUENSTIGE" ] && exit 0

# --- Stunden einlesen (doppelte Timestamps vermeiden) ---
mapfile -t STUNDEN < <(awk '!seen[$1]++' "$GUENSTIGE")

# --- Phasen/Blöcke bilden ---
PHASES=()
CURRENT_PHASE=()
for ((i=0; i<${#STUNDEN[@]}; i++)); do
  TS=$(echo "${STUNDEN[$i]}" | awk '{print $1}')
  TS_EPOCH=$(date -d "$TS" +"%s")
  [ "$TS_EPOCH" -le "$NOW_EPOCH" ] && continue

  if [ ${#CURRENT_PHASE[@]} -eq 0 ]; then
    CURRENT_PHASE+=("${STUNDEN[$i]}")
  else
    LAST_TS=$(echo "${CURRENT_PHASE[-1]}" | awk '{print $1}')
    LAST_TS_EPOCH=$(date -d "$LAST_TS" +"%s")
    if (( TS_EPOCH == LAST_TS_EPOCH + 3600 )); then
      CURRENT_PHASE+=("${STUNDEN[$i]}")
    else
      PHASES+=( "$(IFS=$'\n'; echo "${CURRENT_PHASE[*]}")" )
      CURRENT_PHASE=( "${STUNDEN[$i]}" )
    fi
  fi
done
[ ${#CURRENT_PHASE[@]} -gt 0 ] && PHASES+=( "$(IFS=$'\n'; echo "${CURRENT_PHASE[*]}")" )

# --- Reminder je Phase ---
for PHASE in "${PHASES[@]}"; do
  FIRST_LINE=$(echo "$PHASE" | head -n1)
  PHASE_START=$(echo "$FIRST_LINE" | awk '{print $1}')

  # --- Dynamisches Label ---
  PHASE_DATE=$(date -d "$PHASE_START" +"%Y-%m-%d")
  TODAY=$(date +%Y-%m-%d)
  TOMORROW=$(date -d "tomorrow" +%Y-%m-%d)
  if [ "$PHASE_DATE" = "$TODAY" ]; then
    PHASE_LABEL="heute"
  elif [ "$PHASE_DATE" = "$TOMORROW" ]; then
    PHASE_LABEL="morgen"
  else
    PHASE_LABEL="am $(date -d "$PHASE_START" +%d.%m.%Y)"
  fi

  PHASE_START_EPOCH=$(date -d "$PHASE_START" +"%s")
  DIFF_SEC=$((PHASE_START_EPOCH - ZIEL_EPOCH))

  # Hash für diese Phase (gegen Mehrfachbenachrichtigung)
  
    LAST_LINE=$(echo "$PHASE" | tail -n1 | awk '{print $1}')
  HASH="reminder_${PHASE_LABEL}_$(date -d "$PHASE_START" +%Y-%m-%d_%H:%M)_$(date -d "$LAST_LINE" +%H:%M)"

  if $TESTMODE || (( DIFF_SEC >= -TOLERANZ_MIN*60 && DIFF_SEC <= TOLERANZ_MIN*60 )); then
    if [[ "$IGNORE_LOCK" != true ]] && grep -q "$HASH" "$LOCKFILE" 2>/dev/null; then
      continue
    fi

    START_LOCAL=$(date -d "$PHASE_START" +"%H:%M")
    ENDE_LOCAL=$(date -d "$LAST_LINE +59 min" +"%H:%M")
    STAND=$(date +"%d.%m.%Y %H:%M Uhr")
    [[ "$IGNORE_LOCK" != true ]] && echo "$HASH" >> "$LOCKFILE"

    # Günstigste Stunde im Block finden
    min_idx=0; min_preis=999
    IFS=$'\n' read -r -a lines <<< "$PHASE"
    for idx in "${!lines[@]}"; do
      preis=$(echo "${lines[$idx]}" | awk '{print $2}')
      if (( $(echo "$preis < $min_preis" | bc -l) )); then
        min_preis="$preis"
        min_idx=$idx
      fi
    done


    # Preisliste aufbauen
    PREISLISTE=""
    for idx in "${!lines[@]}"; do
      line="${lines[$idx]}"
      TS2=$(echo "$line" | awk '{print $1}')
      RAW=$(echo "$line" | awk '{print $2}')
      VON=$(date -d "$TS2" +"%H:%M")
      BIS=$(date -d "$TS2 +59 min" +"%H:%M")
      PREIS_FMT=$(format_preis "$RAW")
      if [ "$idx" -eq "$min_idx" ]; then
        PREISLISTE+="🕓 $VON bis $BIS Uhr – 💶 $PREIS_FMT ⭐️"$'\n'
      else
        PREISLISTE+="🕓 $VON bis $BIS Uhr – 💶 $PREIS_FMT"$'\n'
      fi
    done

    MESSAGE="🔔 *Günstige Strompreisphase beginnt bald!* ($PHASE_LABEL)

💡 Dauer: *$START_LOCAL bis $ENDE_LOCAL Uhr*

$PREISLISTE
📅 Stand: $STAND"

    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
      --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
      --data-urlencode "text=$MESSAGE" \
      -d parse_mode=Markdown

    # Ladeempfehlung optional anhängen
    (sleep 10 && bash "$LADEEMPFEHLUNG_SH") &
  fi
done
