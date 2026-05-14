# JupyterLab PaaS

JupyterLab auf Virtuozzo PaaS – **ohne Nginx**, direkt via Apache Reverse-Proxy.

## Architektur

```
Browser (HTTPS)
      │
      ▼
Virtuozzo PaaS Domain
      │
      ▼
Apache (Port 80/443)          ← auf dem Python-Node eingebaut
  mod_proxy + mod_rewrite     ← leitet HTTP + WebSocket weiter
      │
      ▼
JupyterLab (127.0.0.1:8888)  ← läuft als nohup-Prozess
      │
      ├── Jupyter-AI (Infomaniak Mistral)
      └── DuckDB
```

## Projektstruktur

```
jupyterlab-paas/
├── .env.example
├── .gitignore
├── .virtuozzo/
│   ├── apache.conf       ← Reverse-Proxy Konfiguration
│   └── deploy.sh         ← vollständiges Deploy-Skript
├── jupyter_lab_config.py
├── notebooks/
├── requirements.txt
└── scripts/
    └── protonpass.sh
```

---

## Deploy auf Virtuozzo PaaS

### 1. Umgebung erstellen

In der Virtuozzo Konsole → **New Environment** → **Python** (3.11) → Create.

### 2. Umgebungsvariablen setzen

Node → Zahnrad → **Variables**:

| Variable | Wert |
|----------|------|
| `JUPYTER_TOKEN` | `python3 -c "import secrets; print(secrets.token_hex(32))"` |
| `JUPYTER_PORT` | `8888` |
| `INFOMANIAK_API_KEY` | dein Infomaniak Token |
| `INFOMANIAK_PRODUCT_ID` | deine Product-ID |

### 3. Git deployen

```bash
git push origin main
```

In Virtuozzo: **Deployment** → Git-URL → Deploy.

### 4. Deploy-Skript ausführen (via Web SSH)

```bash
cd /var/www/webroot/ROOT
bash .virtuozzo/deploy.sh
```

Das Skript:
- Erstellt Virtualenv (mit pip-Bootstrap-Fallback)
- Installiert alle Pakete
- Konfiguriert Apache als Reverse-Proxy
- Startet JupyterLab als Hintergrundprozess
- Richtet Proton Pass Logout-Trap ein

### 5. Proton Pass einloggen

```bash
pass-cli login
```

### 6. JupyterLab aufrufen

```
https://your-env.paas.infomaniak.com/?token=DEIN_JUPYTER_TOKEN
```

---

## Nützliche Befehle (via Web SSH)

```bash
# Log beobachten
tail -f /var/www/webroot/ROOT/jupyter.log

# JupyterLab neu starten
pkill -f "jupyter lab"; sleep 2; bash /var/www/webroot/ROOT/.virtuozzo/deploy.sh

# Apache neu starten
service httpd restart

# Token generieren
python3 -c "import secrets; print(secrets.token_hex(32))"
```

---

## Auto-Start nach Node-Neustart

`deploy.sh` registriert `startup.sh` automatisch als `@reboot` Cron-Job.
Bei jedem Node-Neustart läuft folgende Sequenz automatisch ab:

```
Node startet
    │
    ▼
@reboot Cron → startup.sh
    │
    ├── Apache-Konfig prüfen / wiederherstellen
    ├── Apache starten
    └── JupyterLab starten (nohup)
```

### Cron-Job manuell prüfen

```bash
crontab -l
# Sollte enthalten:
# @reboot bash /var/www/webroot/ROOT/startup.sh >> /var/www/webroot/ROOT/startup.log 2>&1
```

### startup.sh manuell ausführen

```bash
bash /var/www/webroot/ROOT/startup.sh

# Log beobachten
tail -f /var/www/webroot/ROOT/startup.log
```

### Ablauf deploy.sh vs. startup.sh

| | `deploy.sh` | `startup.sh` |
|---|---|---|
| **Wann** | Einmalig nach Git-Deploy | Bei jedem Node-Neustart |
| **Virtualenv** | Erstellt + alle Pakete installiert | Nur geprüft ob vorhanden |
| **Apache** | Konfig installiert + Neustart | Konfig wiederhergestellt + Neustart |
| **JupyterLab** | Gestartet | Gestartet |
| **Proton Pass** | CLI installiert + Login | Logout-Trap eingebunden |
| **Cron-Job** | Registriert | – |
