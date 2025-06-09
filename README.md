# ⚡️ Tibber EVCC Telegram Automation

Automatisierte Strompreis-Auswertung mit **Tibber**, **EVCC** und direkter Benachrichtigung per **Telegram-Bot**.
Ideal für alle, die ihr E-Auto optimal günstig laden und dabei immer informiert bleiben wollen.

---

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-Ko--fi-FF5E5B?style=flat-square\&logo=ko-fi\&logoColor=white)](https://ko-fi.com/pello1234)

## 🛑 Voraussetzungen

Um diese Automatisierung zu nutzen, benötigst du:

* **Tibber-Account** mit API-Zugang ([Tibber API](https://developer.tibber.com/))
* **Home Assistant** (kann im Container laufen)
* **EVCC** (z. B. als Container oder lokal installiert)
* **Ein kompatibles E-Auto**, das in Home Assistant eingebunden ist
  (z. B. VW ID.4 oder ein anderes Modell mit SOC-Integration)
* Einen **Telegram-Bot** (siehe [Telegram-Doku](https://core.telegram.org/bots))
* Einen Server/Host für die Skripte, z. B. einen **Raspberry Pi** (Container-Umgebung möglich)

> **Standard-Setup:**
> Raspberry Pi (z. B. Pi 4) mit Home Assistant (im Container), EVCC (im Container) und Telegram-Bot.
> Die Skripte laufen aber auch auf jedem Linux-System.

---

## 🚀 Features

* Automatischer **Preis-Forecast** mit Tibber API
* Erkennung günstiger Stromphasen & Blöcke
* Reminder vor günstigen Strompreis-Blöcken (Telegram-Alarm mit Zeitblock, Preisliste, beste Stunde ⭐️, keine Dopplung dank Lockfile)
* Automatische **Ladeempfehlung** für dein E-Auto, abgestimmt auf SOC, Ziel und Wallbox-Leistung
* Übersichtliche Telegram-Nachrichten (Preis, Zeitblock, Dauer, SOC, Kosten, …)
* **Einfache Konfiguration per ****`.env`****-Datei** – keine Code-Anpassung nötig
* Komplett als Shell/Bash-Skripte, läuft lokal (z. B. auf Raspberry Pi, Home Server, NAS etc.)
* Kein Cloud-Backend, keine Drittanbieter-Cloud nötig
* **Testmodus:** `--ignore-lock` erlaubt manuelles Ausführen der Scripte trotz evtl. schon geschriebenen Lockfile
* Reminder- und Ladeempfehlungs-Skript **prüfen vor Ausführung automatisch**, ob das Fahrzeug gerade geladen wird (EVCC-API).
  * Ist bereits ein Ladevorgang aktiv, wird keine erneute Empfehlung oder Erinnerung gesendet (inkl. Log und ggf. Telegram-Benachrichtigung).
* **Ladeempfehlung manuell per Telegram-Bot-Befehl `/ladeempfehlung` anfordern (über Home Assistant Integration)**


---

## 📲 Telegram Integration

Alle Infos kommen **automatisch per Telegram-Bot** auf dein Handy!
Du erhältst:

* Preis-Forecast für heute & morgen
* Reminder kurz vor günstigen Phasen (inkl. Blockbildung, Toleranz, Dopplungsschutz)
* Automatische Ladeempfehlung mit Preis, Zeitfenster, Ladezeit, SOC und Kosten

> **Hinweis:** Du benötigst einen eigenen Telegram-Bot sowie deine eigene Chat-ID – beides einfach in der `.env` hinterlegen.

---

## 🔧 Installation

**Schritt für Schritt:**

1. **Repository klonen & Abhängigkeiten installieren**

   ```bash
   git clone https://github.com/Pello1234/tibber-evcc-telegram-automation.git
   cd tibber-evcc-telegram-automation
   sudo apt install jq curl bc
   ```

2. **Konfigurationsdatei anlegen/anpassen**

   ```bash
   cp token.env.example token.env
   nano token.env
   ```

   Trage deine eigenen **Tokens, IDs & URLs** in die Datei ein (siehe Kommentare in `token.env.example`).
   **Hinweis:** Die Pfade in der Datei sind Beispiele – du kannst eigene Verzeichnisse verwenden!

3. **Skripte ausführbar machen (falls nötig)**

   ```bash
   chmod +x *.sh
   ```

4. **(Optional) Cronjobs einrichten**
   Damit alles automatisch läuft, kannst du Zeitpläne flexibel anpassen:

   ```bash
   crontab -e
   ```

   Beispiel-Einträge:

   ```
   # Preis-Check: täglich um 00:01, 12:01 und 18:01 Uhr
   1 0,12,18 * * * bash /pfad/zu/tibber-price-check.sh

   # Reminder für günstige Phasen alle 10 Minuten
   */10 * * * * bash /pfad/zu/tibber-price-reminder.sh
   ```

   Passe `/pfad/zu/` an deine tatsächlichen Speicherorte an!

   **Testmodus Preis-Check (trotz Lockfile):**

   ```bash
   bash /pfad/zu/tibber-price-check.sh --ignore-lock
   ```
   ```bash
   bash /pfad/zu/tibber-price-reminder.sh --test --ignore-lock
   ```

---

## ⚙️ Konfiguration (`token.env`)

Die `.env`-Datei steuert **alle Einstellungen und Pfade**.
Passe sie an deine Umgebung und Bedürfnisse an.

**Beispiel-Konfiguration:**

```env
# === Telegram Bot Einstellungen ===
TELEGRAM_BOT_TOKEN=dein_telegram_bot_token
TELEGRAM_CHAT_ID=deine_telegram_chat_id

# === EVCC & Fahrzeug-Konfiguration ===
EVCC_API=http://localhost:7070/api/state
WALLBOX_KW=11

# === Tibber API Einstellungen ===
TIBBER_TOKEN=dein_tibber_api_token
HOME_ID=deine_tibber_home_id

# === Schwellenwerte & Preis-Logik ===
PREIS_GRENZE=0.20

# === Pfade für Daten/Logs ===
GUENSTIGE=/pfad/zur/guenstige_stunden.txt
ALLE=/pfad/zur/alle_stundenpreise.txt
LOG=/pfad/zur/ladeempfehlung.log
LOCKFILE=/tmp/evcc_phase_reminder.lock

# === Reminder/Automation ===
# Zeit-Toleranz (in Minuten) für Reminder rund um Phasenstart
TOLERANZ_MIN=60
# Pfad zum Script für Ladeempfehlung (wird ggf. vom Reminder aufgerufen)
LADEEMPFEHLUNG_SH=/home/pi/tibber-evcc-telegram-automation/ladeempfehlung.sh

# Pfad zum Ladeempfehlungs-Skript
LADEEMPFEHLUNG_SH=/pfad/zur/ladeempfehlung.sh

# === (Optional) Home Assistant Einstellungen ===
HA_TOKEN_FILE=/pfad/zur/.homeassistant_token
HA_API_URL=http://dein-ha-server:8123/api/states/sensor.id_4_battery_target_charge_level
```

> **Hinweis:** Du kannst **alle Pfade** beliebig an deine Struktur anpassen!
> Standardmäßig ist `/home/pi/…` ein Beispiel für den Raspberry Pi, aber jeder absolute Pfad funktioniert.

---

## 📋 Beispiel-Nachrichten

### Tibber Forecast

```text
⚡ Tibber Forecast für heute & morgen ⚡

📉 Günstiger Strom unter 20 Cent:
▸ 15:00 – 16:00 Uhr (heute)
▸ 11:00 – 18:00 Uhr (morgen)

Heute:
🕓 15:00 bis 16:00 Uhr – 💶 19,8 Cent (heute)

Morgen:
🕓 11:00 bis 12:00 Uhr – 💶 19,9 Cent (morgen)
🕓 12:00 bis 13:00 Uhr – 💶 19,5 Cent (morgen)
...

📅 Stand: 31.05.2025 14:53 Uhr
```

**Wenn keine günstigen Stunden mehr verfügbar sind:**

```text
⚠️ Für heute sind keine günstigen Stromstunden mehr verfügbar.
⚠️ Für morgen wurden keine günstigen Preise unter 20 Cent gefunden.
```

---

### Reminder vor günstigen Ladephasen

```text
🔔 Günstige Strompreisphase beginnt bald! (heute)

💡 Dauer: 11:00 bis 17:59 Uhr

🕓 11:00 bis 11:59 Uhr – 💶 19,86 Cent
🕓 12:00 bis 12:59 Uhr – 💶 19,46 Cent
🕓 13:00 bis 13:59 Uhr – 💶 18,57 Cent
🕓 14:00 bis 14:59 Uhr – 💶 17,68 Cent ⭐️
🕓 15:00 bis 15:59 Uhr – 💶 18,25 Cent
🕓 16:00 bis 16:59 Uhr – 💶 19,39 Cent
🕓 17:00 bis 17:59 Uhr – 💶 19,99 Cent

📅 Stand: 01.06.2025 09:55 Uhr
```

---

### Automatische Ladeempfehlung

```text
🔋 Ladeempfehlung für dein E-Auto:
💡 Lade von 14:00 bis 16:00 Uhr (heute, alle Preise <20 Cent)
⏳ Geschätzte Ladedauer: 1 Std 16 Min
🔋 Aktueller SOC: 62%
🌟 Ziel: 80% (noch ~13.9 kWh)
⚡ Ladeleistung: 11 kW
💶 Preis: 17.7 Cent–18.2 Cent (Ø 18.0 Cent)
💰 Kosten: ca. 2,49 €

📊 Tibber: Billigste Einzelstunde 14:00 bis 15:00 Uhr (heute, 17.7 Cent)
```

---

## 🏠 Home Assistant Integration (per SSH)

Du kannst das Skript `ladeempfehlung.sh` automatisch auf deinem Raspberry Pi (oder einem anderen Linux-Host) ausführen, wenn dein E-Auto nach Hause kommt und z. B. der SOC unter 80 % liegt.
Die Ausführung erfolgt sicher über SSH – ideal für Home Assistant im Container, auf Synology, VM, etc.

### Beispiel: `shell_command` in `configuration.yaml`

```yaml
shell_command:
  ladeempfehlung_id4: 'ssh -i /config/.ssh/id_rsa -o StrictHostKeyChecking=no pi@192.168.178.99 "bash /home/pi/tibber-evcc-telegram-automation/ladeempfehlung.sh"'
```

**Wichtige Hinweise:**

* SSH-Key vorher zwischen Home Assistant und Zielsystem austauschen (`ssh-copy-id` oder Schlüssel händisch kopieren)
* Skript muss auf dem Pi/Server ausführbar sein (`chmod +x ladeempfehlung.sh`)
* Pfad und User ggf. an dein Setup anpassen

### Beispiel-Automation (automations.yaml)

```yaml
- id: '1738000000000'
  alias: Ladeskript starten bei Heimkehr ID.4 mit SOC < 80%
  trigger:
    - platform: state
      entity_id: device_tracker.id_4_position
      to: 'home'
  condition:
    - condition: numeric_state
      entity_id: sensor.id_4_battery_level
      below: 80
  action:
    - service: shell_command.ladeempfehlung_id4
  mode: single
```

> **Hinweis:**
>
> Wenn Home Assistant und deine Bash-Skripte in getrennten Containern oder auf unterschiedlichen Systemen laufen (z. B. Home Assistant als Docker-Container, Skripte direkt auf dem Raspberry Pi), können sie **nicht direkt aufeinander zugreifen**. Auch das lokale Ausführen von Shell-Kommandos aus Home Assistant heraus funktioniert dann nicht, weil Container voneinander isoliert sind.
>
> Die empfohlene Lösung ist deshalb, das gewünschte Bash-Skript **per SSH von Home Assistant aus remote zu starten** (siehe oben). Das ist sicher, flexibel und funktioniert auch bei Container-Setups, auf NAS, in VMs oder bei verteilten Systemen.

---

## 🔘 Sofort-Ladeempfehlung per Telegram-Befehl

Du kannst jetzt jederzeit eine **Ladeempfehlung manuell per Telegram-Bot anfordern**!
Sende dazu einfach im Chat mit deinem Bot den Befehl:

```text
/ladeempfehlung
```

**Voraussetzung:**

* Dein Bot ist bereits in Home Assistant (z. B. als `telegram_bot:`-Integration) eingebunden.
* Du hast die folgende Automation in deiner `automations.yaml` (bzw. im Automation-Editor) hinterlegt:

```yaml
- alias: "Ladeempfehlung auf Telegram Befehl"
  trigger:
    - platform: event
      event_type: telegram_command
      event_data:
        command: '/ladeempfehlung'
  action:
    - service: shell_command.ladeempfehlung_id4
```

**Ablauf:**

1. Du sendest `/ladeempfehlung` an deinen Bot.
2. Home Assistant empfängt den Befehl und startet das Skript `ladeempfehlung.sh` (wie oben beschrieben).
3. Die Ladeempfehlung wird wie gewohnt per Telegram an dich zurückgesendet.

So bekommst du die Ladeprognose jederzeit **on demand** – unabhängig von Zeitplan oder Automatik!

---

## 🛠️ Tipps & FAQ

**Häufige Fragen:**

* **Kann ich die Pfade frei wählen?**
  Ja! Alle Dateien und Skripte können in beliebigen Ordnern liegen. Passe die Pfade in `token.env` entsprechend an.

* **Mein Bot sendet keine Nachrichten:**
  Prüfe Bot-Token und Chat-ID, und ob der Bot im Chat ist.

* **Cronjobs funktionieren nicht:**
  Prüfe, ob die Skripte ausführbar sind und alle Pfade stimmen.

* **Preisgrenze zu hoch/zu niedrig?**
  Passe `PREIS_GRENZE` in deiner `.env` an – z.B. 0.18 für besonders günstige Phasen.

* **Testausführung trotz Lockfile?**
  Führe das Skript mit `--ignore-lock` aus:

  ```bash
  bash /pfad/zu/tibber-price-check.sh --test --ignore-lock
  ```

---

## ☕️ Mitmachen & Spenden

Du nutzt das Projekt gerne oder hast ein paar Cent gespart?
Unterstütze mich gerne mit einer kleinen Spende:

[![Ko-fi](https://img.shields.io/badge/Buy%20me%20a%20coffee-Ko--fi-FF5E5B?style=flat-square\&logo=ko-fi\&logoColor=white)](https://ko-fi.com/pello1234)

---

## ⚠️ Disclaimer

Dies ist ein Community-Projekt ohne Garantie auf Funktion, Richtigkeit oder Support.
Du benutzt die Skripte auf eigene Gefahr.
