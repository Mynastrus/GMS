-- ============================================================================
--	GMS/Core/Changelog.lua
--	CHANGELOG EXTENSION
--	- Displays all release notes (EN + DE) inside GMS UI
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local GetTime = GetTime
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GetLocale = GetLocale
local UnitName = UnitName
local GetRealmName = GetRealmName
local _G = _G
---@diagnostic enable: undefined-global

-- ###########################################################################
-- #	METADATA
-- ###########################################################################

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "CHANGELOG",
	SHORT_NAME   = "Changelog",
	DISPLAY_NAME = "Release Notes",
	VERSION      = "1.3.19",
}

-- ###########################################################################
-- #	LOG BUFFER + LOCAL LOGGER
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return type(GetTime) == "function" and GetTime() or nil
end

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time   = now(),
		level  = tostring(level or "INFO"),
		type   = METADATA.TYPE,
		source = METADATA.SHORT_NAME,
		msg    = tostring(msg or ""),
	}

	local n = select("#", ...)
	if n > 0 then
		entry.data = {}
		for i = 1, n do
			entry.data[i] = select(i, ...)
		end
	end

	local idx = #GMS._LOG_BUFFER + 1
	GMS._LOG_BUFFER[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		pcall(GMS._LOG_NOTIFY, entry, idx)
	end
end

local function CT(key, fallback, ...)
	if type(GMS.T) == "function" then
		local ok, txt = pcall(GMS.T, GMS, key, ...)
		if ok and type(txt) == "string" and txt ~= "" and txt ~= key then
			return txt
		end
	end
	if select("#", ...) > 0 then
		return string.format(tostring(fallback or key), ...)
	end
	return tostring(fallback or key)
end

-- ###########################################################################
-- #	EXTENSION REGISTRATION
-- ###########################################################################

GMS:RegisterExtension({
	key = METADATA.INTERN_NAME,
	name = METADATA.SHORT_NAME,
	displayName = METADATA.DISPLAY_NAME,
	version = METADATA.VERSION,
	desc = "In-UI release history (EN + DE)",
})

local Changelog = GMS.Changelog or {}
GMS.Changelog = Changelog

Changelog._options = Changelog._options or nil
Changelog._autoShowDone = Changelog._autoShowDone or false

-- ###########################################################################
-- #	RELEASE DATA (all entries are rendered)
-- ###########################################################################

local RELEASES = {
	{
		version = "2.0.3",
		date = "2026-08-23",
		title_en = "Stable Character Info for Midnight Season 2",
		title_de = "Stabile Charakterinformationen für Midnight Saison 2",
		notes_en = {
			"Fixed the Retail client freeze when opening Character Info by removing synchronous Journal, spellbook, protected-frame, and resize-rebuild work from the panel path.",
			"Updated Character Info with Midnight Season 2 raid names, boss totals, current-lockout Best progress, and safe Mythic+ and raid artwork loading.",
			"Updated the Roster Raid column to report progress for the current raid, The Venomous Abyss, instead of a previous raid tier.",
			"Fixed external character rendering when the Mythic+ API returns multiple texture values and added a safe profile fallback while sync data arrives.",
		},
		notes_de = {
			"Der Retail-Client-Freeze beim Öffnen der Charakterinformationen wurde behoben: Encounter-Journal, Zauberbuch, geschützte Frames und Resize-Rebuilds werden nicht mehr synchron im Panelpfad verarbeitet.",
			"Die Charakterinformationen enthalten aktuelle Midnight-Saison-2-Raidnamen, Bossanzahlen, den Bestwert des aktiven Lockouts sowie sicher geladene Mythic+- und Raidgrafiken.",
			"Die Raidspalte im Roster zeigt nun den Fortschritt im aktuellen Raid Der Giftige Abgrund statt eines früheren Raidtiers.",
			"Die Anzeige externer Charaktere wurde für mehrwertige Mythic+-Textur-APIs korrigiert und erhält einen sicheren Fallback, während Synchronisationsdaten eintreffen.",
		},
	},
	{
		version = "2.0.2",
		date = "2026-08-23",
		title_en = "Retail 12.1 compatibility and current Midnight guild data",
		title_de = "Retail-12.1-Kompatibilität und aktuelle Midnight-Gildendaten",
		notes_en = {
			"Updated the addon TOC for WoW Retail 12.1 / Curse of Ula'tek.",
			"Updated addon enumeration to use the current C_AddOns Retail API first, with a legacy fallback where needed.",
			"Restored guild member counts, online counts, MOTD, and guild-information snapshots with the current C_GuildInfo API.",
			"Updated the character raid view for the current Midnight lineup, including Season 2's Venomous Abyss.",
		},
		notes_de = {
			"Die Addon-TOC wurde für WoW Retail 12.1 / Curse of Ula'tek aktualisiert.",
			"Die Addon-Erkennung nutzt nun vorrangig die aktuelle C_AddOns-Retail-API und bei Bedarf einen Legacy-Fallback.",
			"Mitgliederzahl, Onlinezahl, Gilden-MOTD und Gildeninfos funktionieren wieder über die aktuelle C_GuildInfo-API.",
			"Die Raidansicht der Charakterinformationen wurde für die aktuelle Midnight-Auswahl einschließlich Season 2 und Venomous Abyss aktualisiert.",
		},
	},
	{
		version = "2.0.1",
		date = "2026-06-12",
		title_en = "Midnight live compatibility, portal recovery, and release hygiene hardening",
		title_de = "Midnight-Live-Kompatibilitaet, Teleport-Reparaturen und gehaertete Release-Hygiene",
		notes_en = {
			"Updated live-raid coverage with Midnight raid journal/map mappings and broader alias handling for current retail raid names.",
			"Fixed release-notes auto-open so the main window only opens once per session instead of reopening after load screens or repeated world-entry events.",
			"Reworked CharInfo Mythic+ portal actions for current retail with Retail-first spellbook detection, secure spell buttons, and dungeon-name fallback matching for live season changes.",
			"Expanded the bilingual CurseForge project/start page for a clearer public presentation and onboarding flow.",
			"Added a mandatory pre-release locale completeness audit so every shipped locale must be checked and completed before future releases.",
		},
		notes_de = {
			"Die Live-Raid-Abdeckung wurde mit Midnight-Raid-Journal-/Map-Mappings sowie breiterer Alias-Behandlung fuer aktuelle Retail-Raidnamen erweitert.",
			"Das Auto-Open der Release Notes wurde korrigiert: Das Hauptfenster oeffnet sich pro Session nur noch einmal statt nach Ladescreens oder wiederholten World-Entry-Events erneut aufzuspringen.",
			"Die CharInfo-Mythic+-Teleport-Aktionen wurden fuer aktuelles Retail ueberarbeitet: Retail-First-Spellbook-Erkennung, sichere Spell-Buttons und Dungeonnamen-Fallback fuer Season-Wechsel auf Live.",
			"Die zweisprachige CurseForge-Projekt-/Startseite wurde fuer eine klarere oeffentliche Darstellung und ein besseres Onboarding erweitert.",
			"Eine verpflichtende Vor-Release-Pruefung auf vollstaendige Locales wurde ergaenzt, damit kuenftige Releases jede ausgelieferte Sprache vorab vollstaendig absichern.",
		},
	},
	{
		version = "2.0.0",
		date = "2026-02-26",
		title_en = "Sync V2 rollout, canonical DB cutover, and full locale hardening",
		title_de = "Sync-V2-Rollout, kanonischer DB-Cutover und vollstaendige Lokalisierungs-Haertung",
		notes_en = {
			"Rolled out strict sync protocol V2 with version-gated transport, ANN header contract alignment, and domain allowlisting for safer cross-client compatibility.",
			"Completed canonical database cutover for character and guild data paths, including normalized guild club-id storage and consistent central upsert/index flows.",
			"Upgraded module data domains to V2 across roster, character profile, raids, mythic plus, equipment, and account-link pipelines with compact payload handling.",
			"Hardened UI behavior by disabling protected side-dock operations during combat and resuming deferred dock reflow safely after combat ends.",
			"Closed localization parity across all shipped locales and repaired UTF-8/native-text issues in ruRU, koKR, zhCN, and zhTW for chat and UI output consistency.",
		},
		notes_de = {
			"Das strikte Sync-Protokoll V2 wurde ausgerollt: versionsgebundener Transport, abgestimmter ANN-Header-Vertrag und Domain-Allowlist fuer sichere Client-Kompatibilitaet.",
			"Der kanonische Datenbank-Cutover fuer Charakter- und Gildendaten ist abgeschlossen, inklusive normalisierter Guild-Club-ID-Speicherung und konsistenter zentraler Upsert-/Index-Pfade.",
			"Die Modul-Domaenen wurden durchgaengig auf V2 angehoben (Roster, CharInfo, Raids, MythicPlus, Equipment, Account-Links) mit kompakten Payload-Formaten.",
			"Das UI-Verhalten wurde gehaertet: geschuetzte Side-Dock-Operationen sind im Kampf deaktiviert und Dock-Reflow wird danach sicher verzugert fortgesetzt.",
			"Die Lokalisierungsparitaet wurde fuer alle ausgelieferten Sprachen geschlossen; UTF-8-/Nativtext-Probleme in ruRU, koKR, zhCN und zhTW wurden behoben.",
		},
	},
	{
		version = "1.5.2",
		date = "2026-02-23",
		title_en = "Cross-guild sync visibility, context hydration stability, and roster identity hardening",
		title_de = "Guild-uebergreifende Sync-Sichtbarkeit, stabile Kontext-Hydration und gehaertete Roster-Identitaetsauflosung",
		notes_en = {
			"Comm record lookup now merges domain/key reads across all persisted guild stores and picks the freshest record, preventing hidden data when records are split across guild keys.",
			"Roster character identity handling was hardened with strict Player-GUID validation and stable name-to-GUID fallback paths for transient GUID gaps.",
			"Roster row click navigation now forwards a resolved fallback GUID to CharInfo when live roster GUIDs are missing or invalid.",
			"CharInfo context mode now resolves missing/invalid context GUIDs from roster and stored account-link mappings for more reliable target selection.",
			"CharInfo context bootstrap now requests all relevant sync domains (roster meta, Mythic+, raids, equipment, account links) to hydrate external data consistently.",
		},
		notes_de = {
			"Die Comm-Record-Suche fuehrt Domain-/Key-Abfragen jetzt ueber alle persistierten Guild-Stores zusammen und waehlt jeweils den frischesten Datensatz; dadurch verschwinden keine Daten mehr bei verteilten Guild-Keys.",
			"Die Charakter-Identitaetslogik im Roster wurde mit strikter Player-GUID-Validierung und stabilen Name-zu-GUID-Fallbacks gegen temporaere GUID-Luecken gehaertet.",
			"Beim Klick auf eine Roster-Zeile wird jetzt ein aufgeloester Fallback-GUID an CharInfo uebergeben, falls die Live-Roster-GUID fehlt oder ungueltig ist.",
			"Der CharInfo-Kontextmodus loest fehlende/ungueltige Kontext-GUIDs nun aus Roster- und gespeicherten Account-Link-Mappings auf und stabilisiert damit die Zielauswahl.",
			"Der CharInfo-Kontext-Bootstrap fordert jetzt alle relevanten Sync-Domaenen (Roster-Meta, Mythic+, Raids, Equipment, Account-Links) an, damit externe Daten konsistent hydratisiert werden.",
		},
	},
	{
		version = "1.5.1",
		date = "2026-02-22",
		title_en = "Roster/CharInfo UX completion, account-link correctness, and major runtime performance hardening",
		title_de = "Roster/CharInfo-UX-Abschluss, korrekte Account-Link-Zuordnung und deutlich gehaertete Laufzeit-Performance",
		notes_en = {
			"Completed the requested Roster UX updates with default-expanded Settings tree sections and restored Zone column rendering including alignment/clipping fixes.",
			"CharInfo now keeps Mythic+ default dungeon rows visible even when no synced run payload exists yet, so the card structure remains informative for new/unsynced characters.",
			"AccountInfo account-link resolution was hardened to avoid incorrect cross-character references, including strict selected-GUID validation and safer main-character persistence fallback.",
			"GuildLog persistence was reinforced with guild-key fallback mirroring and reduced scan/refresh pressure to minimize session-loss edge cases and lag spikes.",
			"Dashboard was upgraded to a true system-status landing page with READY/NOT READY overview for extensions/modules and localized status strings.",
		},
		notes_de = {
			"Die angeforderten Roster-UX-Updates wurden abgeschlossen: standardmaessig aufgeklappte Settings-Baumabschnitte sowie wiederhergestellte Zone-Spalte inklusive Ausrichtungs-/Clipping-Fix.",
			"CharInfo zeigt nun die Standard-Mythic+-Dungeons auch ohne synchronisierte Run-Daten, damit die Kartenstruktur fuer neue/unsynchronisierte Charaktere sichtbar bleibt.",
			"Die AccountInfo-Account-Link-Aufloesung wurde gehaertet, um falsche Cross-Character-Referenzen zu vermeiden, inklusive strikter Selected-GUID-Validierung und robuster Main-Character-Persistenz.",
			"Die GuildLog-Persistenz wurde mit guild-key-Fallback-Mirroring stabilisiert und die Scan-/Refresh-Last gesenkt, um Session-Loss-Randfaelle und Lag-Spitzen zu reduzieren.",
			"Das Dashboard wurde zu einer echten Systemstatus-Startseite erweitert (READY/NOT READY fuer Extensions/Module) inklusive lokalisierter Status-Texte.",
		},
	},{
		version = "1.5.0",
		date = "2026-02-18",
		title_en = "Baseline player sync rollout, account/twink resilience, and database reset hardening",
		title_de = "Baseline-Player-Sync-Rollout, robuste Account/Twink-Pfade und gehaertete Datenbank-Reset-Logik",
		notes_en = {
			"Implemented the baseline guild sync flow in Roster/Comm with login announce (ANN), peer response (RESP), missing-domain discovery (NEED/HAVE), and targeted peer fetch from the best available sources.",
			"Added per-domain freshness handling (server timestamp, source GUID, self-report priority) and GUID-claim validation for roster meta messages.",
			"Expanded roster/account sync coverage across required domains: account/twinks, equipment, raids, and MythicPlus.",
			"AccountInfo now falls back to stored/synced account links when guild-verified roster matching is temporarily unavailable, improving CharInfo account character visibility.",
			"Removed automatic one-time database hard-reset execution from startup initialization while keeping manual /gms dbwipe behavior intact.",
			"Improved Comm log readability by resolving sync target GUID keys to class-colored Name-Realm output where possible.",
		},
		notes_de = {
			"Der Baseline-Gildensync in Roster/Comm wurde umgesetzt: Login-Announce (ANN), Peer-Response (RESP), Missing-Domain-Ermittlung (NEED/HAVE) und gezielter Peer-Fetch von den besten verfuegbaren Quellen.",
			"Pro-Domain-Freshness wurde ergaenzt (Server-Timestamp, Source-GUID, Self-Report-Prioritaet) inklusive GUID-Claim-Validierung fuer Roster-Meta-Nachrichten.",
			"Die Sync-Abdeckung fuer Pflicht-Domains wurde erweitert: Account/Twinks, Equipment, Raids und MythicPlus.",
			"AccountInfo nutzt nun einen robusten Stored-/Synced-Fallback, wenn guild-verified Roster-Matches temporaer fehlen; dadurch ist die Account-Char-Anzeige in CharInfo stabiler.",
			"Die automatische One-Time-Datenbank-Hardreset-Ausfuehrung beim Startup wurde entfernt; der manuelle Reset via /gms dbwipe bleibt unveraendert erhalten.",
			"Die Comm-Log-Lesbarkeit wurde verbessert: Sync-Ziel-GUID-Keys werden, wenn moeglich, als klassenfarbiger Name-Realm dargestellt.",
		},
	},
	{
		version = "1.4.9",
		date = "2026-02-18",
		title_en = "Unified logs filtering, submenu reliability fix, and expanded locale-native logs text",
		title_de = "Einheitlicher Logs-Filter, stabiler Submenu-Fix und erweiterte native Logs-Lokalisierung",
		notes_en = {
			"Reworked the Logs header into one unified Filter button with nested Levels and Sources submenus.",
			"Fixed Blizzard UIDropDownMenu submenu population so Levels/Sources lists render reliably instead of showing empty second-level menus.",
			"Localized the new Logs filter/details/status key set in all maintained locale files (DE, ES, FR, IT, KO, PT, RU, ZH-CN, ZH-TW) to avoid mixed-language fallback text.",
			"Added and refined release-facing project content and infrastructure updates, including the bilingual CurseForge start page and rule-set clarifications around localization/release hygiene.",
			"Applied additional module/core maintenance updates across Comm, AccountInfo, CharInfo, Equipment, MythicPlus, and Raids to keep the 1.4.9 baseline consistent.",
		},
		notes_de = {
			"Der Logs-Header wurde auf einen einzigen Filter-Button mit verschachtelten Untermenues fuer Level und Quellen umgestellt.",
			"Die Befuellung der Blizzard-UIDropDownMenu-Submenues wurde korrigiert, sodass Level/Quellen wieder zuverlaessig angezeigt werden statt leerer zweiter Menueebenen.",
			"Der neue Logs-Filter/Details/Status-Key-Satz wurde in allen gepflegten Locale-Dateien (DE, ES, FR, IT, KO, PT, RU, ZH-CN, ZH-TW) nativ lokalisiert, um gemischte Fallback-Texte zu vermeiden.",
			"Release-relevante Projektinhalte und Infrastruktur wurden ergaenzt/geschaerft, inklusive zweisprachiger CurseForge-Startseite und praezisierter Lokalisierungs-/Release-Regeln.",
			"Zusaetzliche Modul-/Core-Wartungsupdates in Comm, AccountInfo, CharInfo, Equipment, MythicPlus und Raids runden die 1.4.9-Baseline konsistent ab.",
		},
	},
	{
		version = "1.4.8",
		date = "2026-02-18",
		title_en = "AccountInfo rollout, Mythic+ interaction upgrades, and settings persistence hardening",
		title_de = "AccountInfo-Rollout, Mythic+-Interaktionsupgrades und gehaertete Einstellungs-Persistenz",
		notes_en = {
			"Added new ACCOUNTINFO module with guild-shared profile fields (name, birthday, gender, main character) and centralized account-link synchronization.",
			"Roster tooltips now list same-account guild characters with class color, level, and online indicator.",
			"CharInfo Mythic+ card now supports clickable dungeon names to open the Adventure Guide and portal icons with cooldown display for eligible timed +10 runs.",
			"Settings dashboard and module option rendering were reworked for stable scrolling/layout and robust input handling.",
			"Hardened AccountInfo persistence and restore flow across reloads with direct profile-store fallback and sync hydration improvements.",
		},
		notes_de = {
			"Neues ACCOUNTINFO-Modul hinzugefuegt mit gildenweit geteilten Profilfeldern (Name, Geburtstag, Geschlecht, Main-Charakter) und zentralisierter Account-Link-Synchronisierung.",
			"Roster-Tooltips zeigen jetzt verknuepfte Gildencharaktere desselben Accounts inklusive Klassenfarbe, Stufe und Online-Indikator.",
			"Die Mythic+-Karte in CharInfo unterstuetzt nun klickbare Dungeon-Namen zum Oeffnen des Abenteuerfuehrers sowie Portal-Icons mit Cooldown-Anzeige fuer qualifizierte +10 In-Time-Runs.",
			"Settings-Dashboard und Module-Options-Rendering wurden fuer stabiles Scrolling/Layout und robustes Input-Handling ueberarbeitet.",
			"AccountInfo-Persistenz und Restore-Flow ueber Reloads wurden gehaertet, inklusive direktem Profil-Store-Fallback und verbesserter Sync-Hydration.",
		},
	},
	{
		version = "1.4.7",
		date = "2026-02-16",
		title_en = "Account-link sync rollout, CharInfo equipment polish, and roster noise reduction",
		title_de = "Account-Link-Sync-Rollout, CharInfo-Equipment-Polish und weniger Roster-Rauschen",
		notes_en = {
			"Added synced account-link publishing and retrieval in Roster via ACCOUNT_CHARS_V1 with digest/cooldown guards and guild-verified resolution paths.",
			"Expanded CharInfo account character handling to use the new synced/local account-link pipeline with improved source fallback behavior.",
			"Refined CharInfo equipment presentation with tighter row spacing, dedicated TSET and VZ columns, right-aligned per-slot item levels, and a right-aligned total item level header.",
			"Equipment view now keeps all defined slots visible even when no snapshot entry exists, so empty slots are shown consistently without placeholder item text.",
			"Reduced repetitive Roster INFO logs for local account tracking by excluding operational reason updates from structural change detection.",
		},
		notes_de = {
			"Im Roster wurde synchronisierte Account-Link-Publikation und -Abfrage ueber ACCOUNT_CHARS_V1 eingefuehrt, inklusive Digest-/Cooldown-Schutz und gildenverifizierter Aufloesung.",
			"Die CharInfo-Account-Char-Verarbeitung nutzt jetzt die neue Sync-/Local-Account-Link-Pipeline mit verbessertem Source-Fallback-Verhalten.",
			"Die CharInfo-Equipment-Darstellung wurde gestrafft: engerer Zeilenabstand, eigene TSET- und VZ-Spalten, rechtsbuendige Slot-Itemlevel sowie rechtsbuendiger Gesamt-Itemlevel-Header.",
			"Die Equipment-Ansicht zeigt nun alle definierten Slots auch ohne Snapshot-Eintrag; leere Slots bleiben konsistent sichtbar ohne Platzhalter-Itemtext.",
			"Wiederholte Roster-INFO-Logs beim lokalen Account-Tracking wurden reduziert, da reine Reason-Updates nicht mehr als strukturelle Aenderung gewertet werden.",
		},
	},
	{
		version = "1.4.6",
		date = "2026-02-15",
		title_en = "Unified persistence reset and resilient character data pipelines",
		title_de = "Einheitlicher Persistenz-Reset und robuste Charakterdaten-Pipelines",
		notes_en = {
			"Added a one-time database reset gate for 1.4.6 plus /gms dbwipe aliases to rebuild a clean data baseline when needed.",
			"Reworked CharInfo into a structured, scrollable card layout with localized faction text, interactive equipment item links/tooltips, and streamlined context actions.",
			"Added /gms raids scan and expanded 12.x raid ingest fallbacks (SavedInstances mapping, name/difficulty fallback keys, digest-based publish triggers).",
			"Hardened RAIDS and EQUIPMENT persistence by writing directly into GMS_DB.global.characters[GUID] and eliminating shared table defaults via deep-copy initialization.",
			"Fixed protected-action/UI regressions including target taint paths, a TOC load-entry issue, raid init nil-call edge cases, and remaining syntax diagnostics.",
		},
		notes_de = {
			"Ein versionsgesteuerter One-Time-Datenbankreset fuer 1.4.6 wurde ergaenzt; inklusive /gms dbwipe und Aliasen fuer einen sauberen Daten-Neustart bei Bedarf.",
			"CharInfo wurde als strukturierte, scrollbare Kartenansicht ueberarbeitet (lokalisierte Fraktionsanzeige, klickbare Equipment-Itemlinks mit Tooltip, gestraffte Kontextaktionen).",
			"/gms raids scan wurde hinzugefuegt und die 12.x-Raid-Ingest-Fallbacks erweitert (SavedInstances-Mapping, Name-/Schwierigkeits-Fallback-Keys, Digest-basierte Publish-Trigger).",
			"Die Persistenz von RAIDS und EQUIPMENT wurde gehaertet: direkte Speicherung in GMS_DB.global.characters[GUID] plus Deep-Copy-Initialisierung gegen geteilte Tabellen-Defaults.",
			"Protected-Action-/UI-Regressions behoben, u. a. Target-Taint-Pfade, TOC-Ladeeintrag, nil-Call-Randfaelle bei Raid-Init sowie verbleibende Syntax-Diagnostics.",
		},
	},
	{
		version = "1.4.5",
		date = "2026-02-15",
		title_en = "Stability fixes, CharInfo expansion, and release automation polish",
		title_de = "Stabilitaetsfixes, CharInfo-Erweiterung und Release-Automation verfeinert",
		notes_en = {
			"Hardened Raid Encounter Journal readiness checks and API rebinding to avoid nil upvalue calls during initialization.",
			"Stabilized Permissions and Logs page layout/render behavior to prevent compressed content and incorrect initial widths.",
			"Expanded CharInfo profile coverage with Mythic+, raid status, equipment, talents, and PvP summary, prioritizing guild sync records when available.",
			"Guarded CharInfo PvP API calls with protected execution to prevent page build failures from runtime argument errors.",
			"CurseForge publish workflow now attaches a generated bilingual EN/DE markdown changelog directly from the latest release entry.",
		},
		notes_de = {
			"Raid-Encounter-Journal-Readiness und API-Rebinding gehaertet, um nil-Upvalue-Aufrufe waehrend der Initialisierung zu vermeiden.",
			"Layout- und Render-Verhalten von Permissions- und Logs-Seiten stabilisiert, damit Inhalte nicht gequetscht werden und die Initialbreiten korrekt sind.",
			"CharInfo-Profil um Mythic+, Raidstatus, Equipment, Talente und PvP-Status erweitert; vorhandene Guild-Sync-Records werden bevorzugt ausgewertet.",
			"CharInfo-PvP-API-Aufrufe per geschuetzter Ausfuehrung abgesichert, um Seitenaufbau-Fehler bei Laufzeit-Argumentproblemen zu verhindern.",
			"CurseForge-Publish-Workflow sendet jetzt automatisch einen generierten zweisprachigen EN/DE-Markdown-Changelog aus dem neuesten Release-Eintrag mit.",
		},
	},
	{
		version = "1.4.4",
		date = "2026-02-15",
		title_en = "Cross-module roster sync and automated CurseForge delivery",
		title_de = "Moduluebergreifende Roster-Synchronisierung und automatisierte CurseForge-Auslieferung",
		notes_en = {
			"Roster now broadcasts player meta data on online/login/world/guild state transitions so the shown GMS version updates faster across guild members.",
			"Roster now hydrates and displays item level, Mythic+ score, and raid status from persisted sync records (Equipment, MythicPlus, Raids), including startup hydration from existing Comm records.",
			"Equipment, Raids, and MythicPlus modules now use normalized parsing plus digest-based change detection and publish updates to guild sync domains only when data changed.",
			"Added GitHub Actions workflow for CurseForge upload with manual release type selection (release/beta/alpha) and integrated project release rules for bilingual EN/DE changelogs.",
		},
		notes_de = {
			"Das Roster sendet Metadaten jetzt bei Online/Login/World/Guild-Zustandswechseln aktiv, damit die angezeigte GMS-Version gildenweit schneller aktuell ist.",
			"Das Roster uebernimmt und zeigt Itemlevel, Mythic+-Wertung und Raid-Status aus persistierten Sync-Records (Equipment, MythicPlus, Raids), inklusive Initial-Hydration aus vorhandenen Comm-Records.",
			"Die Module Equipment, Raids und MythicPlus nutzen jetzt normalisiertes Parsing mit Digest-basierter Aenderungserkennung und veroeffentlichen nur bei echten Datenaenderungen in die Guild-Sync-Domains.",
			"GitHub-Actions-Workflow fuer CurseForge-Upload mit manueller Release-Type-Auswahl (release/beta/alpha) hinzugefuegt und Projektregeln fuer zweisprachige EN/DE-Release-Notes verankert.",
		},
	},
	{
		version = "1.4.3",
		date = "2026-02-15",
		title_en = "GuildLog persistence hardening and comm loopback guard",
		title_de = "GuildLog-Persistenz gehaertet und Comm-Loopback-Schutz",
		notes_en = {
			"Hardened GuildLog persistence so roster change events and member history remain intact even when guild-scoped DB binding becomes available late.",
			"Stabilized settings persistence for GuildLog options (including chat echo) across reloads and module lifecycle transitions.",
			"Improved GuildLog UI rendering for large datasets by limiting visible rows and rendering in chunks.",
			"Added comm loopback protection so self-originated packets are ignored and no longer trigger local processing noise.",
		},
		notes_de = {
			"GuildLog-Persistenz gehaertet: Roster-Aenderungen und Member-History bleiben erhalten, auch wenn guild-scoped DB-Binding erst spaet verfuegbar ist.",
			"Persistenz der GuildLog-Einstellungen (inkl. Chat-Echo) ueber Reloads und Modul-Lebenszyklus stabilisiert.",
			"GuildLog-UI-Rendering fuer grosse Datenmengen verbessert: sichtbare Zeilen begrenzt und in Chunks aufgebaut.",
			"Comm-Loopback-Schutz ergaenzt: eigene Pakete werden ignoriert und erzeugen keine lokale Verarbeitungsgeraeusche mehr.",
		},
	},
	{
		version = "1.4.2",
		date = "2026-02-15",
		title_en = "Expanded locale coverage and branding consistency",
		title_de = "Erweiterte Sprachabdeckung und konsistentes Branding",
		notes_en = {
			"Added dedicated locale files for frFR, esES, itIT, ptBR, ruRU, koKR, zhCN, and zhTW.",
			"Added centralized locale fallback registration for common WoW locales, including esMX fallback to esES.",
			"Updated Russian locale to Cyrillic strings while keeping all localization keys and format placeholders stable.",
			"Corrected remaining UI branding text from 'Guild Management Suite' to 'Guild Management System'.",
		},
		notes_de = {
			"Dedizierte Locale-Dateien fuer frFR, esES, itIT, ptBR, ruRU, koKR, zhCN und zhTW hinzugefuegt.",
			"Zentrale Fallback-Registrierung fuer gaengige WoW-Sprachen ergaenzt, inkl. esMX-Fallback auf esES.",
			"Russische Locale auf kyrillische Texte umgestellt, bei unveraenderten Localization-Keys und Platzhaltern.",
			"Verbleibenden UI-Branding-Text von 'Guild Management Suite' auf 'Guild Management System' korrigiert.",
		},
	},
	{
		version = "1.4.1",
		date = "2026-02-15",
		title_en = "GuildLog UI recovery and legacy visibility improvements",
		title_de = "GuildLog-UI-Recovery und verbesserte Legacy-Sichtbarkeit",
		notes_en = {
			"Reworked GuildLog page rendering to rebuild reliably on each open and avoid stale page cache state.",
			"Added GuildLog status line in UI showing active DB guild key, entry count, history count, and chat echo state.",
			"Improved guild storage key resolution so existing guild buckets with data are reused consistently.",
			"Added legacy GuildLog migration from old module keys and deprecated guild DB layouts.",
			"When legacy installs have member history but missing activity entries, UI now shows reconstructed history rows as fallback.",
		},
		notes_de = {
			"GuildLog-Seitenrendering ueberarbeitet: wird bei jedem Oeffnen zuverlaessig neu aufgebaut und ist damit cache-stabil.",
			"Statuszeile im GuildLog-UI hinzugefuegt (aktiver DB-Guild-Key, Entry-Anzahl, History-Anzahl, Chat-Echo-Status).",
			"Guild-Storage-Key-Aufloesung verbessert, sodass bestehende Guild-Buckets mit Daten konsistent wiederverwendet werden.",
			"Legacy-Migration fuer GuildLog aus alten Modul-Keys und veralteten Guild-DB-Layouts ergaenzt.",
			"Falls bei Legacy-Installationen Historie vorhanden ist, aber Activity-Entries fehlen, zeigt die UI jetzt rekonstruierte Historienzeilen als Fallback.",
		},
	},
	{
		version = "1.4.0",
		date = "2026-02-14",
		title_en = "Guild data sync foundation and GuildLog module release",
		title_de = "Grundlage fuer Guild-Datensync und GuildLog-Modul-Release",
		notes_en = {
			"Introduced structured guild sync records in Comm with freshness priority (seq > updatedAt), persistence, and whisper fallback for large datasets.",
			"Added the new GuildLog module with dedicated page, dock icon, slash command, and optional chat echo for tracked events.",
			"GuildLog now tracks join/rejoin/leave, promotions/demotions, online state, notes/officer notes, name change, realm change, faction change, race change, and level change.",
			"Improved GuildLog diff stability via GUID-first key matching, history-key migration, queued event emission, and short duplicate suppression.",
			"Fixed GuildLog persistence by hardening guild key resolution and binding storage to guild-scoped options with migration from legacy/in-memory state.",
		},
		notes_de = {
			"Strukturierte Guild-Sync-Records in Comm eingefuehrt: Prioritaetslogik (seq > updatedAt), Persistenz und Whisper-Fallback fuer grosse Datensaetze.",
			"Neues GuildLog-Modul hinzugefuegt: eigene Seite, Dock-Icon, Slash-Command und optionaler Chat-Echo fuer getrackte Ereignisse.",
			"GuildLog trackt jetzt Join/Rejoin/Leave, Befoerderung/Degradierung, Online-Status, Notiz-/Offiziersnotiz-Aenderungen, Namenswechsel, Serverwechsel, Fraktionswechsel, Volkswechsel und Levelaenderungen.",
			"Diff-Stabilitaet im GuildLog verbessert durch GUID-first Key-Matching, History-Key-Migration, Event-Queue und kurze Duplikat-Sperre.",
			"GuildLog-Persistenz behoben durch robustere Guild-Key-Ermittlung und guild-scoped Speicherung mit Migration aus Legacy-/In-Memory-Status.",
		},
	},
	{
		version = "1.3.28",
		date = "2026-02-14",
		title_en = "Global locale system and CharInfo UI redesign",
		title_de = "Globales Locale-System und CharInfo-UI-Redesign",
		notes_en = {
			"Added a global localization system in Locales/ with language files (enUS/deDE) and fallback handling.",
			"Core chat output and multiple UI texts now resolve by client locale (deDE -> German, otherwise English fallback).",
			"CharInfo page was redesigned to a cleaner card-based layout with profile header, structured info cards, and action panel.",
			"Fixed additional Lua diagnostics in Logs/Roster option and global access handling.",
		},
		notes_de = {
			"Globales Lokalisierungssystem im Ordner Locales/ hinzugefuegt, inkl. Sprachdateien (enUS/deDE) und Fallback-Logik.",
			"Core-Chat-Ausgaben und mehrere UI-Texte werden jetzt ueber die Client-Locale aufgeloest (deDE -> Deutsch, sonst Englisch-Fallback).",
			"Die CharInfo-Seite wurde auf ein aufgeraeumtes kartenbasiertes Layout mit Profilkopf, strukturierten Info-Cards und Aktionsbereich umgestellt.",
			"Weitere Lua-Diagnostics in Logs/Roster (Optionen und Global-Zugriffe) behoben.",
		},
	},
	{
		version = "1.3.27",
		date = "2026-02-14",
		title_en = "Release automation now builds ZIP artifacts",
		title_de = "Release-Automation erstellt jetzt ZIP-Artefakte",
		notes_en = {
			"The release script now creates a RELEASE folder automatically at repository root.",
			"After tagging, it packs the complete GMS addon folder into RELEASE/GMS_<TOC_VERSION>.zip.",
			"If an archive for the same version already exists, it is replaced.",
		},
		notes_de = {
			"Das Release-Script erstellt jetzt automatisch einen RELEASE-Ordner im Repository-Root.",
			"Nach dem Tagging wird der komplette GMS-Ordner als RELEASE/GMS_<TOC_VERSION>.zip verpackt.",
			"Falls bereits ein Archiv fuer dieselbe Version existiert, wird es ersetzt.",
		},
	},
	{
		version = "1.3.26",
		date = "2026-02-14",
		title_en = "Packaging workflow alignment for CurseForge",
		title_de = "Packaging-Workflow fuer CurseForge angeglichen",
		notes_en = {
			"Added project-local .pkgmeta packaging configuration for CurseForge builds.",
			"Updated repository ignore rules so .pkgmeta is tracked in git.",
			"Release process remains script-based via tools/release.ps1 with strict TOC/changelog version checks.",
		},
		notes_de = {
			"Projektlokale .pkgmeta-Paketkonfiguration fuer CurseForge-Builds hinzugefuegt.",
			"Ignore-Regeln des Repositories angepasst, damit .pkgmeta in git versioniert wird.",
			"Der Release-Prozess bleibt skriptbasiert ueber tools/release.ps1 mit strikten TOC-/Changelog-Versionspruefungen.",
		},
	},
	{
		version = "1.3.25",
		date = "2026-02-14",
		title_en = "CharInfo redesign and packaging metadata update",
		title_de = "CharInfo-Redesign und Paket-Metadaten-Update",
		notes_en = {
			"CharInfo page was reworked to a cleaner card-based layout with a dedicated actions section.",
			"Player snapshot and context are now displayed as structured key/value lines for faster scanning.",
			"Added refresh action and removed legacy debug-heavy page content.",
			"Added CurseForge project metadata to TOC: X-Curse-Project-ID: 863660.",
		},
		notes_de = {
			"Die CharInfo-Seite wurde auf ein aufgeraeumtes, kartenbasiertes Layout mit eigener Aktionssektion umgestellt.",
			"Spieler-Snapshot und Context werden jetzt als strukturierte Key/Value-Zeilen fuer schnelleres Erfassen angezeigt.",
			"Refresh-Aktion hinzugefuegt und den alten debuglastigen Seiteninhalt entfernt.",
			"CurseForge-Projektmetadaten im TOC ergaenzt: X-Curse-Project-ID: 863660.",
		},
	},
	{
		version = "1.3.24",
		date = "2026-02-14",
		title_en = "Roster polish: row sizing, context actions, and hover isolation",
		title_de = "Roster-Feinschliff: Zeilenhoehe, Kontextaktionen und Hover-Isolation",
		notes_en = {
			"Roster row height increased for cleaner spacing and hover fit.",
			"Context menu now opens at cursor position and invite/whisper actions were hardened for roster names.",
			"Self-invite is blocked in the context menu.",
			"Hover tooltip content was compacted and refined, including guild notes.",
			"Roster hover/tooltip effects are now restricted to the Roster page only and no longer leak into other pages.",
		},
		notes_de = {
			"Die Zeilenhoehe im Roster wurde fuer sauberere Abstaende und besseren Hover-Fit erhoeht.",
			"Das Kontextmenue oeffnet jetzt an der Mausposition; Invite/Whisper-Aktionen wurden fuer Roster-Namen robuster gemacht.",
			"Selbst-Einladungen werden im Kontextmenue blockiert.",
			"Der Hover-Tooltip wurde kompakter und strukturierter gestaltet, inkl. Gildennotizen.",
			"Hover-/Tooltip-Effekte sind jetzt strikt auf die Roster-Seite begrenzt und erscheinen nicht mehr auf anderen Seiten.",
		},
	},
	{
		version = "1.3.23",
		date = "2026-02-14",
		title_en = "Roster UX update: compact tooltips, context menu, and stable layout",
		title_de = "Roster-UX-Update: kompakte Tooltips, Kontextmenue und stabiles Layout",
		notes_en = {
			"Roster now includes new member columns for Last Online, item level, Mythic+ score, raid status, and known GMS version.",
			"Member context menu on right-click added: whisper, copy full name with realm, and invite to group.",
			"Tooltip was reworked into a compact table layout with class-colored name and guild notes.",
			"Header/content alignment was stabilized and column/header width mismatches were fixed.",
			"NEW/NEU marker logic was fixed so seen releases are no longer marked as new.",
		},
		notes_de = {
			"Das Roster enthaelt jetzt neue Mitgliederspalten fuer Zuletzt online, Itemlevel, Mythic+-Wertung, Raidstatus und bekannte GMS-Version.",
			"Kontextmenue per Rechtsklick auf Spieler hinzugefuegt: Anfluestern, Vollnamen mit Realm kopieren und in Gruppe einladen.",
			"Tooltip auf kompaktes Tabellenlayout umgestellt, inkl. Klassenfarbe beim Namen und Gildennotizen.",
			"Header-/Content-Ausrichtung stabilisiert und Breitenabweichungen zwischen Titelzeile und Spalten behoben.",
			"NEW/NEU-Markierungslogik korrigiert, sodass gesehene Releases nicht mehr als neu markiert werden.",
		},
	},
	{
		version = "1.3.22",
		date = "2026-02-14",
		title_en = "Roster hotfix: visibility filter function initialization",
		title_de = "Roster-Hotfix: Initialisierung der Sichtbarkeits-Filterfunktion",
		notes_en = {
			"Fixed Lua runtime error in Roster where FilterMembersByVisibility could be called before local initialization.",
			"Added local forward declaration so async roster build can safely call the filter function.",
		},
		notes_de = {
			"Lua-Laufzeitfehler im Roster behoben, bei dem FilterMembersByVisibility vor der lokalen Initialisierung aufgerufen werden konnte.",
			"Lokale Forward-Declaration ergaenzt, damit der asynchrone Roster-Build die Filterfunktion sicher aufrufen kann.",
		},
	},
	{
		version = "1.3.21",
		date = "2026-02-14",
		title_en = "Logs polish and major roster UX/performance update",
		title_de = "Logs-Feinschliff und groesseres Roster-UX/Performance-Update",
		notes_en = {
			"Logs: empty messages are filtered out from list and copy export.",
			"Logs: level selector now uses a robust dropdown menu and reflows correctly on resize/new entries.",
			"Roster: reduced UI churn via debounced roster updates and safer incremental/full rebuild decisions.",
			"Roster: guild header now shows guild name prominently, plus server/faction, with right-aligned online/offline toggles.",
			"Roster: added leading presence bullet per member (green online, gray offline, yellow AFK, red DND).",
			"Roster: sort indicator visibility fixed in header.",
		},
		notes_de = {
			"Logs: leere Messages werden in Liste und Copy-Export nicht mehr angezeigt.",
			"Logs: der Level-Selektor nutzt jetzt ein robustes Dropdown-Menue und reflowt korrekt bei Resize/neuen Eintraegen.",
			"Roster: UI-Last reduziert durch entprellte Roster-Updates und robustere Entscheidungen zwischen inkrementellem Update und Full-Rebuild.",
			"Roster: Header zeigt den Gildennamen prominent sowie Server/Fraktion; Online/Offline-Filter sind rechtsbuendig klickbar.",
			"Roster: fuehrender Presence-Bullet pro Spieler hinzugefuegt (gruen online, grau offline, gelb AFK, rot DND).",
			"Roster: Sichtbarkeit des Sortierindikators im Header korrigiert.",
		},
	},
	{
		version = "1.3.20",
		date = "2026-02-14",
		title_en = "Logs console redesign and flexible level filtering",
		title_de = "Logs-Konsole ueberarbeitet und Level-Filter flexibilisiert",
		notes_en = {
			"Logs list layout was compacted with adaptive columns so entries remain on a single line at default window size.",
			"Logs controls were moved into the global page header, and entries now render directly in content without an extra InlineGroup.",
			"Level filtering now uses a multi-select dropdown menu (Select All/None + TRACE/DEBUG/INFO/WARN/ERROR) with persistent per-level visibility.",
			"Legacy min-level setting is migrated automatically to the new per-level visibility flags.",
			"Logs dock icon now uses the bottom right-dock lane (with top-lane fallback for compatibility).",
		},
		notes_de = {
			"Das Layout der Logs-Liste wurde verdichtet und nutzt adaptive Spalten, sodass Eintraege in der Standardfenstergroesse einzeilig bleiben.",
			"Die Logs-Steuerung wurde in den globalen Seiten-Header verschoben; die Eintraege werden nun direkt im Content ohne zusaetzliche InlineGroup gerendert.",
			"Der Level-Filter nutzt jetzt ein Multi-Select-Dropdown (Alles/Keins + TRACE/DEBUG/INFO/WARN/ERROR) mit persistenter Sichtbarkeit pro Level.",
			"Das bisherige Min-Level-Setting wird automatisch auf die neuen Sichtbarkeits-Flags pro Level migriert.",
			"Das Logs-Dock-Icon wird jetzt im unteren RightDock-Bereich registriert (mit Top-Fallback fuer Kompatibilitaet).",
		},
	},
	{
		version = "1.3.19",
		date = "2026-02-14",
		title_en = "Visual NEW marker for unseen release entries",
		title_de = "Visueller NEU-Marker fuer ungesehene Release-Eintraege",
		notes_en = {
			"Release entries newer than the last seen changelog version are now marked with NEW.",
			"Marker text is locale-dependent (EN: NEW, DE: NEU).",
		},
		notes_de = {
			"Release-Eintraege neuer als die zuletzt gesehene Changelog-Version werden jetzt mit NEU markiert.",
			"Marker-Text ist locale-abhaengig (EN: NEW, DE: NEU).",
		},
	},
	{
		version = "1.3.16",
		date = "2026-02-14",
		title_en = "Dedicated SavedVariable persistence for auto-open state",
		title_de = "Dedizierte SavedVariable-Persistenz fuer Auto-Open-Status",
		notes_en = {
			"Added standalone SavedVariable storage for changelog seen state.",
			"Auto-open seen-version check now uses profile, AceDB global, and standalone fallback.",
			"This prevents repeated opening when AceDB namespaces are delayed or unavailable.",
		},
		notes_de = {
			"Eigenstaendige SavedVariable-Speicherung fuer den Changelog-Status hinzugefuegt.",
			"Seen-Version-Pruefung nutzt jetzt Profil, AceDB-Global und eigenstaendigen Fallback.",
			"Damit wird wiederholtes Oeffnen verhindert, auch wenn AceDB-Namespace verzoegert ist.",
		},
	},
	{
		version = "1.3.15",
		date = "2026-02-14",
		title_en = "Persisted seen-version fallback storage",
		title_de = "Persistenter Fallback fuer gesehene Version",
		notes_en = {
			"Added global fallback persistence for last seen changelog version in GMS_DB.",
			"Auto-open check now reads seen version from profile and global fallback.",
			"Seen version write now updates both profile options and global fallback.",
		},
		notes_de = {
			"Globalen Fallback fuer persistente lastSeenVersion in GMS_DB hinzugefuegt.",
			"Auto-Open prueft gesehene Version jetzt aus Profil und globalem Fallback.",
			"Beim Speichern wird die gesehene Version jetzt in Profil und global geschrieben.",
		},
	},
	{
		version = "1.3.14",
		date = "2026-02-14",
		title_en = "Auto-open repeat prevention",
		title_de = "Wiederholtes Auto-Open verhindert",
		notes_en = {
			"Auto-open now marks the current version as seen immediately after opening the changelog.",
			"This prevents repeated opening on every reload for the same version.",
		},
		notes_de = {
			"Auto-Open markiert die aktuelle Version jetzt direkt nach dem Oeffnen als gesehen.",
			"Damit wird wiederholtes Oeffnen bei jedem Reload fuer dieselbe Version verhindert.",
		},
	},
	{
		version = "1.3.13",
		date = "2026-02-14",
		title_en = "Auto-open trigger hardening",
		title_de = "Auto-Open Trigger gehaertet",
		notes_en = {
			"Auto-open now triggers from PLAYER_LOGIN and PLAYER_ENTERING_WORLD.",
			"Auto-open no longer depends on a matching release entry for the current version.",
			"Option handling is now tolerant: only explicit false disables auto-open.",
		},
		notes_de = {
			"Auto-Open wird jetzt von PLAYER_LOGIN und PLAYER_ENTERING_WORLD ausgeloest.",
			"Auto-Open haengt nicht mehr von einem exakt passenden Release-Eintrag ab.",
			"Options-Handling ist toleranter: nur explizites false deaktiviert Auto-Open.",
		},
	},
	{
		version = "1.3.12",
		date = "2026-02-14",
		title_en = "Reliable auto-open after reload/login",
		title_de = "Zuverlaessiges Auto-Open nach Reload/Login",
		notes_en = {
			"Auto-open now only marks release notes as seen when the CHANGELOG page is actually active.",
			"Added retries if UI/pages are not fully registered yet during login.",
		},
		notes_de = {
			"Auto-Open markiert Release Notes jetzt erst als gesehen, wenn die CHANGELOG-Seite wirklich aktiv ist.",
			"Retry-Logik hinzugefuegt, falls UI/Pages beim Login noch nicht vollstaendig registriert sind.",
		},
	},
	{
		version = "1.3.11",
		date = "2026-02-14",
		title_en = "Locale-bound language and reliable auto-open",
		title_de = "Clientgebundene Sprache und zuverlaessiges Auto-Open",
		notes_en = {
			"Release note language is now bound to client locale.",
			"Date format is now locale-aware (DE: DD.MM.YYYY, EN: MM/DD/YYYY).",
			"Auto-open for new releases now retries until options/UI are available.",
		},
		notes_de = {
			"Die Sprache der Release Notes ist jetzt an die Client-Locale gebunden.",
			"Datumsformat ist jetzt locale-abhaengig (DE: DD.MM.YYYY, EN: MM/DD/YYYY).",
			"Auto-Open fuer neue Releases versucht es jetzt erneut, bis Optionen/UI verfuegbar sind.",
		},
	},
	{
		version = "1.3.10",
		date = "2026-02-14",
		title_en = "Language selection for release notes",
		title_de = "Sprachauswahl fuer Release Notes",
		notes_en = {
			"Added language mode option: AUTO, DE, EN.",
			"AUTO now resolves to German on deDE clients, English otherwise.",
			"Added UI buttons to switch language directly on the changelog page.",
		},
		notes_de = {
			"Sprachmodus-Option hinzugefuegt: AUTO, DE, EN.",
			"AUTO waehlt auf deDE-Clients Deutsch, sonst Englisch.",
			"UI-Buttons zum direkten Sprachwechsel auf der Changelog-Seite hinzugefuegt.",
		},
	},
	{
		version = "1.3.9",
		date = "2026-02-14",
		title_en = "Auto-open for new release notes added",
		title_de = "Auto-Open fuer neue Release Notes hinzugefuegt",
		notes_en = {
			"Added one-time auto-open of changelog on first login after an update.",
			"Added persistent and user-toggleable option to disable auto-open.",
			"Added per-profile tracking of the last seen addon version.",
		},
		notes_de = {
			"Einmaliges Auto-Open des Changelogs beim ersten Login nach einem Update hinzugefuegt.",
			"Persistente und deaktivierbare Option fuer Auto-Open hinzugefuegt.",
			"Profilbasierte Speicherung der zuletzt gesehenen Addon-Version hinzugefuegt.",
		},
	},
	{
		version = "1.3.8",
		date = "2026-02-14",
		title_en = "Changelog extension introduced",
		title_de = "Changelog-Extension eingefuehrt",
		notes_en = {
			"Added in-game changelog page that renders all releases.",
			"Added bilingual release note structure (EN + DE) per release.",
			"Updated project rules for changelog maintenance.",
		},
		notes_de = {
			"Ingame-Changelog-Seite hinzugefuegt, die alle Releases anzeigt.",
			"Zweisprachige Struktur (EN + DE) pro Release eingefuehrt.",
			"Projektregeln fuer die Changelog-Pflege erweitert.",
		},
	},
	{
		version = "1.3.7",
		date = "2026-02-14",
		title_en = "Security and rules compliance update",
		title_de = "Security- und Rule-Compliance-Update",
		notes_en = {
			"Comm sender validation hardened against spoofed packet sources.",
			"UI active-page persistence fixed and SavedVariables aligned.",
			"Permissions and lifecycle compliance fixes applied.",
		},
		notes_de = {
			"Comm-Sender-Validierung gegen gespoofte Paketquellen gehaertet.",
			"UI-Active-Page-Persistenz repariert und SavedVariables abgeglichen.",
			"Permissions- und Lifecycle-Compliance-Fixes umgesetzt.",
		},
	},
	{
		version = "1.3.6",
		date = "2026-02-14",
		title_en = "Permissions persistence stabilization",
		title_de = "Stabilisierung der Permissions-Persistenz",
		notes_en = {
			"Resolved persistence issues in permissions profile data.",
		},
		notes_de = {
			"Persistenzprobleme in den Permissions-Profildaten behoben.",
		},
	},
	{
		version = "1.0.1",
		date = "2026-02-14",
		title_en = "First tagged baseline",
		title_de = "Erster getaggter Stand",
		notes_en = {
			"Repository baseline release tag.",
		},
		notes_de = {
			"Baseline-Release-Tag des Repositories.",
		},
	},
}

local CHANGELOG_OPTIONS_DEFAULTS = {
	showOnNewVersion = {
		type = "toggle",
		name = CT("CHANGELOG_OPT_SHOW_ON_LOGIN", "Show new release notes automatically on login"),
		default = true,
	},
}

local function GetCurrentAddonVersion()
	local v = tostring((GMS and GMS.VERSION) or "")
	v = v:gsub("^%s+", ""):gsub("%s+$", "")
	return v
end

local function NormalizeVersion(v)
	return tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function GetSeenFallbackStore()
	if type(_G) ~= "table" then return nil end
	_G.GMS_UIDB = type(_G.GMS_UIDB) == "table" and _G.GMS_UIDB or {}
	_G.GMS_UIDB.changelog = type(_G.GMS_UIDB.changelog) == "table" and _G.GMS_UIDB.changelog or {}
	return _G.GMS_UIDB.changelog
end

local function GetRawProfileChangelogStore()
	if type(_G) ~= "table" then return nil end
	local rawDB = rawget(_G, "GMS_DB")
	if type(rawDB) ~= "table" then return nil end
	rawDB.profiles = type(rawDB.profiles) == "table" and rawDB.profiles or {}
	rawDB.profileKeys = type(rawDB.profileKeys) == "table" and rawDB.profileKeys or {}

	local profileName = nil
	if type(GMS) == "table" and type(GMS.db) == "table" and type(GMS.db.GetCurrentProfile) == "function" then
		local ok, current = pcall(GMS.db.GetCurrentProfile, GMS.db)
		if ok and type(current) == "string" and current ~= "" then
			profileName = current
		end
	end

	if not profileName or profileName == "" then
		local name = type(UnitName) == "function" and tostring(UnitName("player") or "") or ""
		local realm = type(GetRealmName) == "function" and tostring(GetRealmName() or "") or ""
		if name ~= "" and realm ~= "" then
			local charKey = string.format("%s - %s", name, realm)
			local mapped = rawDB.profileKeys[charKey]
			if type(mapped) == "string" and mapped ~= "" then
				profileName = mapped
			end
		end
	end

	if not profileName or profileName == "" then
		local onlyName = nil
		local count = 0
		for k in pairs(rawDB.profiles) do
			if type(k) == "string" and k ~= "" then
				count = count + 1
				if not onlyName then onlyName = k end
				if count > 1 then break end
			end
		end
		if count == 1 and onlyName then
			profileName = onlyName
		end
	end

	if not profileName or profileName == "" then
		return nil
	end

	rawDB.profiles[profileName] = type(rawDB.profiles[profileName]) == "table" and rawDB.profiles[profileName] or {}
	local profile = rawDB.profiles[profileName]
	profile.modules = type(profile.modules) == "table" and profile.modules or {}
	profile.modules.CHANGELOG = type(profile.modules.CHANGELOG) == "table" and profile.modules.CHANGELOG or {}
	return profile.modules.CHANGELOG
end

local function HasReleaseEntry(version)
	local v = tostring(version or "")
	if v == "" then return false end
	for i = 1, #RELEASES do
		if tostring(RELEASES[i].version or "") == v then
			return true
		end
	end
	return false
end

local function IsAutoOpenEnabled(opts)
	if type(opts) ~= "table" then return true end
	-- Only an explicit boolean false disables the feature.
	return opts.showOnNewVersion ~= false
end

local function GetEffectiveSeenVersion(opts)
	local profileSeen = (type(opts) == "table") and NormalizeVersion(opts.lastSeenVersion) or ""
	if profileSeen ~= "" then
		return profileSeen
	end
	local rawProfile = GetRawProfileChangelogStore()
	if type(rawProfile) == "table" then
		local rawSeen = NormalizeVersion(rawProfile.lastSeenVersion)
		if rawSeen ~= "" then
			return rawSeen
		end
	end
	local fb = GetSeenFallbackStore()
	if type(fb) == "table" then
		local fallbackSeen = NormalizeVersion(fb.lastSeenVersion)
		if fallbackSeen ~= "" then
			return fallbackSeen
		end
	end
	return ""
end

local function IsReleaseNewForSeenVersion(releaseVersion, seenVersion)
	local target = tostring(releaseVersion or "")
	local seen = tostring(seenVersion or "")
	if target == "" then return false end
	if seen == "" then return true end
	if target == seen then return false end

	for i = 1, #RELEASES do
		local v = tostring(RELEASES[i].version or "")
		if v == seen then
			return false
		end
		if v == target then
			return true
		end
	end
	return false
end

local function EnsureOptions()
	if not GMS or type(GMS.RegisterModuleOptions) ~= "function" then
		return nil
	end

	pcall(function()
		GMS:RegisterModuleOptions(METADATA.INTERN_NAME, CHANGELOG_OPTIONS_DEFAULTS, "PROFILE")
	end)

	if type(GMS.GetModuleOptions) ~= "function" then
		return nil
	end

	local ok, opts = pcall(GMS.GetModuleOptions, GMS, METADATA.INTERN_NAME)
	if not ok or type(opts) ~= "table" then
		return nil
	end

	if opts.showOnNewVersion == nil then
		opts.showOnNewVersion = true
	end
	if type(opts.lastSeenVersion) ~= "string" then
		opts.lastSeenVersion = ""
	end
	if type(opts.lastSeenAt) ~= "number" then
		opts.lastSeenAt = 0
	end
	if NormalizeVersion(opts.lastSeenVersion) == "" then
		local rawProfile = GetRawProfileChangelogStore()
		if type(rawProfile) == "table" then
			local rawSeen = NormalizeVersion(rawProfile.lastSeenVersion)
			if rawSeen ~= "" then
				opts.lastSeenVersion = rawSeen
			end
			local rawAt = tonumber(rawProfile.lastSeenAt or 0) or 0
			if rawAt > 0 and tonumber(opts.lastSeenAt or 0) <= 0 then
				opts.lastSeenAt = rawAt
			end
		end
		local fb = GetSeenFallbackStore()
		if type(fb) == "table" then
			local fallbackSeen = NormalizeVersion(fb.lastSeenVersion)
			if fallbackSeen ~= "" then
				opts.lastSeenVersion = fallbackSeen
			end
			local fallbackAt = tonumber(fb.lastSeenAt or 0) or 0
			if fallbackAt > 0 and tonumber(opts.lastSeenAt or 0) <= 0 then
				opts.lastSeenAt = fallbackAt
			end
		end
	end

	Changelog._options = opts
	return opts
end

local function ResolveLanguageMode()
	local locale = ""
	if type(GMS.GetLanguage) == "function" then
		locale = tostring(GMS:GetLanguage() or "")
	elseif type(GetLocale) == "function" then
		locale = tostring(GetLocale() or "")
	end

	if locale == "deDE" then
		return "DE"
	end
	return "EN"
end

local function IsEnglishFallbackActive()
	local locale = ""
	if type(GMS.GetLanguage) == "function" then
		locale = tostring(GMS:GetLanguage() or "")
	elseif type(GetLocale) == "function" then
		locale = tostring(GetLocale() or "")
	end

	if locale == "deDE" or locale == "enUS" or locale == "enGB" then
		return false
	end
	return true
end

local function FormatDateByLanguage(isoDate, languageMode)
	local y, m, d = tostring(isoDate or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not y or not m or not d then
		return tostring(isoDate or "?")
	end

	if languageMode == "DE" then
		return d .. "." .. m .. "." .. y
	end
	return m .. "/" .. d .. "/" .. y
end

local function MarkCurrentVersionSeen(reason)
	local opts = Changelog._options or EnsureOptions()

	local current = GetCurrentAddonVersion()
	if current == "" then return end

	if type(opts) == "table" then
		opts.lastSeenVersion = current
		opts.lastSeenAt = now() or 0
	end
	local rawProfile = GetRawProfileChangelogStore()
	if type(rawProfile) == "table" then
		rawProfile.lastSeenVersion = current
		rawProfile.lastSeenAt = now() or 0
	end
	local fb = GetSeenFallbackStore()
	if type(fb) == "table" then
		fb.lastSeenVersion = current
		fb.lastSeenAt = now() or 0
	end
	LOCAL_LOG("INFO", "Marked changelog as seen", current, reason or "unknown")
end

local function TryAutoOpenOnLogin(attempt)
	attempt = tonumber(attempt) or 1
	if Changelog._autoShowDone then
		return
	end

	local opts = Changelog._options or EnsureOptions()
	if type(opts) ~= "table" then
		if attempt < 20 and C_Timer and C_Timer.After then
			C_Timer.After(0.5, function()
				TryAutoOpenOnLogin(attempt + 1)
			end)
		else
			LOCAL_LOG("WARN", "Changelog options unavailable for auto-open")
		end
		return
	end

	if not IsAutoOpenEnabled(opts) then
		Changelog._autoShowDone = true
		LOCAL_LOG("DEBUG", "Auto-open disabled by profile option")
		return
	end

	local current = GetCurrentAddonVersion()
	if current == "" then
		LOCAL_LOG("WARN", "Current addon version unavailable")
		return
	end

	if GetEffectiveSeenVersion(opts) == current then
		Changelog._autoShowDone = true
		LOCAL_LOG("DEBUG", "Current version already seen", current)
		return
	end

	if not HasReleaseEntry(current) then
		LOCAL_LOG("WARN", "No release entry for current version (still trying auto-open)", current)
	end

	local tries = 0
	local function attemptOpen()
		tries = tries + 1
		if GMS.UI and type(GMS.UI.Open) == "function" then
			-- Ensure page exists before opening; UI may be up before page registration finished.
			if not (GMS.UI._pages and GMS.UI._pages[METADATA.INTERN_NAME]) then
				RegisterInUI()
			end

			if GMS.UI._pages and GMS.UI._pages[METADATA.INTERN_NAME] then
				GMS.UI:Open(METADATA.INTERN_NAME)
				MarkCurrentVersionSeen("auto-login-open")
				Changelog._autoShowDone = true
				LOCAL_LOG("INFO", "Auto-opened changelog for new version", current)
				return
			end
		end

		if tries < 40 and C_Timer and C_Timer.After then
			C_Timer.After(0.5, attemptOpen)
		else
			LOCAL_LOG("WARN", "Failed to auto-open changelog (page not available/active)")
		end
	end

	attemptOpen()
end

local function RenderNotes(lines)
	if type(lines) ~= "table" or #lines == 0 then
		return "- n/a"
	end

	local out = {}
	for i = 1, #lines do
		out[#out + 1] = "- " .. tostring(lines[i] or "")
	end
	return table.concat(out, "\n")
end

local function SplitFirstSentence(text)
	local t = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if t == "" then
		return "", ""
	end
	local first, rest = t:match("^(.-%.)(%s+.+)$")
	if first then
		return first, rest:gsub("^%s+", "")
	end
	return t, ""
end

local function BuildReleaseBlock(parent, release, isNew)
	local mode = ResolveLanguageMode()
	local formattedDate = FormatDateByLanguage(release.date, mode)

	local box = AceGUI:Create("InlineGroup")
	box:SetTitle(string.format("v%s (%s)", tostring(release.version or "?"), formattedDate))
	box:SetFullWidth(true)
	box:SetLayout("Flow")
	parent:AddChild(box)

	local titleText = (mode == "DE") and tostring(release.title_de or "-") or tostring(release.title_en or "-")
	local notesText = (mode == "DE") and RenderNotes(release.notes_de) or RenderNotes(release.notes_en)
	local newLabel = (mode == "DE") and "NEU" or "NEW"
	local newBadge = isNew and ("  |cff00ff00[" .. newLabel .. "]|r") or ""

	local title = AceGUI:Create("Label")
	title:SetFullWidth(true)
	title:SetText("|cff03A9F4" .. titleText .. "|r" .. newBadge)
	box:AddChild(title)

	local notes = AceGUI:Create("Label")
	notes:SetFullWidth(true)
	notes:SetText(notesText)
	box:AddChild(notes)
end

local function BuildChangelogPage(root, id, isCached)
	local opts = Changelog._options or EnsureOptions()
	local seenBeforeOpen = GetEffectiveSeenVersion(opts)

	if GMS.UI and type(GMS.UI.Header_BuildIconText) == "function" then
		local mode = ResolveLanguageMode()
		GMS.UI:Header_BuildIconText({
			icon = "Interface\\Icons\\INV_Scroll_03",
			text = "|cff03A9F4" .. METADATA.DISPLAY_NAME .. "|r",
			subtext = (mode == "DE") and "Alle Releases werden angezeigt" or "All releases are shown",
		})
	end

	if GMS.UI and type(GMS.UI.SetStatusText) == "function" then
		GMS.UI:SetStatusText(CT("CHANGELOG_STATUS_LOADED_FMT", "CHANGELOG: %d releases loaded (%s)", #RELEASES, ResolveLanguageMode()))
	end

	if isCached and type(root.ReleaseChildren) == "function" then
		root:ReleaseChildren()
	end

	root:SetLayout("Fill")

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	root:AddChild(scroll)

	if IsEnglishFallbackActive() then
		local fallbackText = CT(
			"CHANGELOG_FALLBACK_NOTICE",
			"Language fallback: This changelog is currently shown in English. Sorry, but providing release notes in all languages would be too much effort right now, so only English and German are available."
		)
		local firstSentence, restText = SplitFirstSentence(fallbackText)

		local fallbackGroup = AceGUI:Create("InlineGroup")
		fallbackGroup:SetTitle("")
		fallbackGroup:SetFullWidth(true)
		fallbackGroup:SetLayout("Flow")
		scroll:AddChild(fallbackGroup)

		local fallbackHeading = AceGUI:Create("Label")
		fallbackHeading:SetFullWidth(true)
		fallbackHeading:SetText("|cff03A9F4" .. firstSentence .. "|r")
		fallbackGroup:AddChild(fallbackHeading)

		if restText ~= "" then
			local fallbackNotice = AceGUI:Create("Label")
			fallbackNotice:SetFullWidth(true)
			fallbackNotice:SetText(restText)
			fallbackGroup:AddChild(fallbackNotice)
		end
	end

	for i = 1, #RELEASES do
		local release = RELEASES[i]
		local isNew = IsReleaseNewForSeenVersion(release.version, seenBeforeOpen)
		BuildReleaseBlock(scroll, release, isNew)
	end

	MarkCurrentVersionSeen("manual-open")
end

local function RegisterInUI()
	if not GMS.UI or type(GMS.UI.RegisterPage) ~= "function" then
		return false
	end

	GMS.UI:RegisterPage(METADATA.INTERN_NAME, 95, METADATA.DISPLAY_NAME, BuildChangelogPage)

	if type(GMS.UI.AddRightDockIconBottom) == "function" then
		GMS.UI:AddRightDockIconBottom({
			id = METADATA.INTERN_NAME,
			order = 2,
			selectable = true,
			icon = "Interface\\Icons\\INV_Scroll_03",
			tooltipTitle = METADATA.DISPLAY_NAME,
			tooltipText = CT("CHANGELOG_DOCK_TOOLTIP", "Shows all release notes"),
			tooltipTextKey = "CHANGELOG_DOCK_TOOLTIP",
			onClick = function()
				if GMS.UI and type(GMS.UI.Open) == "function" then
					GMS.UI:Open(METADATA.INTERN_NAME)
				end
			end,
		})
	end

	return true
end

local function RegisterSlash()
	if type(GMS.Slash_RegisterSubCommand) ~= "function" then
		return false
	end

	GMS:Slash_RegisterSubCommand("changelog", function()
		if GMS.UI and type(GMS.UI.Open) == "function" then
			GMS.UI:Open(METADATA.INTERN_NAME)
		end
	end, {
		helpKey = "CHANGELOG_SLASH_HELP",
		helpFallback = "/gms changelog - opens release notes",
		alias = { "notes", "releases" },
		owner = METADATA.INTERN_NAME,
	})

	return true
end

local function Init()
	EnsureOptions()

	local okUI = RegisterInUI()
	local okSlash = RegisterSlash()

	if okUI then
		LOCAL_LOG("INFO", "Changelog page registered", #RELEASES)
	end
	if okSlash then
		LOCAL_LOG("INFO", "Changelog slash command registered")
	end

	if not okUI and C_Timer and C_Timer.After then
		C_Timer.After(0.5, Init)
	end
end

Init()

if not Changelog._loginFrame and CreateFrame then
	Changelog._loginFrame = CreateFrame("Frame")
	Changelog._loginFrame:RegisterEvent("PLAYER_LOGIN")
	Changelog._loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	Changelog._loginFrame:SetScript("OnEvent", function(_, event)
		if event ~= "PLAYER_LOGIN" and event ~= "PLAYER_ENTERING_WORLD" then return end
		if Changelog._autoOpenInitStarted then
			return
		end
		Changelog._autoOpenInitStarted = true
		Changelog._loginFrame:UnregisterAllEvents()
		if C_Timer and C_Timer.After then
			C_Timer.After(1.0, function()
				TryAutoOpenOnLogin()
			end)
		else
			TryAutoOpenOnLogin()
		end
	end)
end

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)
LOCAL_LOG("INFO", "Changelog extension loaded", METADATA.VERSION)

