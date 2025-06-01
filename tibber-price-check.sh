#!/bin/bash

# === ENV-File einlesen (über Umgebungsvariable oder Default) ===
ENVFILE="${ENVFILE:-/home/pi/tibber-evcc-telegram-automation/token.env}"
if [ -f "$ENVFILE" ]; then
  set -a
  . "$ENVFILE"
  set +a
else
  echo "Fehler: $ENVFILE nicht gefunden!"
  exit 1
fi

# === Logging-Funktion mit Zeitstempel ===
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

HEUTE=$(date +"%Y-%m-%d")
LOCKFILE="/tmp/tibber_forecast_sent_$HEUTE.lock"

# === LEERE TEMP-DATEIEN VOR DEM SCHREIBEN ===
> "$TEMP_DATEI"
> "$TEMP_ALLE"

# === TELEGRAM-Nachricht senden ===
function sende_info() {
  local msg="$1"
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$msg" \
    -d parse_mode=Markdown >/dev/null
  log "Telegram-Nachricht gesendet."
}

# === DATEN VON TIBBER API HOLEN ===
log "Hole Preisdaten von Tibber-API…"
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $TIBBER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ viewer { homes { currentSubscription { priceInfo { today { total startsAt } tomorrow { total startsAt } } } } } }"}' \
  https://api.tibber.com/v1-beta/gql)

# === CHECK: Gibt es Preise für morgen? ===
HAT_MORGEN=$(echo "$RESPONSE" | jq '.data.viewer.homes[0].currentSubscription.priceInfo.tomorrow | length')
log "Preise für morgen gefunden: $HAT_MORGEN"

# === Forecast-Nachricht nur senden, wenn noch kein Lockfile existiert ===
if [ "$HAT_MORGEN" -gt 0 ]; then
  if [ -f "$LOCKFILE" ]; then
    log "Lockfile existiert bereits, Forecast-Nachricht wird nicht erneut gesendet."
    exit 0
  fi
fi

# === Helper-Funktion für Preis-Einträge ===
write_stunde() {
  local ts="$1"
  local preis="$2"
  local label="$3"
  echo "$ts $preis $label" >> "$TEMP_ALLE"
  if (( $(echo "$preis < $PREIS_GRENZE" | bc -l) )); then
    echo "$ts $preis $label" >> "$TEMP_DATEI"
  fi
}

# === Schreibe alle Stunden in temporäre Dateien ===
jq -r '.data.viewer.homes[0].currentSubscription.priceInfo.today[] | [.startsAt, .total] | @tsv' <<< "$RESPONSE" | while IFS=$'\t' read -r ts preis; do
  write_stunde "$ts" "$preis" "heute"
done

if [ "$HAT_MORGEN" -gt 0 ]; then
  jq -r '.data.viewer.homes[0].currentSubscription.priceInfo.tomorrow[] | [.startsAt, .total] | @tsv' <<< "$RESPONSE" | while IFS=$'\t' read -r ts preis; do
    write_stunde "$ts" "$preis" "morgen"
  done
fi
log "Alle Preisdaten geschrieben (TEMP_DATEI, TEMP_ALLE)."

# === Dubletten entfernen und endgültige Dateien erzeugen ===
awk '!seen[$0]++' "$TEMP_DATEI" > "$FORECAST_FILE"
awk '!seen[$0]++' "$TEMP_ALLE" > "$ALLE_STUNDEN_FILE"
log "Dubletten entfernt und in Ziel-Dateien geschrieben."

# === Aktuelle Zeit für Filter (nur zukünftige Stunden anzeigen) ===
now_epoch=$(date +%s)

