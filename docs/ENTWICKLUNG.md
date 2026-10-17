# Wie ShareOS entstanden ist – ein KI-Entwicklungsprotokoll

*English version: [DEVELOPMENT.md](DEVELOPMENT.md)*

ShareOS wurde fast vollständig von einer KI entwickelt: **Claude** (Anthropic).
Jan hat das Projekt angestoßen und als „Vibe Coder“ geführt: Er hat die Ziele
vorgegeben, die grundlegenden Entscheidungen getroffen und alles an der echten
Hardware ausprobiert. Analyse, Architektur, der gesamte Code, die Builds, die
Tests, die Fehlersuche und diese Dokumentation stammen von Claude.

Dieses Dokument hält mit Zeitstempeln fest, wie das abgelaufen ist. So sieht
man, wie weit eine KI im Oktober 2026 bei echter Embedded-Entwicklung kommt:
alte Hardware, ein Bootloader, der nicht verändert werden darf, und kein
Debugger außer einer seriellen Konsole.

![Zeitstrahl](images/zeitstrahl.png)

*Jeder Punkt ist ein Commit (Uhrzeiten MESZ). Erzeugt mit `scripts/zeitstrahl.py`
direkt aus der Git-Historie.*

## Wer hat was gemacht

| | Jan (Initiator) | Claude (KI) |
|---|---|---|
| Ziele & Richtung | Alt-F modernisieren, GUI im Stil seines Intranets, Updates über GitHub, Cloud, Paperless | Vorschläge mit Abwägungen (OpenWrt vs. Alt-F-Basis, CGI vs. rpcd/ucode, Partitionierung) |
| Entscheidungen | „Alte Oberfläche komplett ersetzen“, „erst das Fundament“, „kein OpenWrt“, „nicht löten“, Assistent *und* manueller Weg | – |
| Code | 1 Commit: Import von Alt-F | 26 Commits, rund 5 500 neue Zeilen (Build-System, Device Tree, Init, Updater, Backend, GUI, Tests, Doku) |
| Hardware | Seriellen Adapter angeschlossen, U-Boot bedient, Befehle ausgeführt, Logs zurückgeschickt, Platten eingebaut | Jeden Befehl vorgegeben, jedes Log ausgewertet, Ursachen gefunden |
| Tests | Echte Box (DNS-320L rev A3) | Emulator (qemu-user), Testsuiten mit simulierter Box und virtuellen Platten |

Einmal hat zusätzlich „Konrad“ geholfen, Jans lokale Claude-Instanz. Sie hat
direkt auf der Box nachgesehen, warum der Webserver nicht lief.

## Chronik

### Freitag, 16.10.2026 – vom Konzept zur neuen Basis

| Zeit | Ereignis |
|---|---|
| ~16:00 | Jan legt das Projekt an und importiert Alt-F (r3935) als ShareOS ins Repo. |
| ~16:20 | **GUI-Konzept**: Claude analysiert die 178 CGI-Skripte von Alt-F und ordnet sie in 8 Bereiche. Das Design übernimmt den Stil aus Jans Skynet-Intranet. |
| ~16:55 | **Modernisierungsplan**: Bestandsaufnahme (buildroot 2009, Kernel 4.14 EOL, uClibc). Entscheidung mit Jan: Alt-F-Basis modernisieren und das Bedienkonzept von OpenWrt übernehmen (UCI, ubus, rpcd, ucode), weil OpenWrt nur über die serielle Konsole installierbar wäre. |
| 17:10 | **Neue Build-Basis**: buildroot 2026.02 LTS als BR2_EXTERNAL, GCC 14, musl, Kernel 6.18 mit portiertem DNS-320L-Device-Tree. |
| 19:10 | Der Kernel ist zu groß (4,2 MB), das Original-U-Boot lädt nur 3 MB. Mit xz und schlankerer Konfiguration passt er (2,1 MB). |
| 19:54 | Test über Alt-Fs „TryIt“/kexec: Die Box hängt, auch mit Alt-Fs eigenem Kernel. Claude findet die Bestätigung des Alt-F-Autors, dass kexec auf dem DNS-320L nicht funktioniert. **Ohne serielle Konsole geht es nicht weiter.** |
| 21:25 | **Kern-Stack**: UCI, ubus, rpcd mit ucode-Plugin, uhttpd und ein Updater für GitHub Releases, komplett im Emulator getestet. |

