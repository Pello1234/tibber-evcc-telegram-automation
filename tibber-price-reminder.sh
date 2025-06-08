#!/bin/bash

# === Parameterverarbeitung ===
TESTMODE=false
IGNORE_LOCK=false
for arg in "$@"; do
  [[ "$arg" == "--test" ]] && TESTMODE=true
  [[ "$arg" == "--ignore-lock" ]] && IGNORE_LOCK=true
done

# === .env laden ===
ENVFILE="${ENVFILE:-/home/pi/tibber-evcc-telegram-automation/token.env}"
if [ -f "$ENVFILE" ]; then
  set -a
  . "$ENVFILE"
  set +a
else
  echo "Fehler: $ENVFILE nicht gefunden!"
  exit 1
fi

# === Logging ===
log() {
  LOGFILE_PATH="${REMINDER_LOG:-/tmp/reminder.log}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE_PATH"
}

# === Konfiguration ===
TOLERANZ_SEK=$((TOLERANZ_MIN * 60))
JETZT_EPOCH=$(date +%s)
LOCK_DIR="/tmp"

# === Nächste günstige Phase ermitteln ===
PHASE=$(grep -E "^(20|21)[0-9]{2}-" "$GUENSTIGE" | while read -r zeile; do
  ts=$(echo "$zeile" | awk '{print $1}')
  preis=$(echo "$zeile" | awk '{print $2}')
  label=$(echo "$zeile" | awk '{print $3}')
  start_epoch=$(date -d "$ts" +%s)
  diff_sec=$((start_epoch - JETZT_EPOCH))

  if [ "$TESTMODE" = true ] || [ "$IGNORE_LOCK" = true ]; then
    echo "$ts $label"
    break
  fi

  if [ "$diff_sec" -le "$TOLERANZ_SEK" ] && [ "$diff_sec" -ge -$TOLERANZ_SEK ]; then
    echo "$ts $label"
    break
  fi
done)


if [ -z "$PHASE" ]; then
  log "Keine Phase in Toleranz gefunden."
  exit 0
fi

START_TS=$(echo "$PHASE" | awk '{print $1}')
LABEL=$(echo "$PHASE" | awk '{print $2}')
PHASE_EPOCH=$(date -d "$START_TS" +%s)
PHASE_HASH="reminder_${LABEL}_$(date -d "$START_TS" +%Y-%m-%d_%H:%M)"
LOCKFILE="$LOCK_DIR/$PHASE_HASH"

if [ "$IGNORE_LOCK" != true ] && [ -f "$LOCKFILE" ]; then
  log "Reminder bereits gesendet ($PHASE_HASH), Abbruch."
  exit 0
fi

# === Stunden der Phase sammeln ===
ENDE_EPOCH=$PHASE_EPOCH
BEST_PREIS=999
TEXT=""

while read -r ts preis label; do
  [ "$label" != "$LABEL" ] && continue
  ts_epoch=$(date -d "$ts" +%s)
  if [ "$ts_epoch" -lt "$PHASE_EPOCH" ]; then continue; fi
  diff=$((ts_epoch - PHASE_EPOCH))
  [ $diff -gt 21600 ] && break

  stunde=$(date -d "$ts" +%H)
  von="${stunde}:00"
  bis=$(printf "%02d:00" $((10#$stunde + 1)))
  preis_fmt=$(awk -v p="$preis" 'BEGIN { if (p < 1) printf "%.2f Cent", p*100; else printf "%.2f Euro", p }' | sed 's/\./,/')
  zeile="🕓 $von bis $bis Uhr – 💶 $preis_fmt"

  preis_cmp=$(awk -v p="$preis" 'BEGIN { printf "%.4f", p }')
  if (( $(echo "$preis_cmp < $BEST_PREIS" | bc -l) )); then
    BEST_PREIS="$preis_cmp"
    BEST_ZEILE="$zeile⭐️"
  else
    TEXT+="$zeile"$'\n'
  fi
  ENDE_EPOCH=$ts_epoch
done < "$GUENSTIGE"

TEXT="$BEST_ZEILE"$'\n'"$TEXT"

DAUER_VON=$(date -d "@$PHASE_EPOCH" +%H:%M)
DAUER_BIS=$(date -d "@$((ENDE_EPOCH + 3600))" +%H:%M)
DAUER_LABEL=$([ "$LABEL" == "heute" ] && echo "heute" || echo "morgen")

NACHRICHT="🔔 Günstige Strompreisphase beginnt bald!

💡 Dauer: $DAUER_LABEL $DAUER_VON bis $DAUER_BIS Uhr

$TEXT
📅 Stand: $(date '+%d.%m.%Y %H:%M Uhr')"

# === Telegram senden ===
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
  --data-urlencode "text=$NACHRICHT" \
  -d parse_mode=Markdown >/dev/null

# Ladeempfehlungsskript ausführen (optional)
if [ -x "$LADEEMPFEHLUNG_SH" ]; then
  "$LADEEMPFEHLUNG_SH" --from-reminder
fi

if [ "$TESTMODE" != true ] && [ "$IGNORE_LOCK" != true ]; then
  touch "$LOCKFILE"
  log "Reminder gesendet für $PHASE_HASH ($DAUER_LABEL $DAUER_VON-$DAUER_BIS)."
else
  log "Testmodus oder --ignore-lock aktiv – kein Lockfile geschrieben ($PHASE_HASH)."
fi
