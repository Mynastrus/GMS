# GMS Player Sync Baseline (Requested Workflow)

Dieses Dokument hält die gewünschte Vorgehensweise für den initialen GMS-Spielerabgleich fest.

## Ziel

Alle Online-Spieler sollen möglichst schnell einen gemeinsamen, lokalen Datenstand über
alle bekannten Gildenmitglieder aufbauen.

## Datenmodell (Basis pro Spieler)

- `PLAYERGUID`
- `name`
- `realm`
- `level`
- `klasse`
- `rasse`
- `fraktion`
- `gmsVersion`
- Primärschlüssel für Identität/Abgleich: `PLAYERGUID`

## Datenmodell (Accountinformationen, gleicher Zyklus)

Zusätzlich zu den Grundspielerdaten werden auch allgemeine Accountinformationen
im selben Sync-Zyklus geteilt.

Beispielhafte Accountfelder (gemäß GMS-Kontext):

- `account.name`
- `account.birthday`
- `account.gender`
- `account.mainCharacter`
- `account.twinks[]` (Twink-Charaktere des Accounts innerhalb des Gildenkontexts)

## Pflicht-Domains pro Charakter (Vollständigkeitsprüfung)

- `account`
- `twinks`
- `equipment`
- `raid`
- `mplus`

## Twink-Verifikation (GuildRoster-Regel)

- Persistenz/Source of Truth für Twink-Daten liegt in `AccountInfo`.
- Twink-Zuordnungen werden nur als gültig geführt, wenn der verlinkte Charakter
  im aktuellen GuildRoster vorhanden ist (gleicher Gildenkontext).
- Grundlage für Abgleich/Identität bleibt `PLAYERGUID` (nicht Name).
- `Roster` dient als Verifikationsfilter, nicht als primärer Speicher für Twink-Links.
- Charaktere außerhalb des GuildRosters werden für Twink-Links nicht als gültige
  Zielobjekte behandelt (ungültig markieren oder entfernen).

## Ablauf

1. Login-Announce:
   - Beim Login sendet Spieler X einen Guild-Announce mit seinen Basisdaten + `gmsVersion`.

2. Peer-Response:
   - Online-Spieler antworten dem Sender mit:
     - ihrer eigenen Identität + `gmsVersion`
     - bekannten Basisdaten zu weiteren Spielern (Gossip/Bestandsweitergabe)
     - bekannten allgemeinen Accountinformationen inkl. Twink-Listen (gleicher Gossip-Zyklus).

3. Verteilung:
   - Durch Announce + Responses + Gossip gleichen sich die lokalen Stände zwischen allen
     Online-Clients schrittweise an.
   - Das gilt für Grundspielerdaten, allgemeine Accountinformationen und Twink-Verknüpfungen gleichermaßen.

## Verarbeitungsregeln für eingehende Daten

1. Validierung:
   - Eingehende Datensätze werden auf Struktur und Pflichtfelder geprüft.

2. Abgleich:
   - Daten werden per `PLAYERGUID` mit lokalem DB-Stand pro Spieler verglichen.
   - Nur fehlende oder aktuellere Werte werden übernommen.
   - Für Accountinformationen gilt derselbe Abgleich (fehlend/aktueller gewinnt).
   - Frischevergleich erfolgt pro Domain/Feld mit Metadaten:
     - `ts_server`
     - `source_guid`
     - `is_self_report`

3. Priorität/Konfliktauflösung:
   - Selbstbericht hat immer Vorrang:
     - Wenn ein Spieler seine eigenen Daten sendet, haben diese Vorrang.
     - Selbstbericht ist nur gültig, wenn `sender_guid == payload.PLAYERGUID`.
   - Andernfalls entscheidet ausschließlich ein eindeutiger Server-Timestamp.
   - Lokale Zeitstempel dürfen nicht zur Frischeentscheidung verwendet werden.
   - Ältere Fremdstände werden nicht erneut in die Gilde verteilt.

4. Direktes Nachfordern fehlender Daten:
   - Nach Eingang und Speicherung eines Spieler-Datensatzes wird sofort geprüft,
     ob für diesen Charakter noch erwartete Daten fehlen.
   - Falls Lücken bestehen, wird ein Guild-Request ausgelöst, z. B.:
     - "Benötige weitere Daten zu Spieler XY"
   - Ziel: fehlende Domains zeitnah nachziehen, statt nur passiv auf spätere
     Broadcasts zu warten.

5. Antworten im Gilden-Addon-Channel und gezieltes Peer-Fetch:
   - Auf einen Daten-Request im Gilden-Addon-Channel antworten alle Clients mit
     ihrem bekannten Stand zu Spieler XY (Metadaten/Frische-Information).
   - Der anfragende Client vergleicht die eingehenden Stände.
   - Wenn ein anderer Client einen neueren Stand für XY hat, werden die fehlenden/
     neueren Detaildaten direkt bei genau diesem Client angefordert (direkter
     Peer-Request), statt erneut breit in die Gilde zu fragen.
   - Retry-Reihenfolge für gezielten Fetch:
     - 1. beste Quelle anfragen (Timeout 8s)
     - bei Timeout: 2. beste Quelle anfragen (Timeout 8s)
     - bei Timeout: 3. beste Quelle anfragen (Timeout 8s)
   - Maximal 3 direkte Versuche, danach Abbruch bis neuer Input eintrifft
     (z. B. neuer Spieler online, neuer Broadcast, neuer Selbstbericht).

## Persistenz

- Jeder Client speichert den finalen Datenstand unabhängig in seiner eigenen lokalen Datenbank.
