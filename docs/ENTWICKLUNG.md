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
| 22:50 | Jan testet `beta.2` komplett durch – alles läuft. Rückmeldungen: Logo auf der Anmeldeseite nicht mittig, Installieren-Knopf bleibt aktiv, Hinweise rechts unten gehen unter. |
| 23:00 | Konzept **Benutzer, Freigaben, Apps**: ein Konto für alles (Freigaben, Weboberfläche, Apps, Cloud). Jan entscheidet: eigener Bereich „Mein ShareOS“ für Benutzer, Speicherlimit je Benutzer, Cloud-Sync für Gerät und Benutzer, ksmbd als SMB-Server. |
| 23:05 | In Jans Protokoll fallen ECC-Fehler auf: `blkid`/`lsblk` lasen bei jeder Speicherabfrage auch die rohen Flash-Partitionen, darunter D-Links unlesbare „my-dlink“. Claude schaltet die Flash-Blockgeräte ab. |
| 23:30 | **Freigaben (SMB/NFS), Benutzer, Gruppen, Speicherlimits, „Mein ShareOS“, Sichern/Wiederherstellen** (JSON, optional AES-256). Alt-F-Benutzer werden mitsamt Passwörtern übernommen. 52 Prüfungen im ARM-Emulator. |

### Sonntag, 18.10.2026 – Paperless, Cloud und App

| Zeit | Was passiert ist |
|---|---|
| 00:37 | Jan veröffentlicht `v0.1.0-beta.3` und geht schlafen: „Du kannst weiter in der Roadmap machen, Cloud, Paperless. Ich teste dann morgen früh.“ |
| 01:00 | **Paperless-ngx**: Eingangsordner je Benutzer (im persönlichen Ordner) oder gemeinsam auf einer Freigabe, z. B. für einen Scanner. ShareOS lädt neue Dateien über die Paperless-API hoch, fragt das Ergebnis ab und zeigt es an. Benutzer tragen ihr Token selbst unter „Mein ShareOS“ ein. |
| 01:00 | **Cloud-Sync mit rclone**: rclone wird bei Bedarf von GitHub geladen (mit Prüfsumme) und liegt im Apps-Bereich. Konten (WebDAV/Nextcloud, S3, SFTP oder ein Abschnitt aus `rclone.conf`) und Aufträge (hochladen, herunterladen, spiegeln) mit Zeitplan und Bandbreitengrenze – für das Gerät und, wenn erlaubt, für jeden Benutzer mit eigenen Zugangsdaten. 29 Prüfungen mit einem nachgebauten Paperless und einem lokalen WebDAV-Server. |
| 01:20 | **Als App installierbar** (Symbol, Kurzbefehle) und eine **Status-Adresse für Widget-Apps** wie KWGT – Chrome bietet für Web-Apps keine Startbildschirm-Widgets. |
| 01:40 | Beim erneuten Durchlauf aller Tests fällt auf: Seit dem Cloud-Umbau scheiterte die Anmeldung normaler Benutzer an einer Funktion, die im Skript erst weiter unten stand (ucode kennt kein Hoisting). Behoben, bevor es eine Box erreicht hat; eine neue Prüfung im CI findet solche Fälle künftig automatisch. |
| 09:20 | Jan veröffentlicht `v0.1.0-beta.4`. Freigaben, Benutzer und Gruppen laufen auf der Box „sehr gut“. |
| 10:00 | Jans Rückmeldungen: ein zu langes Feld-Label verschiebt das Eingabefeld, Datei-Knöpfe sehen anders aus als die übrigen, Wunsch nach einem **Dateibrowser** (Admin: alles, Benutzer: eigener Ordner, je Benutzer freischaltbar) und **eigener Darstellung** für Benutzer. |
| 10:09 | Frage nach der Update-Anzeige: Bisher prüfte nur die geöffnete Oberfläche. Jetzt prüft die Box selbst alle 6 Stunden. |
| 10:30 | Login-Text `user@shareos`, Zertifikat folgt Name und IP. Empfehlung statt fester Werks-IP: DHCP, Name per mDNS (`shareos.local`) und eine Rückfall-Adresse `192.168.0.32` ohne DHCP. Jan: „Ja gerne.“ |
| 11:00 | Dateibrowser mit Hoch- und Herunterladen über einmalige Tickets; Dateien von Benutzern werden mit deren Rechten gelesen und geschrieben. Ein uhttpd-Patch verhindert, dass große Übertragungen nach 60 s abbrechen. Beim Testen in der Cloud-Umgebung hat ein Aufräumschritt versehentlich deren `/dev` geleert – die Testskripte löschen seitdem nur noch, wenn nichts mehr eingehängt ist. |
| 11:53 | Jan veröffentlicht `v0.1.0-beta.5` und bringt Ideen für die Roadmap: App-Store mit Docker/Compose und ein Benachrichtigungssystem. Claude schreibt eine Machbarkeitsstudie: Docker passt nicht auf den DNS-320L (ARMv5, 256 MB, keine Images); stattdessen „Apps light“ mit nativen Paketen, Benachrichtigungen über ubus. Jan: „Container sind raus.“ |
| 12:12 | Jan schickt sein Webpad: Es soll **ShareOS-WebApps** als nachinstallierbare Pakete mit App-JSON (Version, Herausgeber) geben, angeboten wie die Firmware-Versionen, aus einem eigenen Repo. Jan legt `ShareOS-Apps` an. |
| 12:45 | App-Repo mit Paketformat `.sapp`, Build, Releases je Version und Katalog `index.json` per GitHub Actions; Webpad 1.0.0 als erste App, mit eingepackten Bibliotheken (läuft offline). In der Firmware: APPS-Bereich mit Store, Installation mit SHA-256-Prüfung, eigener Web-Server-Port für Apps, Sichtbarkeit je Benutzer, eigene Pakete hochladen. |

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

| Freigaben | Rechte je Benutzer und Gruppe |
|---|---|
| ![Freigaben](images/gui-freigaben.png) | ![Rechte](images/gui-freigabe-rechte.png) |

| Benutzer | „Mein ShareOS“ für Benutzer |
|---|---|
| ![Benutzer](images/gui-benutzer.png) | ![Mein ShareOS](images/gui-mein-shareos.png) |

| Sichern & Wiederherstellen | |
|---|---|
| ![Sichern](images/gui-sichern.png) | |

| Update mit Fortschritt | Englisch |
|---|---|
| ![Update](images/gui-update-progress.png) | ![Englisch](images/gui-en-overview.png) |

| Paperless | Cloud-Sync |
|---|---|
| ![Paperless](images/gui-paperless.png) | ![Cloud](images/gui-cloud.png) |

| „Mein ShareOS“: Paperless und Cloud | App & Widgets |
|---|---|
| ![Mein ShareOS mit Paperless und Cloud](images/gui-mein-paperless-cloud.png) | ![App und Widgets](images/gui-app-widgets.png) |

| Dateibrowser (Admin) | Dateibrowser (Benutzer) |
|---|---|
| ![Dateien](images/gui-dateien.png) | ![Dateien Benutzer](images/gui-dateien-benutzer.png) |

| Eigene Darstellung (Benutzer) | Benutzer anlegen |
|---|---|
| ![Darstellung Benutzer](images/gui-darstellung-benutzer.png) | ![Benutzer anlegen](images/gui-benutzer-editor.png) |

| App-Store | Installierte Apps |
|---|---|
| ![Store](images/gui-apps-store.png) | ![Installiert](images/gui-apps-installiert.png) |

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
