ShareOS – Testsystem aus Alt-F starten, ohne zu flashen (DNS-320L)
===================================================================

1. Auf dem PC den Empfänger für die Kernel-Meldungen starten (UDP-Port 6666)

   Linux:
       nc -u -l -k 6666

   Windows (PowerShell, Firewall-Abfrage für UDP 6666 erlauben):
       $u = New-Object System.Net.Sockets.UdpClient 6666
       $ep = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any, 0)
       while ($true) { [Text.Encoding]::ASCII.GetString($u.Receive([ref]$ep)) | Write-Host -NoNewline }

2. Paket auf die Box kopieren und dort starten

       scp shareos-kexec-test-*.tar root@<alt-f-ip>:/tmp/
       ssh root@<alt-f-ip>
       cd /tmp && tar xf shareos-kexec-test-*.tar && cd shareos-kexec-test
       sh shareos-kexec-test.sh              # Meldungen an alle im LAN
       # oder: sh shareos-kexec-test.sh <pc-ip>

3. Beobachten
   - Meldungen im Empfänger    -> der neue Kernel läuft
   - blaue USB-LED blinkt      -> ShareOS ist komplett oben, ssh root@<ip> (Passwort: shareos)
   - Box startet von selbst neu -> Kernel-Absturz, Meldungen stehen im Empfänger
   - gar nichts nach 2 Minuten -> Stecker ziehen, Alt-F startet normal

Nichts davon verändert den Flash. Nach dem Stromlosmachen läuft wieder Alt-F.
Bitte die Ausgabe aus dem Empfänger komplett zurückgeben.
