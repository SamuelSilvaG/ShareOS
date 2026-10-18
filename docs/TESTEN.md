# ShareOS testen und installieren (DNS-320L)

*English version: [TESTING.md](TESTING.md)*

Stand: 17.10.2026. ShareOS ist in der **Testphase**. Die Installation auf eine
Box mit Alt-F braucht im Moment noch die **serielle Konsole** (Stiftleiste JP1,
ohne Löten, siehe [HARDWARE-DNS320L.md](HARDWARE-DNS320L.md)). Ist ShareOS
einmal installiert, laufen Updates über die Weboberfläche.

Jeder Schritt hat einen Rückweg: Zuerst läuft ShareOS nur im RAM, dann kommt
das System in den Flash und ganz zum Schluss der Kernel. Die Alt-F-Partitionen
werden vorher gesichert.

## Was du brauchst

- das Update-Paket `ShareOS-<version>-DNS-320L-rev-Ax.sysupgrade.tar` aus einem
  GitHub-Release
- einen USB-TTL-Adapter (3,3 V) an JP1: Pin 4 = TX der Box, 3 = GND, 1 = RX der
  Box; Pin 2 (3,3 V) bleibt frei. Einstellung 115200 8N1
- einen PC mit TFTP-Server, zum Beispiel `dnsmasq`

## 1. PC vorbereiten

```sh
sudo mkdir -p /srv/tftp && sudo rm -f /srv/tftp/*
sudo tar xf ShareOS-*.sysupgrade.tar -C /srv/tftp
cd /srv/tftp && sha256sum -c SHA256SUMS
sudo dnsmasq --no-daemon --port=0 --enable-tftp --tftp-root=/srv/tftp --tftp-single-port
```
Die Firewall des PCs muss UDP-Port 69 durchlassen, zum Beispiel
`sudo ufw allow from <netz>/24 to any port 69 proto udp`.

## 2. Start aus dem RAM (schreibt nichts)

Box einschalten und sofort **Leertaste, 1, Leertaste, 1 …** tippen, bis
`Marvell>>` erscheint. Dann:
```
setenv ipaddr <freie IP>
setenv serverip <IP des PCs>
setenv netmask 255.255.255.0
setenv bootargs shareos.netroot=<IP des PCs>
tftpboot 0xa00000 uImage
tftpboot 0xf00000 urootfs
bootm 0xa00000 0xf00000
```
Niemals `saveenv` eingeben. Anmelden mit `root` / `shareos`. Mit
`shareos-check` lässt sich die Hardware prüfen.

## 3. System in den Flash schreiben

> Die `.bin` aus einem Release enthält nur Kernel und Startsystem. Über die
> Firmware-Seite von Alt-F oder D-Link geflasht, startet die Box danach im
> Rettungsmodus, bis das System (Schritt unten) installiert ist. Eine
> Installationsseite dafür ist geplant.

Auf der Box, im Netzwerk-Start aus Schritt 2:
```sh
shareos-install-ubi tftp://<IP des PCs>/rootfs.squashfs --yes
shareos-flash-boot tftp://<IP des PCs> --yes
```
- Der erste Befehl schreibt das System in die Partition `image`. Dabei gehen
  die Zusatzpakete von Alt-F verloren, Alt-F selbst bleibt startfähig.
- Der zweite Befehl schreibt Kernel und Start-System. Vorher sichert er die
  Alt-F-Partitionen nach `/root/boot-backup`. Bitte die Sicherung auf den PC
  holen: `scp -O -r root@<ip>:/root/boot-backup .`

Danach `reboot`: Die Box startet ShareOS allein.

## 4. Weboberfläche

`http://shareos.local` öffnen (oder `http://shareos.fritz.box`, `http://<ip>`)
und mit `root` / `shareos` anmelden. Das Passwort gleich unter
**System → Allgemein** ändern.