# === Günstige Zeitblöcke ermitteln (nur zukünftig) ===
get_block() {
  local label="$1"
  local first="" last="" von="" bis=""
  local found=0
  while read -r ts preis lab; do
    [ "$lab" != "$label" ] && continue
    ts_epoch=$(date -d "$ts" +%s)
    # Nur zukünftige Stunden berücksichtigen
    if [ "$ts_epoch" -le "$now_epoch" ]; then
      continue
    fi
    stunde=$(echo "$ts" | sed -E 's/.*T([0-9]{2}):.*/\1/')
    if [ $found -eq 0 ]; then
      first=$stunde
      found=1
    fi
    last=$stunde
  done < "$FORECAST_FILE"
  if [ $found -eq 1 ]; then
    von="${first}:00"
    bis=$(printf "%02d:00" $((10#$last + 1)))
    echo "▸ $von – $bis Uhr ($label)"
  fi
}

# === Günstige Stunden für Nachricht vorbereiten (nur zukünftig) ===
BLOCKS=""
GUENSTIGE_HEUTE=""
GUENSTIGE_MORGEN=""

if grep -q "heute" "$FORECAST_FILE"; then
  BLOCKS+="$(get_block "heute")"
  while read -r ts preis label; do
    [ "$label" != "heute" ] && continue
    ts_epoch=$(date -d "$ts" +%s)
    # Nur zukünftige Stunden anzeigen
    if [ "$ts_epoch" -le "$now_epoch" ]; then
      continue
    fi
    stunde=$(echo "$ts" | sed -E 's/.*T([0-9]{2}):.*/\1/')
    von="${stunde}:00"
    bis=$(printf "%02d:00" $((10#$stunde + 1)))
    preis_fmt=$(awk -v p="$preis" 'BEGIN { if (p < 1) printf "%.1f Cent", p*100; else printf "%.2f Euro", p }' | sed 's/\./,/')
    GUENSTIGE_HEUTE+="🕓 $von bis $bis Uhr – 💶 $preis_fmt (heute)
"
  done < "$FORECAST_FILE"
fi

if grep -q "morgen" "$FORECAST_FILE"; then
  BLOCKS+="
$(get_block "morgen")"
  while read -r ts preis label; do
    [ "$label" != "morgen" ] && continue
    ts_epoch=$(date -d "$ts" +%s)
    # Nur zukünftige Stunden anzeigen
    if [ "$ts_epoch" -le "$now_epoch" ]; then
      continue
    fi
    stunde=$(echo "$ts" | sed -E 's/.*T([0-9]{2}):.*/\1/')
    von="${stunde}:00"
    bis=$(printf "%02d:00" $((10#$stunde + 1)))
    preis_fmt=$(awk -v p="$preis" 'BEGIN { if (p < 1) printf "%.1f Cent", p*100; else printf "%.2f Euro", p }' | sed 's/\./,/')
    GUENSTIGE_MORGEN+="🕓 $von bis $bis Uhr – 💶 $preis_fmt (morgen)
"
  done < "$FORECAST_FILE"
fi

# === Nachricht zusammensetzen ===
MESSAGE="⚡ Tibber Forecast für heute & morgen ⚡

📉 Günstiger Strom unter 20 Cent:
$BLOCKS
"

if [ -n "$GUENSTIGE_HEUTE" ]; then
  MESSAGE+="
Heute:
$GUENSTIGE_HEUTE
"
fi

if [ "$HAT_MORGEN" -gt 0 ]; then
  if [ -n "$GUENSTIGE_MORGEN" ]; then
    MESSAGE+="
Morgen:
$GUENSTIGE_MORGEN
"
  fi
else
  MESSAGE+="
⚠️ Für morgen sind noch keine Preise verfügbar. Ich prüfe später erneut.
"
fi

MESSAGE+="📅 Stand: $(date +"%d.%m.%Y %H:%M Uhr")"

# === Nachricht senden ===
sende_info "$MESSAGE"
log "Nachricht an Telegram gesendet."

# === LOCKFILE SCHREIBEN, SOBALD MORGEN-FORECAST VORHANDEN ===
if [ "$HAT_MORGEN" -gt 0 ]; then
  touch "$LOCKFILE"
  log "Lockfile geschrieben: $LOCKFILE (Preise für morgen verfügbar)"
fi

log "Script beendet."
