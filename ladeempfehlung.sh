# Dieses Skript gibt eine Ladeempfehlung für EVs mit EVCC-API und Tibber-Preisprognose.
# Voraussetzung: .env-Datei mit EVCC_API, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID usw.

#!/bin/bash
set -euo pipefail

# === Logging  ===
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# === Konfiguration aus ENV-Datei einlesen ===
ENVFILE="${ENVFILE:-/home/pi/tibber-evcc-telegram-automation/token.env}"
if [ -f "$ENVFILE" ]; then
  set -a
  . "$ENVFILE"
  set +a
else
  echo "Fehler: $ENVFILE nicht gefunden!"
  exit 1
fi

# === Laden prüfen, ggf. abbrechen ===
CHARGING=$(curl -s "$EVCC_API" | jq -r '.result.loadpoints[0].charging' 2>/dev/null)
if [ "$CHARGING" = "true" ]; then
  log "Ladeempfehlung: Auto lädt bereits, kein Vorschlag gesendet."
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=⚡ *Ladeempfehlung*: Das Auto wird bereits geladen, keine Empfehlung nötig!" \
    --data-urlencode "parse_mode=Markdown"
  exit 0
fi

# Ab hier werden alle Variablen aus token.env verwendet:
# TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, EVCC_API, WALLBOX_KW, ALLE, LOG, HA_TOKEN_FILE, HA_API_URL

# Preisformat NUR für Log, KEINE Emojis/Umlaute!
format_preis_log() {
  local raw="$1"
  if (( $(echo "$raw < 1" | bc -l) )); then
    printf "%.1f Cent" "$(echo "$raw * 100" | bc -l)"
  else
    printf "%.2f Euro" "$raw" | sed 's/\./,/'
  fi
}

# Preisformat für Telegram-Nachricht (mit Emojis/Formatierung)
format_preis() {
  local raw="$1"
  if (( $(echo "$raw < 1" | bc -l) )); then
    printf "%.1f Cent" "$(echo "$raw * 100" | bc -l)"
  else
    printf "%.2f €" "$raw" | sed 's/\./,/'
  fi
}

# --- SOC, Ziel, Kapazität holen ---
SOC=$(curl -s "$EVCC_API" | jq -r '.result.loadpoints[0].vehicleSoc')
CAPACITY=$(curl -s "$EVCC_API" | jq -r '.result.vehicles.ev2.capacity')

# HA_TOKEN und API-URL aus ENV
HA_TOKEN=$(cat "$HA_TOKEN_FILE")
ZIEL_SOC=$(curl -s -H "Authorization: Bearer $HA_TOKEN" "$HA_API_URL" | jq -r '.state')
[[ -z "$ZIEL_SOC" || "$ZIEL_SOC" == "null" ]] && ZIEL_SOC=$(curl -s "$EVCC_API" | jq -r '.result.loadpoints[0].effectiveLimitSoc')
if [[ -z "$SOC" || "$SOC" == "null" || -z "$ZIEL_SOC" || "$ZIEL_SOC" == "null" || -z "$CAPACITY" || "$CAPACITY" == "null" ]]; then
  MSG="⚡ Ladeempfehlung: SOC oder Kapazität konnte nicht ermittelt werden."
  log "Ladeempfehlung: SOC oder Kapazitaet konnte nicht ermittelt werden."
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$MSG"
  exit 0
fi

# -- Korrektur für Capacity, falls in Wh geliefert wird --
if (( $(echo "$CAPACITY > 100" | bc -l) )); then
  CAPACITY=$(echo "$CAPACITY / 1000" | bc -l)
fi

fehlende_prozent=$(echo "$ZIEL_SOC - $SOC" | bc -l)
fehlende_kwh=$(echo "$fehlende_prozent * $CAPACITY / 100" | bc -l)

lade_dauer_stunden=$(awk "BEGIN { print $fehlende_kwh / $WALLBOX_KW }")
lade_dauer_min=$(printf "%.0f" $(echo "$lade_dauer_stunden * 60" | bc -l))
lade_dauer_anzeige=""
if (( lade_dauer_min < 60 )); then
  lade_dauer_anzeige="${lade_dauer_min} Min"
else
  lade_dauer_anzeige="$(($lade_dauer_min / 60)) Std $(($lade_dauer_min % 60)) Min"
fi

# Sliding-Window: Wie viele Stunden brauchen wir?
fenster=$(( lade_dauer_min / 60 ))
(( fenster * 60 < lade_dauer_min )) && fenster=$((fenster+1))
(( fenster < 1 )) && fenster=1

now_epoch=$(date +%s)

# --- Ladefenster suchen (Sliding Window) ---
readarray -t zeilen < "$ALLE"
declare -a ts preis
for z in "${zeilen[@]}"; do
  t=$(echo "$z" | awk '{print $1}')
  p=$(echo "$z" | awk '{print $2}' | sed 's/,/./')
  epoch=$(date -d "$t" +%s)
  (( epoch < now_epoch )) && continue
  ts+=("$t")
  preis+=("$p")
