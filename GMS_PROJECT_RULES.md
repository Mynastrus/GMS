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

### 3.2 Synchronisation mit GMS.toc

* Eine Änderung an der Version einer einzelnen Lua-Datei **MUSS NICHT** automatisch eine Erhöhung der Version in der `GMS.toc` auslösen.
* Die `## Version`-Angabe in der `GMS.toc` ist die **Source of Truth** für die globale Anzeige.
* Die Versionen der einzelnen Dateien bleiben unabhängig und werden **nicht** zwangsweise angeglichen.
* Die `GMS.toc`-Version wird nur im **Release-Modus** erhöht (siehe 3.4 und 11.4).

### 3.4 TOC Versionierung nach Tasks

* Nach einem **echten Release-Task** (gebündelte Auslieferung) **MUSS** die globale Version in der `GMS.toc` erhöht werden.
* Normale Entwicklungs-/Update-Commits in einer laufenden Batch-Reihe erhöhen die `GMS.toc`-Version **nicht**.
* Dies stellt sicher, dass Nutzer nur bei tatsächlichen Releases eine neue Addon-Version sehen.

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

## 11. Release Notes & Changelog (Pflicht)

### 11.1 Changelog-Extension

* Es gibt eine dedizierte Extension `Core/Changelog.lua` mit `TYPE = "EXT"` und eigenem `METADATA`.
* Die Extension **MUSS** eine UI-Seite `CHANGELOG` registrieren.
* Die Seite **MUSS alle Release-Einträge vollständig anzeigen** (kein hartes Limit wie "nur letzte 5").

### 11.2 Datenstruktur (verbindlich)

* Release-Einträge werden zentral in einer Tabelle `RELEASES` gepflegt.
* Jeder Eintrag **MUSS** folgende Felder enthalten:
  * `version`
  * `date`
  * `title_en`
  * `title_de`
  * `notes_en` (Liste)
  * `notes_de` (Liste)
* Reihenfolge: **neuester Eintrag zuerst**.

### 11.3 Pflege bei Releases

* Bei jeder Erhöhung von `## Version` in `GMS.toc` **MUSS** ein passender Eintrag in `RELEASES` ergänzt werden.
* Inhalt der Release Notes ist immer **zweisprachig (EN + DE)**.
* Changelog-Einträge müssen den tatsächlich ausgelieferten Änderungen entsprechen.

### 11.4 Unreleased-Staging (Pflicht)

* Laufende Änderungen werden **nicht direkt** in `Core/Changelog.lua` gesammelt.
* Stattdessen werden sie in `GMS_INTERNAL_RELEASE_NOTES.md` unter `## Unreleased` gepflegt.
* Struktur unter `Unreleased` ist verbindlich:
  * `Added`
  * `Changed`
  * `Fixed`
  * `Rules/Infra`
* Erst bei einem **echten Release** werden die kuratierten Punkte aus `GMS_INTERNAL_RELEASE_NOTES.md` in `RELEASES` (EN + DE) übernommen.
* Ein echter Release umfasst mindestens:
  * kuratierter `RELEASES`-Eintrag in `Core/Changelog.lua`
  * Erhöhung von `## Version` in `GMS.toc`
  * optionales Git-Tag `vX.Y.Z`
* Nach erfolgreichem Release wird `Unreleased` zurückgesetzt (leeren/neu starten), damit die nächste Iteration sauber beginnt.

### 11.5 Commit-Abdeckung im Unreleased-Log (Pflicht)

* **Jeder Commit** mit Code-/Config-/Dokumentationsänderungen **MUSS** in `GMS_INTERNAL_RELEASE_NOTES.md` unter `## Unreleased` erfasst werden.
* Falls ein Commit mehrere Kategorien betrifft, werden die Punkte auf `Added`, `Changed`, `Fixed` und/oder `Rules/Infra` verteilt.
* Einträge müssen mindestens enthalten:
  * kurze Änderungsbeschreibung
  * betroffene Datei(en)
  * optional Commit-Hash zur Rückverfolgung
* Vor einem Release ist `Unreleased` auf Vollständigkeit gegen `git log` seit dem letzten Tag zu prüfen.

### 11.6 CurseForge-Releasepflicht (Pflicht)

* Bei **jedem echten Release** müssen die Addon-Dateien auf CurseForge veröffentlicht/aktualisiert werden.
* Die Release-Baseline für die Zielversion basiert verbindlich auf der **aktuellen Interface-Version** aus `GMS/GMS.toc`.
* Das Release-Changelog für die Veröffentlichung ist immer **zweisprachig (EN + DE)** und inhaltlich ansprechend/kuratierend zu formulieren.
* Der automatisierte GitHub-Workflow für CurseForge-Uploads ist Teil des Standard-Release-Prozesses und soll bei Tag-Releases bzw. manuellen Release-Runs genutzt werden.
## AI Interaction & Artifacts
The following rules apply to the AI assistant's interaction with artifacts:
- **Auto-Approval**: `implementation_plan.md` and `walkthrough.md` should generally be set to `ShouldAutoProceed = true` unless major breaking changes or critical design decisions require explicit user confirmation.
- **Conciseness**: Documentation should be kept as concise as possible, focusing on technical changes and verification results.

---

## 12. Globals-Lokalisierung (Pflicht)

Um "Undefined field"-Warnungen des Linters zu vermeiden und die Performance zu optimieren, **MÜSSEN** alle verwendeten Blizzard-Globals (APIs, Mixins, UI-Frames, Constants) lokalisiert werden.

### 12.1 Lokalisierungs-Block

Die Lokalisierung erfolgt am Anfang der Datei (nach `METADATA` und den ersten Guards). Der Block **MUSS** durch Diagnose-Kommentare für den Linter abgesichert werden.

**Verbindliches Muster:**

```lua
-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G               = _G
local CreateFrame      = CreateFrame
local GetTime          = GetTime
local UIParent         = UIParent
local C_Timer          = C_Timer
-- ... weitere ...
---@diagnostic enable: undefined-global
```

### 12.2 Verwendung

* Innerhalb der Logik **DARF NICHT** direkt auf `_G.XYZ` zugegriffen werden, wenn `XYZ` ein Blizzard-Global ist.
* Stattdessen wird die lokale Variable `XYZ` verwendet.
* Die Lokalisierung dient als zentrale Stelle zur Absicherung gegen fehlende APIs in verschiedenen WoW-Umgebungen.