### Samstag, 17.10.2026 – auf der echten Hardware

| Zeit | Ereignis |
|---|---|
| ~11:00 | Jan schließt einen USB-TTL-Adapter an die unbestückte Stiftleiste JP1 an, ohne zu löten. Claude führt durch: Pinbelegung, vertauschte RX/TX-Leitungen, eine wackelige Masse. |
| ~12:15 | Das Unterbrechen des Autoboots klappt nicht. Claude findet im U-Boot-Code die D-Link-Eigenheit: **Leertaste, dann 1**. |
| ~12:30 | TFTP-Timeouts: Ursache ist die Firewall (ufw) auf Jans PC. |
| 12:44 | **ShareOS startet zum ersten Mal auf der Box**, aus dem RAM, ohne etwas zu flashen. Gigabit, MAC-Adresse, Lüfter, Temperatur, Taster und Weboberfläche funktionieren. |
| 12:57 | **UBI-Layout**: System als squashfs, Einstellungen als UBIFS-Overlay, ein kleines Start-System mit Rettungsmodus. |
| 13:48 | System in den Flash geschrieben. Die Einstellungen überleben den Neustart. Der Fix fürs saubere Herunterfahren ist eingebaut. |
| 14:11 | Kernel und Start-System geflasht: **Die Box startet ShareOS allein**, ohne PC und ohne Konsole. Die Alt-F-Partitionen sind vorher gesichert. |
| 14:47 | **Updater für das neue Layout** und **neue Weboberfläche** im Skynet-Stil. |
| 15:00–15:44 | Die Weboberfläche ist nach jedem Start weg. Fehlersuche mit Jan und Konrad. Claude stellt den Absturz im Emulator nach: Jede Browser-Anfrage mit `If-Modified-Since` bringt `uhttpd` zum Absturz (musl-`strptime` mit `%Z`). Behoben mit einem Patch. |
| 15:51 | Die Festplatten werden erkannt. Die beim Portieren korrigierte SATA-Stromleitung (gpio0 24 statt Alt-Fs gpio1 24) ist damit bestätigt. |
| 16:00 | **Speicher**: Assistent und manuelle Verwaltung (ext4, RAID 1, SMART, Ruhezustand, Swap, Apps-Bereich). |
| 16:45 | Englische Oberfläche über Sprachdateien, HTTPS mit selbstsigniertem Zertifikat, Ersteinrichtungs-Assistent mit Alt-F-Übernahme, Lüfter- und LED-Einstellungen. |
| 17:20 | Die Speicher-Tests mit virtuellen Platten finden einen echten Fehler: Bei zwei einzelnen Platten landete die zweite unter dem Namen der ersten. Behoben, bevor er auf die Box kam. |
| 18:13 | Alles geht nach `main`; Jan legt das erste Release `v0.1.0-beta.1` an, GitHub baut das Update-Paket. |
| 18:26 | Die Box erreicht GitHub nicht: „certificate is not correctly signed“. Erster Verdacht von Claude (Netzwerk fängt HTTPS ab) ist falsch. Jans Ausgabe zeigt Googles echtes Zertifikat. Ursache: buildroot gibt curl mit mbedTLS keinen Pfad zu den CA-Zertifikaten. Workaround per `/root/.curlrc`, Fix im Build. |
| 20:15 | **Erstes Online-Update auf echter Hardware:** Die Box lädt `0.1.0-beta.1` von GitHub, prüft es, schreibt Kernel und Startsystem, installiert das System beim Neustart. Ersteinrichtung läuft ohne Probleme. |
| 20:18 | Jans Rückmeldung: Nach „Installieren“ sieht man nichts. Claude baut einen Fortschrittsbalken mit den einzelnen Schritten. |
| 20:31 | Neue Vorgaben von Jan: Menü nach „Haupt-Funktion“ (Dienste → Autostart, System → Netzwerk), Kachel-/Tabellenansicht je Bereich, Hell/Dunkel/System, Logo und Browser-Symbol in der Akzentfarbe. Netzwerk-Einstellungen mit automatischem Rückfall, damit man sich nicht aussperrt. |

## Bemerkenswerte Problemlösungen

