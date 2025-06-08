# Changelog

## [v1.1.2] – 2025-06-08

### Added
- Hinweis im Forecast, wenn **für heute keine günstigen Strompreise mehr verfügbar** sind
- Hinweis im Forecast, wenn **für morgen zwar Preise**, aber **keine unterhalb der Preisgrenze** vorhanden sind
- Neue Option `--ignore-lock` für das Price-Check-Skript, um mehrfaches Testen zu ermöglichen
- Verbesserte Telegram-Meldungen (Forecast/Reminder) mit klareren Infos

### Fixed
- Reminder-Skript sendet nun **nur noch 1x pro günstiger Phase**, nicht stündlich neu
- `HASH`-Fehler im Testmodus des Reminder-Skripts behoben

### Changed
- README aktualisiert und alle Neuerungen dokumentiert
- Forecast-Skript überarbeitet, um **bei jeder Ausführung** eine Nachricht zu senden (auch ohne günstige Stunden)

## [v1.1.1] – 2025-06-01

### Added
- Ausführliche Anleitung zur Home Assistant Integration per SSH (YAML-Beispiele für shell_command und Automation)
- Infobox zu Container-Setups und SSH
- README verbessert und ergänzt (Home Assistant/SSH-Integration, Hinweise, FAQ)

## [v1.0.0] – 2025-06-01

### Added
- Initial Release: Komplettes Tibber/EVCC/Telegram-Setup mit .env-Konfiguration, Reminder-Block-Logik und ausführlicher Dokumentation.
