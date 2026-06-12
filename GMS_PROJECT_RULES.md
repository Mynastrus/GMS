# GMS â€“ Project Ruleset

Dieses Dokument definiert **alle verbindlichen Regeln** fÃ¼r das Projekt **GMS**.
Diese Regeln gelten dauerhaft fÃ¼r **Code, Versionierung, Logging, Commits und Tooling**.

---

## 1. Projekt & Repository

* Projektname: **GMS**
* Repository: [https://github.com/Mynastrus/GMS](https://github.com/Mynastrus/GMS)
* Das Repository ist **Ã¶ffentlich**
* Bei allen Ã„nderungen, Analysen oder Erweiterungen ist **dieses Repo die einzige Referenz**
* Zusaetzlich verbindlich zu beachten: `GMS_INTERNAL_RELEASE_NOTES.md` und `GMS_PLAYER_SYNC_BASELINE.md`

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
  * `"CORE"` fÃ¼r die Addon-Basis (Core.lua)
  * `"MOD"` fÃ¼r Module
  * `"EXT"` fÃ¼r Extensions (Core-Erweiterungen)
* `VERSION` **immer als String**
* Versionsformat **exakt**: `"1.0.0"`

---

## 3. Versionierung (SemVer â€“ verpflichtend)

Bei **jeder DateiÃ¤nderung** wird die `METADATA.VERSION` angepasst.

### 3.1 Automatische ErhÃ¶hung

* **PATCH** (`1.0.x`)

  * Bugfixes
  * Refactorings
  * interne LogikÃ¤nderungen

* **MINOR** (`1.x.0`)

  * neue Features
  * neue Module
  * funktionale Erweiterungen

* **MAJOR** (`x.0.0`)

  * Breaking Changes
  * **nur nach expliziter Freigabe**

> Wenn nichts angegeben wird, erfolgt die ErhÃ¶hung **automatisch und korrekt**.

### 3.2 Synchronisation mit GMS.toc

* Eine Ã„nderung an der Version einer einzelnen Lua-Datei **MUSS NICHT** automatisch eine ErhÃ¶hung der Version in der `GMS.toc` auslÃ¶sen.
* Die `## Version`-Angabe in der `GMS.toc` ist die **Source of Truth** fÃ¼r die globale Anzeige.
* Die Versionen der einzelnen Dateien bleiben unabhÃ¤ngig und werden **nicht** zwangsweise angeglichen.
* Die `GMS.toc`-Version wird nur im **Release-Modus** erhÃ¶ht (siehe 3.4 und 11.4).

### 3.4 TOC Versionierung nach Tasks

* Nach einem **echten Release-Task** (gebÃ¼ndelte Auslieferung) **MUSS** die globale Version in der `GMS.toc` erhÃ¶ht werden.
* Normale Entwicklungs-/Update-Commits in einer laufenden Batch-Reihe erhÃ¶hen die `GMS.toc`-Version **nicht**.
* Dies stellt sicher, dass Nutzer nur bei tatsÃ¤chlichen Releases eine neue Addon-Version sehen.

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

âŒ Folgende Kommentare sind **nicht erlaubt**:

* `Buffer is Source of Truth`
* `Notify is only a signal`

---

## 5. Commit-Regeln (verbindlich)

### 5.1 Allgemein

* Commits sind **immer vollstÃ¤ndig kopierbar**
* Keine gekÃ¼rzten oder fragmentierten Commit-Nachrichten

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

* PrÃ¤gnanter Titel in Zeile 1
* Trennlinie unter Titel
* Trennlinie unter jedem Sprachblock
* Format gemÃ¤ÃŸ **GMS Commit Style Guide**

* Format gemÃ¤ÃŸ **GMS Commit Style Guide**

### 5.3 Validierung

Commits, die gegen das Schema in 5.2 verstoÃŸen, sind **ungÃ¼ltig** und mÃ¼ssen korrigiert werden, bevor sie in das Repository aufgenommen werden. Ein Commit **MUSS** alle oben genannten Strukturelemente enthalten.

---

## 6. WoW Itemlinks & Tooltips

### 6.1 Tooltips

* Tooltips **immer** Ã¼ber:

```lua
SetHyperlink(originalLink)
```

---

### 6.2 Lokalisierung von Itemlinks

Ziel: **Lokalisierung ohne VerÃ¤nderung der Spezifikationen**.

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

* Bonus-IDs, Upgrade-Tracks und Stats bleiben **unverÃ¤ndert**
* Nur der Anzeigename wird ersetzt

---

## 7. Modul-Status & Lifecycle (Pflicht)

Jede Erweiterung (Extension) und jedes Modul **MUSS** sich beim Core registrieren, wenn es bereit ist.
Dies geschieht Ã¼ber die Funktion `GMS:SetReady(key)`.

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

## 8. Arbeits- & Antwortregeln fÃ¼r GMS

* Keine stillen Ã„nderungen
* Jede strukturelle Entscheidung wird begrÃ¼ndet
* Auf Anfrage werden **immer komplette Dateien** geliefert
* Commit- und VersionsÃ¤nderungen werden **transparent erklÃ¤rt**

---

## 9. Nebenregel

* Alle gelieferten `/run`-Befehle:

  * **GesamtlÃ¤nge < 250 Zeichen**

---

## 10. GÃ¼ltigkeit

Dieses Regelwerk ist **verbindlich und dauerhaft gÃ¼ltig** fÃ¼r das Projekt GMS.
Ã„nderungen am Regelwerk erfolgen **nur explizit** und werden versioniert dokumentiert.

---

## 11. Release Notes & Changelog (Pflicht)

### 11.1 Changelog-Extension

* Es gibt eine dedizierte Extension `Core/Changelog.lua` mit `TYPE = "EXT"` und eigenem `METADATA`.
* Die Extension **MUSS** eine UI-Seite `CHANGELOG` registrieren.
* Die Seite **MUSS alle Release-EintrÃ¤ge vollstÃ¤ndig anzeigen** (kein hartes Limit wie "nur letzte 5").

### 11.2 Datenstruktur (verbindlich)

* Release-EintrÃ¤ge werden zentral in einer Tabelle `RELEASES` gepflegt.
* Jeder Eintrag **MUSS** folgende Felder enthalten:
  * `version`
  * `date`
  * `title_en`
  * `title_de`
  * `notes_en` (Liste)
  * `notes_de` (Liste)
* Reihenfolge: **neuester Eintrag zuerst**.

### 11.3 Pflege bei Releases

* Bei jeder ErhÃ¶hung von `## Version` in `GMS.toc` **MUSS** ein passender Eintrag in `RELEASES` ergÃ¤nzt werden.
* Inhalt der Release Notes ist immer **zweisprachig (EN + DE)**.
* Changelog-EintrÃ¤ge mÃ¼ssen den tatsÃ¤chlich ausgelieferten Ã„nderungen entsprechen.

### 11.4 Unreleased-Staging (Pflicht)

* Laufende Ã„nderungen werden **nicht direkt** in `Core/Changelog.lua` gesammelt.
* Stattdessen werden sie in `GMS_INTERNAL_RELEASE_NOTES.md` unter `## Unreleased` gepflegt.
* Struktur unter `Unreleased` ist verbindlich:
  * `Added`
  * `Changed`
  * `Fixed`
  * `Rules/Infra`
* Erst bei einem **echten Release** werden die kuratierten Punkte aus `GMS_INTERNAL_RELEASE_NOTES.md` in `RELEASES` (EN + DE) Ã¼bernommen.
* Ein echter Release umfasst mindestens:
  * kuratierter `RELEASES`-Eintrag in `Core/Changelog.lua`
  * ErhÃ¶hung von `## Version` in `GMS.toc`
  * optionales Git-Tag `vX.Y.Z`
* Nach erfolgreichem Release wird `Unreleased` zurÃ¼ckgesetzt (leeren/neu starten), damit die nÃ¤chste Iteration sauber beginnt.

### 11.5 Commit-Abdeckung im Unreleased-Log (Pflicht)

* **Jeder Commit** mit Code-/Config-/DokumentationsÃ¤nderungen **MUSS** in `GMS_INTERNAL_RELEASE_NOTES.md` unter `## Unreleased` erfasst werden.
* Falls ein Commit mehrere Kategorien betrifft, werden die Punkte auf `Added`, `Changed`, `Fixed` und/oder `Rules/Infra` verteilt.
* EintrÃ¤ge mÃ¼ssen mindestens enthalten:
  * kurze Ã„nderungsbeschreibung
  * betroffene Datei(en)
  * optional Commit-Hash zur RÃ¼ckverfolgung
* Vor einem Release ist `Unreleased` auf VollstÃ¤ndigkeit gegen `git log` seit dem letzten Tag zu prÃ¼fen.

### 11.6 CurseForge-Releasepflicht (Pflicht)

* Bei **jedem echten Release** mÃ¼ssen die Addon-Dateien auf CurseForge verÃ¶ffentlicht/aktualisiert werden.
* Die Release-Baseline fÃ¼r die Zielversion basiert verbindlich auf der **aktuellen Interface-Version** aus `GMS/GMS.toc`.
* Das Release-Changelog fÃ¼r die VerÃ¶ffentlichung ist immer **zweisprachig (EN + DE)** und inhaltlich ansprechend/kuratierend zu formulieren.
* Der automatisierte GitHub-Workflow fÃ¼r CurseForge-Uploads ist Teil des Standard-Release-Prozesses und soll bei Tag-Releases bzw. manuellen Release-Runs genutzt werden.
### 11.7 Discord-Release-Post (Pflicht)

* Bei **jedem echten Release** sind zusaetzlich zwei Discord-Posts zu veroeffentlichen.
* Beide Posts **MUESSEN** den CurseForge-Link zur veroeffentlichten Version enthalten.
* Deutsch (polierter Release-Post auf Deutsch):
  * Webhook-Secret: `DISCORD_WEBHOOK_RELEASE_DE`
* Englisch (gleichwertiger, polierter Release-Post auf Englisch):
  * Webhook-Secret: `DISCORD_WEBHOOK_RELEASE_EN`
* Roh-Webhook-URLs duerfen nicht im Repository gespeichert werden (nur lokale Secret-Verwaltung oder CI-Secrets).

## AI Interaction & Artifacts
The following rules apply to the AI assistant's interaction with artifacts:
- **Auto-Approval**: `implementation_plan.md` and `walkthrough.md` should generally be set to `ShouldAutoProceed = true` unless major breaking changes or critical design decisions require explicit user confirmation.
- **Conciseness**: Documentation should be kept as concise as possible, focusing on technical changes and verification results.

---

## 12. Globals-Lokalisierung (Pflicht)

Um "Undefined field"-Warnungen des Linters zu vermeiden und die Performance zu optimieren, **MÃœSSEN** alle verwendeten Blizzard-Globals (APIs, Mixins, UI-Frames, Constants) lokalisiert werden.

### 12.1 Lokalisierungs-Block

Die Lokalisierung erfolgt am Anfang der Datei (nach `METADATA` und den ersten Guards). Der Block **MUSS** durch Diagnose-Kommentare fÃ¼r den Linter abgesichert werden.

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

---

## 12.7 Retail-First API-Regel (Pflicht)

GMS wird **erstrangig fuer WoW Retail** entwickelt.

**Verbindliche Regeln:**

* Wenn eine Blizzard-API als Namespace-Funktion `C_*` existiert und in Retail funktioniert, **MUSS** sie bevorzugt verwendet werden.
* Legacy-Globals (z. B. `GetAddOnInfo`, `GetAddOnCPUUsage`, `GetAddOnMemoryUsage`) sind nur als **Fallback** erlaubt.
* Bei API-Zugriffen ist das Muster verpflichtend:
  * zuerst `C_*` pruefen/verwenden
  * erst danach auf Legacy-Global fallbacken
* Neue Implementierungen duerfen keine Retail-faehige `C_*`-API durch Legacy-Global ersetzen.
* Die gewaehlte API-Reihenfolge (Retail-First + Fallback) ist im Code an der Aufrufstelle kurz nachvollziehbar zu halten.

---

## 13. Text-Lokalisierung (Pflicht)

Alle angezeigten Texte **MÃœSSEN** lokalisierbar sein, sofern es sich nicht um Eigennamen handelt.

### 13.1 Geltungsbereich

Die Regel gilt fÃ¼r:

* Chat-Ausgaben
* UI-Texte
* generierte Texte
* angezeigte Texte
* Tooltip-Texte

### 13.2 Ausnahme

Nicht lokalisierungspflichtig sind nur **Eigennamen** (z. B. Charakter-, NPC-, Instanz- oder Itemnamen aus Blizzard-Daten).

### 13.3 Ablageort der Locales

Die Lokalisierungsdateien befinden sich im Ordner:

* `GMS/Locales/`

### 13.4 Vor-Commit-PrÃ¼fung (Pflicht)

Vor **jedem Commit** muss auf fehlende Lokalisierungen geprÃ¼ft werden.

**Verbindliche MindestprÃ¼fung:**

* Suche nach neu eingefÃ¼hrten, direkt ausgegebenen String-Literalen in Chat/UI/Tooltip-Code.
* PrÃ¼fe, ob jeder neue Text Ã¼ber Locale-Keys (`GMS:T(...)` bzw. modulare Wrapper wie `LT/TR/ST/...`) aufgelÃ¶st wird.
* PrÃ¼fe, ob neue Keys mindestens in `GMS/Locales/enUS.lua` und `GMS/Locales/deDE.lua` vorhanden sind.
* Wenn Keys in anderen Locale-Dateien fehlen, ist ein valider Fallback auf `enUS` sicherzustellen.

Ein Commit ohne diese PrÃ¼fung gilt als **regelwidrig**.

### 13.4.1 Vor-Release-Locale-Vollstaendigkeitspruefung (Pflicht)

Vor **jedem echten Release** sind **alle** Locale-Dateien auf Vollstaendigkeit zu pruefen.

**Verbindliche Regeln:**

* Jeder in `enUS` oder der aktuellen Referenz vorhandene Locale-Key **MUSS** vor Release in **jeder** ausgelieferten Locale-Datei vorhanden sein.
* Fehlende Keys duerfen vor einem Release **nicht** nur ueber Fallback stillschweigend offenbleiben.
* Fehlende Eintraege **MUESSEN** vor dem Release in der **jeweiligen Zielsprache** ergaenzt werden.
* Maschinennahe Platzhaltertexte oder bewusst englische Kopien in fremdsprachigen Locale-Dateien sind nur zulaessig, wenn der Nutzer dies explizit freigibt.
* Die Vor-Release-Pruefung umfasst mindestens alle gepflegten Dateien unter `GMS/Locales/`.

Ein Release ohne diese Vollstaendigkeitspruefung und sprachspezifische Ergaenzung gilt als **regelwidrig**.

### 13.5 deDE-Umlaute (Pflicht)

In `GMS/Locales/deDE.lua` duerfen und sollen echte deutsche Umlaute verwendet werden (`ä`, `ö`, `ü`, `Ä`, `Ö`, `Ü`, `ß`), sofern Encoding/Toolchain dies korrekt unterstuetzt.

* ASCII-Umschreibungen wie `ae`, `oe`, `ue` sind in `deDE` nur noch Fallback-Ausnahme, wenn technische Inkompatibilitaeten nachweisbar sind.
* Neue oder geaenderte `deDE`-Texte sollen standardmaessig mit korrekter deutscher Rechtschreibung inkl. Umlauten gepflegt werden.

### 13.6 Log-Lokalisierung & menschliche Lesbarkeit (Pflicht)

Alle im Addon angezeigten Logs **MÜSSEN** fuer Endnutzer menschlich lesbar und lokalisiert sein.

**Verbindliche Regeln:**

* Technische/roh-formatierte Meldungen (z. B. Protokoll- oder Paketdetails) duerfen intern existieren, muessen in der sichtbaren Log-Ausgabe jedoch in eine nutzerfreundliche Form ueberfuehrt werden.
* Die sichtbare Log-Sprache folgt der aktiven Addon-Sprache (Locale-System via `GMS:T(...)` / Locale-Keys).
* Neue oder geaenderte Log-Texte sind als Locale-Keys zu pflegen (mindestens `enUS` und `deDE`).
* Wenn fuer ein Log-Muster keine Humanisierung existiert, ist dies als Luecke zu behandeln und bei naechster Aenderung nachzuziehen.
* Ziel der Logs: klarer fachlicher Kontext (wer, was, wann, optional wohin), ohne unnoetigen technischen Noise.