- **3-MB-Grenze des Bootloaders:** Der Kernel ist von 4,2 auf 2,4 MB geschrumpft, Treiber wurden in Module ausgelagert. Das Start-System umfasst nur 0,9 MB.
- **Kein Flashen ohne Rückweg:** Erst lief ShareOS im RAM, dann vom Netzwerk, dann stand das System im Flash und erst zuletzt der Kernel. Jeder Schritt hatte einen Rückweg (Alt-F-Sicherung, D-Link-Rettungssystem, Rettungsmodus).
- **U-Boot ohne Doku:** Die Abbruchsequenz und der Rückfall auf das Rettungssystem bei defektem Image hat Claude aus dem Verhalten und dem Speicherabbild erschlossen.
- **Hardware-Detail im Device Tree:** Alt-F schaltete die SATA-Stromversorgung über den falschen GPIO-Controller. Claude hat das beim Portieren erkannt, die Platten haben es bestätigt.
- **Netzwerk ändern ohne Aussperren:** Eine neue IP gilt sofort, die Box wartet aber 2 Minuten auf eine Bestätigung von der neuen Adresse. Kommt keine, stellt sie die alten Einstellungen wieder her (wie bei OpenWrt). Die Oberfläche öffnet die neue Adresse selbst und bestätigt.
- **Absturz, der nur im echten Browser auftritt:** Die Absicherung (automatischer Neustart von uhttpd, Protokoll) kam zuerst. Die eigentliche Ursache war ein Fehler in der C-Bibliothek, den Claude im Emulator nachgestellt und gezielt umgangen hat.

## Die Oberfläche

Standard ist das dunkelblaue Design mit Logo. Hell, Dunkel oder „wie das
Betriebssystem“ sowie die Akzentfarben Blau, Grün, Rot und Weiß gelten für alle
Nutzer. Logo und Browser-Symbol nehmen die Akzentfarbe an, das Logo lässt sich
abschalten. Jeder Bereich mit Kacheln hat rechts in der Kopfzeile einen
Schalter für die Tabellenansicht. Die Oberfläche gibt es auf Deutsch und
Englisch.

| Anmeldung | Übersicht |
|---|---|
| ![Anmeldung](images/gui-login.png) | ![Übersicht](images/gui-uebersicht.png) |

| Speicher (Spiegel in der Erst-Synchronisierung) | Speicher-Assistent |
|---|---|
| ![Speicher](images/gui-speicher.png) | ![Assistent](images/gui-assistent.png) |

| Firmware-Update | Darstellung, Sprache, Logo |
|---|---|
| ![Firmware](images/gui-firmware.png) | ![Darstellung](images/gui-darstellung.png) |

| Netzwerk mit Rückfall, HTTPS | Dienste → Autostart |
|---|---|
| ![Netzwerk](images/gui-netzwerk.png) | ![Autostart](images/gui-autostart.png) |

| Tabellenansicht | Akzentfarben, Hell und Dunkel |
|---|---|
| ![Tabellenansicht](images/gui-tabelle.png) | ![Farben](images/gui-farben.png) |

| Update mit Fortschritt | Englisch |
|---|---|
| ![Update](images/gui-update-progress.png) | ![Englisch](images/gui-en-overview.png) |

| Handy | |
|---|---|
| ![Handy](images/gui-handy.png) | |

*Screenshots mit Beispieldaten (`tests/mock-ubus.py`): zwei 4-TB-Platten als
Spiegel und ein verfügbares Update.*

## Zahlen (Stand 17.10.2026, 16 Uhr)

- Reine Arbeitszeit: etwa 6 Stunden am Freitag und 5 Stunden am Samstag
- 27 Commits, davon 26 von Claude
- rund 5 500 neue Zeilen: Build/Board 1 300, Backend + GUI 2 900, Tests 370, Doku 500
- 18 Tests für den Updater (inklusive kompletter Installation auf einer simulierter Box), 21 Prüfungen der Schnittstelle im ARM-Emulator, Speicher-Tests mit virtuellen Platten
- 0 Lötstellen, 0 unbrauchbare Boxen

## Wie gearbeitet wurde

Jan schrieb in einem Chat auf Deutsch, was er möchte oder was er gerade sieht.
Oft war das nur ein eingefügtes Konsolen-Log. Claude arbeitete in einer
Cloud-Umgebung mit dem Repo, baute die Firmware, testete sie im Emulator,
pushte auf GitHub und schickte Jan die fertigen Images mit einer genauen
Schritt-für-Schritt-Anleitung. Alles, was die Box veränderte (Flashen,
Platten löschen), passierte nur nach Jans ausdrücklichem OK.
