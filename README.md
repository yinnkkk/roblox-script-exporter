# Roblox Script Exporter (Studio → Disk)

This tool exports **all scripts** from a Roblox Studio place to your local filesystem.

Export direction is **one-way only**:
Studio → Disk

Supported script types:
- Script
- LocalScript
- ModuleScript

Rojo is **not required**, but the output is Rojo-compatible.

---

## Requirements

- Roblox Studio
- Python 3.9 or newer
- HTTP Requests enabled in Roblox Studio

---

## Setup

### 1. Download files

You need these two files:
- `export_server.py`
- `roblox_exporter.plugin.lua`

Put them in any folder, for example:

RobloxExporter/
├─ export_server.py
├─ roblox_exporter.plugin.lua

---

### 2. Start the export server

Open a terminal in the folder (for example cd ~/RobloxExporter) and run:

python3 export_server.py

You should see:

Listening on http://127.0.0.1:34873/export


Leave this terminal running.

---

### 3. Install the Studio plugin

In Roblox Studio:
1. Open **Plugins Folder**
2. Select `roblox_exporter.plugin.lua`

A toolbar button called **Roblox Exporter** will appear.

---

### 4. Enable HTTP requests

In Roblox Studio:
1. Go to **File → Game Settings → Security**
2. Enable **Allow HTTP Requests**
3. Save

---

### 5. Export scripts

1. Open your Roblox place
2. Click **Export Scripts** in the plugin toolbar
3. All scripts will be written to disk automatically

Files are created under:

MyGame/
└─ src/
├─ ServerScriptService/
├─ ReplicatedStorage/
├─ StarterPlayer/
└─ ...


If the folder already exists, files are **overwritten**, not duplicated.

---

## Notes

- You can delete the `MyGame` folder at any time and re-export
- Script names with invalid filesystem characters are skipped
- Export is safe and read-only (no Studio data is modified)
- Please create new folders for other games, else it may all merge

---
