# Phase 1 testen – ohne zu flashen

Das Phase-1-Image ist ein **minimales Testsystem**: neuer Kernel 6.18, neues
Userland (musl, aktuelles BusyBox), SSH und ein Hardware-Check. Es hat noch
keine Weboberfläche. Ziel ist nur, zu prüfen, ob die neue Basis auf dem
DNS-320L sauber läuft.

> **Stand 2026-10-16:** Auf dem DNS-320L ist „TryIt“ in Alt-F ausgegraut, und
> kexec funktioniert dort generell nicht (auch nicht mit Alt-Fs eigenem Kernel).
> Ein Test ohne serielle Konsole ist damit nicht möglich – siehe
> [HARDWARE-DNS320L.md](HARDWARE-DNS320L.md). Der Weg unten gilt für Boxen, auf
> denen TryIt verfügbar ist; auf dem DNS-320L wird über die serielle Konsole
> getestet (Start aus dem RAM per TFTP, ohne Flashen).

## Sicherer Weg: „TryIt“ in Alt-F

Alt-F kann eine Firmware starten, **ohne sie zu flashen** (per kexec). Nach dem
nächsten Neustart läuft wieder das geflashte Alt-F.

1. Firmware-Datei `ShareOS-<version>-DNS-320L-rev-Ax.bin` herunterladen
   (GitHub Actions-Artefakt oder Release) und die `.sha256` prüfen.
2. In Alt-F: **System → Firmware**, die `.bin` hochladen. Das optionale
   Prüfsummen-Feld erwartet eine **SHA1**-Datei: dort die `.sha1` angeben
   (nicht die `.sha256`) oder das Feld leer lassen.
3. **„TryIt“** wählen (nicht „FlashIt“!) und bestätigen.
4. Die Box startet neu in ShareOS. Die **blaue USB-LED blinkt** im Herzschlag-Takt,
   sobald ShareOS läuft.

> In Phase 1 bitte **nicht „FlashIt“** verwenden: Das Testsystem hat keine
> Weboberfläche, um wieder auf Alt-F zurückzuflashen.

## Anmelden

ShareOS holt sich die IP per DHCP (Hostname `shareos`, IP im Router
nachsehen).

```sh
ssh root@<ip>          # Passwort: shareos   (nur im Testsystem!)
```

Hängt eine serielle Konsole dran, steht dort nach dem Start ebenfalls IP und
Linkgeschwindigkeit.

## Hardware-Check

```sh
shareos-check
```

Der Bericht landet in `/tmp/shareos-check.txt`. Holen mit:

```sh
scp root@<ip>:/tmp/shareos-check.txt .
```

### Worauf es ankommt

| Prüfpunkt | Erwartung | Wo sichtbar |
|---|---|---|
| Netzwerk | `Speed: 1000Mb/s` (A3-Gigabit-Frage) | Abschnitt *Ethernet* |
| PHY-Treiber | `Generic PHY` (wie Alt-F); Marvell-Treiber liegt als Modul bei | *Ethernet* |
| MCU | `dns320l-daemon: running`, Temperatur plausibel (z. B. 30000–45000 m°C) | *MCU / fan* |
| Lüfter | dreht auf halber Stufe, ab 50 °C voll | hörbar |
| Platten | `sda`/`sdb` mit Modell und Größe | *Disks* |
| Flash | 7 MTD-Partitionen: u-boot, uImage, ramdisk, image, mini firmware, config, my-dlink | *Flash* |
| LEDs | blaue USB-LED blinkt | am Gerät |
| Fehler | möglichst keine Einträge | *Kernel warnings/errors* |

### Optional: echter Durchsatz

`iperf3` ist im Testsystem enthalten:

```sh
# auf der Box
iperf3 -s
# auf dem PC
iperf3 -c <ip> -t 20          # PC -> NAS
iperf3 -c <ip> -t 20 -R       # NAS -> PC
```

Bei Gigabit sind auf dem Kirkwood grob 300–600 Mbit/s realistisch (CPU-limitiert);
um 94 Mbit/s hieße: Link läuft nur mit 100 Mbit.

### Ausschalten und Power-Taste

- `poweroff` per SSH → die MCU schaltet nach ~3 s ab.
- Power-Taste kurz drücken → gleiches Verhalten.
- `reboot` → startet wieder Alt-F aus dem Flash.

Beim nächsten Einschalten läuft in jedem Fall wieder Alt-F.

Hinweis aus Alt-F: Bei manchen Kernel-Wechseln schaltet U-Boot nach einem
Neustart das Netzwerk nicht ein. Falls Alt-F danach nicht erreichbar ist:
einmal stromlos machen und neu starten.

## Rückmeldung

Bitte die `shareos-check.txt` zurückgeben, dazu: Lief der Lüfter? Hat die
Power-Taste ausgeschaltet? Kam Alt-F nach dem Neustart wieder?