done
n=${#preis[@]}
beste_idx=-1; beste_avg=999

for ((i=n-fenster; i>=0; i--)); do
  summe=0
  for ((j=0; j<fenster; j++)); do
    idx=$((i+j))
    summe=$(echo "$summe + ${preis[$idx]}" | bc -l)
  done
  avg=$(echo "$summe / $fenster" | bc -l)
  if (( $(echo "$avg <= $beste_avg" | bc -l) )); then
    beste_avg=$avg
    beste_idx=$i
  fi
done

block_all_lt20=1
if (( beste_idx >= 0 )); then
  for ((j=0; j<fenster; j++)); do
    idx=$((beste_idx+j))
    (( $(echo "${preis[$idx]} >= $PREIS_GRENZE" | bc -l) )) && block_all_lt20=0
  done
fi

min_idx=0; min_preis=999
for ((i=n-1; i>=0; i--)); do
  (( $(date -d "${ts[$i]}" +%s) < now_epoch )) && continue
  if (( $(echo "${preis[$i]} <= $min_preis" | bc -l) )); then
    min_preis="${preis[$i]}"
    min_idx=$i
  fi
done

billigste_stunde_von=$(date -d "${ts[$min_idx]}" +"%H:%M")
billigste_stunde_bis=$(date -d "${ts[$min_idx]} +1 hour" +"%H:%M")

# --- Dynamische Label-Bestimmung ---
# Für Ladeblock
if (( beste_idx >= 0 )); then
  start_utc="${ts[$beste_idx]}"
  end_utc="${ts[$((beste_idx+fenster-1))]}"
  start_local=$(date -d "$start_utc" +"%H:%M")
  end_local=$(date -d "$end_utc +1 hour" +"%H:%M")

  start_date=$(date -d "$start_utc" +"%Y-%m-%d")
  today=$(date +"%Y-%m-%d")
  tomorrow=$(date -d "tomorrow" +"%Y-%m-%d")
  if [ "$start_date" = "$today" ]; then
    start_label="heute"
  elif [ "$start_date" = "$tomorrow" ]; then
    start_label="morgen"
  else
    start_label="am $(date -d "$start_utc" +"%d.%m.%Y")"
  fi

  # Für billigste Einzelstunde
  billigste_date=$(date -d "${ts[$min_idx]}" +"%Y-%m-%d")
  if [ "$billigste_date" = "$today" ]; then
    billigste_label="heute"
  elif [ "$billigste_date" = "$tomorrow" ]; then
    billigste_label="morgen"
  else
    billigste_label="am $(date -d "${ts[$min_idx]}" +"%d.%m.%Y")"
  fi

  blockpreise=(); summe=0
  for ((j=0; j<fenster; j++)); do
    idx=$((beste_idx+j))
    blockpreise+=("${preis[$idx]}")
    summe=$(echo "$summe + ${preis[$idx]}" | bc -l)
  done
  min=$(printf "%s\n" "${blockpreise[@]}" | sort -n | head -n1)
  max=$(printf "%s\n" "${blockpreise[@]}" | sort -n | tail -n1)
  avg=$(echo "$summe / $fenster" | bc -l)
  kosten=$(echo "$avg * $fehlende_kwh" | bc -l)
  lade_kosten_str=$(format_preis "$(printf "%.2f" "$kosten")")
  min_str=$(format_preis "$min")
  max_str=$(format_preis "$max")
  avg_str=$(format_preis "$avg")
  block_text="günstigster Block"
  (( block_all_lt20 )) && block_text="alle Preise <20 Cent"

  lade_kosten_log=$(format_preis_log "$(printf "%.2f" "$kosten")")
  min_log=$(format_preis_log "$min")
  max_log=$(format_preis_log "$max")
  avg_log=$(format_preis_log "$avg")
  billigste_stunde_preis_log=$(format_preis_log "${preis[$min_idx]}")
  block_text_log=$block_text

  log "Ladeempfehlung: $start_local-$end_local, Dauer $lade_dauer_anzeige, SOC ${SOC}%, Ziel ${ZIEL_SOC}%, noch ~$(printf \"%.1f\" \"$fehlende_kwh\")kWh, Block $block_text_log, Preis $min_log-$max_log, Ø $avg_log, Kosten ca. $lade_kosten_log. Billigste Einzelstunde: $billigste_stunde_von-$billigste_stunde_bis ($billigste_stunde_preis_log)"
else
  log "Ladeempfehlung: Es konnte kein sinnvolles Ladefenster ermittelt werden."
fi

if (( beste_idx >= 0 )); then
  MSG="🔋 Ladeempfehlung für deinen ID.4:
💡 Lade von $start_local bis $end_local Uhr ($start_label, $block_text)
⏳ Geschätzte Ladedauer: $lade_dauer_anzeige
🔋 Aktueller SOC: ${SOC}%
🌟 Ziel: ${ZIEL_SOC}% (noch ~$(printf \"%.1f\" \"$fehlende_kwh\") kWh)
⚡ Ladeleistung: ${WALLBOX_KW} kW
💶 Preis: $min_str–$max_str (Ø $avg_str)
💰 Kosten: ca. $lade_kosten_str

📊 Tibber: Billigste Einzelstunde $billigste_stunde_von bis $billigste_stunde_bis Uhr ($billigste_label, $(format_preis "${preis[$min_idx]}"))"
else
  MSG="⚡ Ladeempfehlung: Es konnte kein sinnvolles Ladefenster ermittelt werden."
fi

curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
  --data-urlencode "text=$MSG" \
  --data-urlencode "parse_mode=Markdown"

