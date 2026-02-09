# GMS – Project Ruleset

Dieses Dokument definiert **alle verbindlichen Regeln** für das Projekt **GMS**.
Diese Regeln gelten dauerhaft für **Code, Versionierung, Logging, Commits und Tooling**.

---

## 1. Projekt & Repository

* Projektname: **GMS**
* Repository: [https://github.com/Mynastrus/GMS](https://github.com/Mynastrus/GMS)
* Das Repository ist **öffentlich**
* Bei allen Änderungen, Analysen oder Erweiterungen ist **dieses Repo die einzige Referenz**

---

## 2. Allgemeine Lua-Dateiregeln

### 2.1 Pflicht: METADATA

Jede Lua-Datei **MUSS** ein lokales `METADATA`-Table enthalten.

```lua
local METADATA = {
	TYPE         = "...",
	INTERN_NAME  = "...",
	SHORT_NAME   = "...",
	DISPLAY_NAME = "...",
	VERSION      = "1.0.0",
}
```

**Verbindliche Regeln:**

* Kein Feld darf fehlen
* `TYPE` **MUSS** einer der folgenden Werte sein:
  * `"CORE"` für die Addon-Basis (Core.lua)
  * `"MOD"` für Module
  * `"EXT"` für Extensions (Core-Erweiterungen)
* `VERSION` **immer als String**
* Versionsformat **exakt**: `"1.0.0"`

---

## 3. Versionierung (SemVer – verpflichtend)

Bei **jeder Dateiänderung** wird die `METADATA.VERSION` angepasst.

### 3.1 Automatische Erhöhung

* **PATCH** (`1.0.x`)

  * Bugfixes
  * Refactorings
  * interne Logikänderungen

* **MINOR** (`1.x.0`)

  * neue Features
  * neue Module
  * funktionale Erweiterungen

* **MAJOR** (`x.0.0`)

  * Breaking Changes
  * **nur nach expliziter Freigabe**

> Wenn nichts angegeben wird, erfolgt die Erhöhung **automatisch und korrekt**.

---

## 4. Logging-System (globale Regel)

### 4.1 Globaler Log-Buffer

Jede Datei stellt sicher, dass der globale Log-Buffer existiert:

```lua
GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}
```

---

### 4.2 LOCAL_LOG (Pflicht)

Jede Lua-Datei **MUSS** eine lokale Logging-Funktion enthalten:

```lua
LOCAL_LOG(level, msg, ...)
```

**Verbindliche Regeln:**

* `type` wird aus `METADATA.TYPE` abgeleitet
* `source` wird aus `METADATA.SHORT_NAME` abgeleitet
* **Kein manueller source-Parameter erlaubt**

### 4.3 Ablauf von LOCAL_LOG

1. Log-Eintrag wird **immer zuerst** in `GMS._LOG_BUFFER` geschrieben

```lua
local idx = #GMS._LOG_BUFFER + 1
GMS._LOG_BUFFER[idx] = entry
```

2. Danach optionaler Notify-Aufruf:

```lua
if GMS._LOG_NOTIFY then
	GMS._LOG_NOTIFY(entry, idx)
end
```

### 4.4 Verbotene Inhalte

❌ Folgende Kommentare sind **nicht erlaubt**:

* `Buffer is Source of Truth`
* `Notify is only a signal`

---

## 5. Commit-Regeln (verbindlich)

### 5.1 Allgemein

* Commits sind **immer vollständig kopierbar**
* Keine gekürzten oder fragmentierten Commit-Nachrichten

---

### 5.2 Sprache & Struktur

* **Zweisprachig: Englisch + Deutsch**
* Feste Struktur:

```
<Titel>

-- [EN] --------------------

	English description

-- [DE] --------------------

	Deutsche Beschreibung

----------------------------

	Liste der bearbeiteten Dateien
```

**Pflichtregeln:**

* Prägnanter Titel in Zeile 1
* Trennlinie unter Titel
* Trennlinie unter jedem Sprachblock
* Format gemäß **GMS Commit Style Guide**

* Format gemäß **GMS Commit Style Guide**

### 5.3 Validierung

Commits, die gegen das Schema in 5.2 verstoßen, sind **ungültig** und müssen korrigiert werden, bevor sie in das Repository aufgenommen werden. Ein Commit **MUSS** alle oben genannten Strukturelemente enthalten.

---

## 6. WoW Itemlinks & Tooltips

### 6.1 Tooltips

* Tooltips **immer** über:

```lua
SetHyperlink(originalLink)
```

---

### 6.2 Lokalisierung von Itemlinks

Ziel: **Lokalisierung ohne Veränderung der Spezifikationen**.

**Verbindliches Muster:**

```lua
local item = Item:CreateFromItemLink(originalLink)
item:ContinueOnItemLoad(function()
	local name = item:GetItemName()
	local localizedLink = originalLink:gsub("%|h%[[^%]]+%]%|h", "|h[" .. name .. "]|h")
	-- use localizedLink
end)
```

**Regeln:**

* Bonus-IDs, Upgrade-Tracks und Stats bleiben **unverändert**
* Nur der Anzeigename wird ersetzt

---

## 7. Modul-Status & Lifecycle (Pflicht)

Jede Erweiterung (Extension) und jedes Modul **MUSS** sich beim Core registrieren, wenn es bereit ist.
Dies geschieht über die Funktion `GMS:SetReady(key)`.

### 7.1 Extensions (Core-Erweiterungen)

* Format: `EXT:<INTERN_NAME>`
* Zeitpunkt: **Am Ende der Datei** (Top-Level)

```lua
-- Am Ende der Datei:
GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)
```

### 7.2 Module (Ace3)

* Format: `MOD:<INTERN_NAME>`
* Zeitpunkt: **Innerhalb von `OnEnable()`**

```lua
function MODULE:OnEnable()
	-- ... initialization ...
	GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
end

function MODULE:OnDisable()
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end
```

---

## 8. Arbeits- & Antwortregeln für GMS

* Keine stillen Änderungen
* Jede strukturelle Entscheidung wird begründet
* Auf Anfrage werden **immer komplette Dateien** geliefert
* Commit- und Versionsänderungen werden **transparent erklärt**

---

## 9. Nebenregel

* Alle gelieferten `/run`-Befehle:

  * **Gesamtlänge < 250 Zeichen**

---

## 10. Gültigkeit

Dieses Regelwerk ist **verbindlich und dauerhaft gültig** für das Projekt GMS.
Änderungen am Regelwerk erfolgen **nur explizit** und werden versioniert dokumentiert.

---

## 11. Retail-Kompatibilität (Pflicht)

Alle Funktionen und API-Aufrufe **MÜSSEN** der **aktuellsten WoW-Retail-Version** entsprechen.

* Veraltete APIs (z.B. aus Classic/Vanilla) sind **verboten**.
* Moderne Namespaces (`C_*`) sind **immer zu bevorzugen**.
* Rückwärtskompatibilität zu Classic wird **nicht** berücksichtigt, wenn sie Retail-Code verkompliziert.
