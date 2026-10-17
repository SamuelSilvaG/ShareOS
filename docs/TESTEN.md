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

`http://<ip>` öffnen und mit `root` / `shareos` anmelden. Das Passwort
gleich unter **System → Allgemein** ändern.

## 5. Updates

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

## Wenn etwas schiefgeht

| Zeichen | Bedeutung / Abhilfe |
|---|---|
| Die orange USB-LED blinkt | Rettungsmodus: Grund und SSH-Adresse stehen auf der Konsole. `shareos-install-ubi` ist dort verfügbar. |
| U-Boot meldet einen defekten Image-Header | U-Boot startet automatisch das D-Link-Rettungssystem. Darüber lässt sich Alt-F per Weboberfläche flashen. |
| Der Kernel hängt | Wie in Schritt 2 per TFTP starten und die Sicherung zurückschreiben: `flash_erase /dev/mtd1 0 0; nandwrite -p /dev/mtd1 uImage.bin` (mtd2 mit `ramdisk.bin`) |
| Ganz zurück zu Alt-F | Sicherung zurückschreiben (siehe Zeile davor), dann in Alt-F die Zusatzpakete neu flashen |

U-Boot, MAC-Adresse und das D-Link-Rettungssystem fasst ShareOS nie an.
