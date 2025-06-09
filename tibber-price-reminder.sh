#!/bin/bash

# === Logging ===
log() {
  LOGFILE_PATH="${REMINDER_LOG:-/tmp/reminder.log}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE_PATH"
}

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

# === prüfen, ob das Auto gerade geladen wird ===
CHARGING=$(curl -s "$EVCC_API" | jq -r '.result.loadpoints[0].charging' 2>/dev/null)
if [ "$CHARGING" = "true" ]; then
  log "Auto lädt bereits, kein Reminder/Ladeempfehlung nötig."
  exit 0
fi

# === Konfiguration ===
TOLERANZ_SEK=$((TOLERANZ_MIN * 60))
JETZT_EPOCH=$(date +%s)
LOCK_DIR="/tmp"

# === Günstige Stunden einlesen & Phasen (Blöcke) bilden ===
block_start=""
block_end=""
block_label=""
prev_epoch=0
first_reminder_sent=false
PHASE=""
while read -r ts preis label; do
  cur_epoch=$(date -d "$ts" +%s)
  if [ -z "$block_start" ]; then
    block_start="$ts"
    block_end="$ts"
    block_label="$label"
    prev_epoch="$cur_epoch"
    continue
  fi
  # Prüfe, ob aktuelle Stunde Teil des Blocks ist (1h Unterschied & gleiches Label)
  if [ $((cur_epoch - prev_epoch)) -eq 3600 ] && [ "$label" = "$block_label" ]; then
    block_end="$ts"
    prev_epoch="$cur_epoch"
    continue
  fi

  # Block-Ende erreicht: Reminder für Block-Start prüfen
  block_start_epoch=$(date -d "$block_start" +%s)
  diff_sec=$((block_start_epoch - JETZT_EPOCH))
  if [ "$first_reminder_sent" = false ] && [ "$diff_sec" -le "$TOLERANZ_SEK" ] && [ "$diff_sec" -ge -$TOLERANZ_SEK ]; then
    PHASE="$block_start $block_end $block_label"
    first_reminder_sent=true
    break
  fi
  # Nächsten Block starten
  block_start="$ts"
  block_end="$ts"
  block_label="$label"
  prev_epoch="$cur_epoch"
done < <(grep -E "^(20|21)[0-9]{2}-" "$GUENSTIGE")

# Letzten Block prüfen, falls keine Phase bisher gefunden wurde
if [ "$first_reminder_sent" = false ] && [ -n "$block_start" ]; then
  block_start_epoch=$(date -d "$block_start" +%s)
  diff_sec=$((block_start_epoch - JETZT_EPOCH))
  if [ "$diff_sec" -le "$TOLERANZ_SEK" ] && [ "$diff_sec" -ge -$TOLERANZ_SEK ]; then
    PHASE="$block_start $block_end $block_label"
  fi
fi

# === Phase prüfen ===
if [ -z "$PHASE" ]; then
  log "Keine Phase in Toleranz gefunden."
  exit 0
fi

# === Start- und Endzeit, Label extrahieren ===
START_TS=$(echo "$PHASE" | awk '{print $1}')
END_TS=$(echo "$PHASE" | awk '{print $2}')
ORIG_LABEL=$(echo "$PHASE" | awk '{print $3}')
PHASE_EPOCH=$(date -d "$START_TS" +%s)
ENDE_EPOCH=$(date -d "$END_TS" +%s)

# === Menschliches Label für Anzeige erzeugen ===
START_DATUM=$(date -d "$START_TS" +%Y-%m-%d)
HEUTE_DATUM=$(date +%Y-%m-%d)
MORGEN_DATUM=$(date -d "tomorrow" +%Y-%m-%d)

if [ "$START_DATUM" = "$HEUTE_DATUM" ]; then
  DAUER_LABEL="heute"
elif [ "$START_DATUM" = "$MORGEN_DATUM" ]; then
  DAUER_LABEL="morgen"
else
  DAUER_LABEL="am $(date -d "$START_TS" +%d.%m.%Y)"
fi

PHASE_HASH="reminder_${DAUER_LABEL}_$(date -d "$START_TS" +%Y-%m-%d_%H:%M)"
LOCKFILE="$LOCK_DIR/$PHASE_HASH"

if [ "$IGNORE_LOCK" != true ] && [ -f "$LOCKFILE" ]; then
  log "Reminder bereits gesendet ($PHASE_HASH), Abbruch."
  exit 0
fi

# === Stunden im Block einsammeln und sortiert aufbereiten ===
TEXT=""
BEST_PREIS=999
BEST_ZEILE=""

while read -r ts preis label; do
  # Nur innerhalb Block und passendes Label
  ts_epoch=$(date -d "$ts" +%s)
  [ "$label" != "$ORIG_LABEL" ] && continue
  [ "$ts_epoch" -lt "$PHASE_EPOCH" ] && continue
  [ "$ts_epoch" -gt "$ENDE_EPOCH" ] && continue

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
done < "$GUENSTIGE"

TEXT="$BEST_ZEILE"$'\n'"$TEXT"

DAUER_VON=$(date -d "$START_TS" +%H:%M)
DAUER_BIS=$(date -d "$END_TS 1 hour" +%H:%M)

NACHRICHT="🔔 Günstige Strompreisphase beginnt bald!

💡 Dauer: $DAUER_LABEL $DAUER_VON bis $DAUER_BIS Uhr

$TEXT
📅 Stand: $(date '+%d.%m.%Y %H:%M Uhr')"

# === Telegram senden ===
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
  --data-urlencode "text=$NACHRICHT" \
  -d parse_mode=Markdown >/dev/null

# === Ladeempfehlungsskript starten ===
if [ -x "$LADEEMPFEHLUNG_SH" ]; then
  "$LADEEMPFEHLUNG_SH" --from-reminder
fi

# === Lockfile setzen (außer bei --test oder --ignore-lock) ===
if [ "$TESTMODE" != true ] && [ "$IGNORE_LOCK" != true ]; then
  touch "$LOCKFILE"
  log "Reminder gesendet für $PHASE_HASH ($DAUER_LABEL $DAUER_VON-$DAUER_BIS)."
else
  log "Testmodus oder --ignore-lock aktiv – kein Lockfile geschrieben ($PHASE_HASH)."
fi