- Die Box holt sich ihre Adresse per **DHCP** vom Router und meldet sich dort mit ihrem Namen an.
- Per **mDNS** ist sie zusätzlich unter `<name>.local` erreichbar (Windows 10/11, macOS, iOS, Android, Linux).
- Antwortet kein DHCP-Server (Box direkt am PC), nimmt sie nach etwa 15 s die **Rückfall-Adresse `192.168.0.32`**. Den PC dann auf z. B. `192.168.0.10/24` stellen. Sobald ein DHCP-Server antwortet, wechselt sie von selbst.
- Das selbst ausgestellte HTTPS-Zertifikat nennt Name, `<name>.local` und die aktuelle IP. Nach einer Änderung wird es neu ausgestellt (der Browser fragt dann einmal neu nach).

## 5. Updates

- **Automatisch:** Die Box sieht alle 6 Stunden auf GitHub nach. Ein neues Release erscheint oben als **UPDATE … verfügbar**, sobald GitHub das Update-Paket gebaut hat (etwa 45 Minuten nach dem Veröffentlichen).
- **Über die Weboberfläche:** System → Firmware → *Jetzt prüfen*. Für
  Testversionen den Kanal **Beta** wählen.
- **Von Hand**, mit einem Paket auf der Box:
  ```sh
  cd /tmp && mkdir u && tar xf ShareOS-*.sysupgrade.tar -C u
  shareos-flash-boot /tmp/u --yes
  mkdir -p /overlay/upgrade && cp /tmp/u/rootfs.squashfs /overlay/upgrade/
  cd /overlay/upgrade && sha256sum rootfs.squashfs > rootfs.squashfs.sha256 && echo <version> > version
  sync && reboot
  ```
  Beim Start meldet die Konsole `upgrade: installing system … done`.

Einstellungen und installierte Pakete bleiben bei Updates erhalten.

**Versionen bis 0.1.0-beta.1:** curl findet dort die CA-Zertifikate nicht,
die Prüfung bei GitHub meldet „certificate is not correctly signed“. Einmal auf
der Box ausführen, danach klappt das Update (ab 0.1.0-beta.2 nicht mehr nötig):
```sh
echo 'cacert = /etc/ssl/certs/ca-certificates.crt' > /root/.curlrc
```

## 6. Netzwerk

Unter **System → Netzwerk** lässt sich eine feste IP einstellen. Die Änderung
gilt sofort; die Box wartet dann 2 Minuten auf eine Bestätigung von der neuen
Adresse. Die Oberfläche öffnet die neue Adresse selbst und bestätigt. Kommt
keine Bestätigung (Tippfehler, falsches Netz), stellt die Box die alten
Einstellungen wieder her. Notfalls: Werkseinstellungen (DHCP) über die serielle
Konsole mit `shareos-factory-reset --yes`.

## 7. Freigaben und Benutzer

Unter **Freigaben → Benutzer** Konten anlegen (Rolle, persönlicher Ordner,
Speicherlimit), unter **Freigaben → Freigaben** Ordner freigeben und Rechte je
Benutzer oder Gruppe setzen. Windows: `\\<box>\<freigabe>`, macOS/Linux:
`smb://<box>/<freigabe>`. Benutzer mit Web-Zugang sehen nach der Anmeldung
„Mein ShareOS“ (eigener Speicher, Freigaben, Passwort, Paperless, Cloud).

## 8. Paperless-ngx

1. In Paperless: Profil → **API-Token** erzeugen.
2. In ShareOS unter **Paperless** die Adresse eintragen (z. B. `http://192.168.1.20:8000`) und speichern.
3. **Neuer Eingang**: persönlich (Ordner `Paperless` im persönlichen Ordner eines Benutzers) oder gemeinsam (Ordner einer Freigabe, z. B. für den Scanner), Token eintragen, **Verbindung prüfen**.
4. Eine PDF in den Eingangsordner legen. Nach spätestens 2 Minuten (oder sofort mit **Jetzt übertragen**) erscheint sie im Protokoll als „wird verarbeitet“, dann „übernommen“ und in Paperless.

Dateien, die Paperless ablehnt (z. B. Duplikate), landen in `.paperless/failed`
im Eingangsordner. Ist Paperless nicht erreichbar, bleibt die Datei liegen und
wird beim nächsten Lauf erneut gesendet.

## 9. Cloud-Sync

1. **Cloud → rclone installieren** (lädt rclone von GitHub, braucht einen eingerichteten Apps-Bereich).
2. **Konto hinzufügen**: Nextcloud/WebDAV, S3 oder SFTP direkt; Google Drive, OneDrive, Dropbox: auf dem PC `rclone config` ausführen und den fertigen Abschnitt aus `rclone.conf` einfügen. **Testen** zeigt, ob die Anmeldung klappt.
3. **Neuer Auftrag**: Ordner auf dem NAS, Konto, Ordner in der Cloud, Richtung (Hochladen ist die sichere Wahl, Spiegeln löscht auf der Zielseite), Zeitplan. **Jetzt starten** und das **Protokoll** ansehen.

Benutzer dürfen eigene Konten und Aufträge anlegen, wenn im Benutzerkonto
„Darf eigene Cloud-Sync-Aufträge anlegen“ gesetzt ist (braucht einen
persönlichen Ordner). Ihre Aufträge laufen mit ihren Rechten.

## 10. App und Widgets

- **Als App:** Chrome und Edge bieten „App installieren“ nur über HTTPS mit einem vertrauenswürdigen Zertifikat an (z. B. Let's Encrypt, unter System → Netzwerk einspielen). Über http:// geht „Zum Startbildschirm hinzufügen“ (Lesezeichen-Symbol). Langes Drücken auf das App-Symbol zeigt die Kurzbefehle.
- **Widgets:** Unter **System → Allgemein → Status für Widgets** einschalten und die Adresse kopieren. Sie liefert JSON, z. B.:
  ```sh
  curl "http://<box>/cgi-bin/status?token=<token>"
  ```
  In KWGT (Android) kann man die Werte mit `$wg("<adresse>", json, ".volumes[0].used_pct")$` anzeigen. **Neuer Schlüssel** macht die alte Adresse ungültig.

## 11. Dateibrowser und eigene Darstellung

- **Admins:** Freigaben → **Dateien** zeigt alle eingehängten Laufwerke: Ordner anlegen, hochladen (auch per Ziehen), herunterladen, umbenennen, verschieben, kopieren, löschen.
- **Benutzer:** Im Benutzerkonto „Dateibrowser für den persönlichen Ordner“ einschalten. Dann gibt es in „Mein ShareOS“ den Reiter **Dateien**, nur für den eigenen Ordner und mit den eigenen Rechten.
- **Darstellung:** Benutzer mit Web-Zugang stellen unter **Darstellung** Hell/Dunkel und Akzentfarbe für sich ein. „Wie für alle“ nimmt wieder die Vorgabe des Admins.
- Testidee: eine große Datei (z. B. 1 GB) hochladen und wieder herunterladen. Das darf nicht nach 60 s abbrechen.

## Wenn etwas schiefgeht

| Zeichen | Bedeutung / Abhilfe |
|---|---|
| Die orange USB-LED blinkt | Rettungsmodus: Grund und SSH-Adresse stehen auf der Konsole. `shareos-install-ubi` ist dort verfügbar. |
| U-Boot meldet einen defekten Image-Header | U-Boot startet automatisch das D-Link-Rettungssystem. Darüber lässt sich Alt-F per Weboberfläche flashen. |
| Der Kernel hängt | Wie in Schritt 2 per TFTP starten und die Sicherung zurückschreiben: `flash_erase /dev/mtd1 0 0; nandwrite -p /dev/mtd1 uImage.bin` (mtd2 mit `ramdisk.bin`) |
| Ganz zurück zu Alt-F | Sicherung zurückschreiben (siehe Zeile davor), dann in Alt-F die Zusatzpakete neu flashen |

U-Boot, MAC-Adresse und das D-Link-Rettungssystem fasst ShareOS nie an.
