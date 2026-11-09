# Spotify-Titellisten und Offline-Testversion

Diese Anleitung gehört zum Branch `feature/spotify-offline-audit` im Fork
[dirkdrutschmann/openjooki](https://github.com/dirkdrutschmann/openjooki).
Die experimentelle Testversion ergänzt den bisherigen Spotify-Player.

## Spotify Free und Premium

Mit **Spotify Free** kannst du nach dem Verbinden die Titel einer Playlist lesen.
Die Liste zeigt Titel, Interpret und Dauer und blättert große Playlists in Seiten
mit bis zu 50 Einträgen durch. Die normale Online-Wiedergabe nutzt weiterhin den
bisherigen Player. Die zusätzliche Anmeldung ändert dessen gespeichertes Konto nicht.

**Premium** wird für die zusätzliche Freigabe zum Herunterladen von Audiodaten
benötigt. Erst nach dieser Freigabe erscheinen die Offline-Bedienelemente.
Eine Liste von Titeln bedeutet noch nicht, dass die Musik heruntergeladen ist.
Für private Playlists muss das verbundene Konto Zugriff besitzen. Spotify kann
Abfragen zeitweise begrenzen; dann etwas warten und erneut versuchen.

## Am Computer verbinden

Die erste Version verwendet den gewählten Computer-Login: Die Oberfläche startet
den Vorgang, der Browser auf deinem Computer nimmt die Spotify-Anmeldung entgegen.
Eine Rückleitung an die unverschlüsselte Netzwerkadresse des Jooki wird von Spotify
nicht unterstützt. Der Computer muss sich im selben Netz befinden und per SSH
bereits Zugang zum Jooki haben.

Im Checkout des Forks, mit Python 3.11 oder neuer und installiertem Rust:

```sh
python3 -m venv build/spotify-login-venv
build/spotify-login-venv/bin/pip install paho-mqtt
build/spotify-login-venv/bin/python tools/spotify-offline/computer_login.py \
  --host JOOKI_IP --known-hosts /pfad/zur/known_hosts
```

Im Befehl `JOOKI_IP` durch die tatsächliche IP ersetzen, zum
Beispiel `172.16.17.124`. `--key` und `--port` können einen anderen SSH-Schlüssel
oder Port wählen. Der Helfer baut beim ersten Start den festgelegten Testplayer;
das kann einige Minuten dauern. Bei eingerichteter Eltern-PIN zusätzlich
`--parent-code-file /privater/pfad/pin.txt` verwenden.

1. Den Helfer laufen lassen und am **Computer** die Jooki-Webseite öffnen.
2. **Einstellungen → Spotify → Titellisten & Offline** öffnen. Für Titellisten
   mit Free **Spotify verbinden**, mit Premium direkt **Offline aktivieren · Premium** wählen.
3. Im geöffneten Browser bei Spotify anmelden und die Freigabe bestätigen.
4. Eine vorhandene Free-Verbindung lässt sich mit **Offline aktivieren · Premium**
   erweitern; dabei für beide Freigaben dasselbe Konto verwenden. Premium braucht
   für seine Titellisten keine zusätzliche Web-API-Anmeldung.
5. Warten, bis die Einstellungen die erfolgreiche Verbindung anzeigen.

Über MQTT werden nur Statusmeldungen und die öffentliche Anmeldeseite übertragen.
Der Helfer überträgt Zugangsdaten per SSH in den eigenen Speicher des Testplayers.
Mit **Abbrechen** wird ein laufender Vorgang verworfen. Ohne Helfer ist die
Anmeldetaste gesperrt und die Oberfläche verlinkt diese Anleitung.

## Playlist herunterladen

Die Spotify-Playlist öffnen. Ihre **Titelliste** lässt sich schon vor dem Download
lesen. Mit Premium erscheint zusätzlich **Offline speichern**:

- **Offline herunterladen** lädt genau diese Playlist in ihrer Reihenfolge.
- Läuft bereits ein Download, fügt die Taste die Playlist zur **Download-Queue**
  hinzu. Dort stehen Reihenfolge und Links; wartende Einträge lassen sich entfernen.
- Während aktiver Offline-Wiedergabe wartet die Queue auf Pause. Der normale
  Online-Player kann während eines Downloads weiterlaufen.
- Ein Download wird erst nach vollständiger Prüfung als **Offline verfügbar**
  veröffentlicht. Ein fehlgeschlagenes Update lässt eine vorhandene vollständige
  Kopie bestehen. Erneutes Herunterladen verwendet intakte Dateien erneut.
- Die Queue übersteht einen Neustart und gehört zum angemeldeten Konto. Bei vollem
  Speicher pausiert sie, bis Platz geschaffen und **Warteschlange fortsetzen**
  gewählt wurde. Der fehlgeschlagene Eintrag kann erneut vorgemerkt werden.

Wenn die Liste **Offline nicht verfügbar** anzeigt, erhält der Testplayer für
diesen Eintrag keine Audiodatei oder geeignete Alternative. Der Download nennt
den betroffenen Titel und hält die letzte vollständige Kopie bereit. Er überspringt
keine Einträge. Bei „Anton Fuchs“ wurden beispielsweise die ersten beiden Titel
gespeichert; Titel 3 und 4 werden vom SDK ohne Audiodateien geliefert. Die vollständige
710er-Kopie ist deshalb derzeit nicht möglich. Die Liste bleibt lesbar.

**Online** verwendet den bisherigen Player. **Automatisch** spielt die letzte
vollständige Offline-Kopie, sonst online. **Nur Offline-Kopie** benötigt einen
vollständigen Download. Abmelden deaktiviert den Offline-Weg und lässt den
bisherigen Online-Player verfügbar.

Das Speicherbudget richtet sich nach dem freien Platz auf der SD-Karte; die
Standardkonfiguration lässt 128 MiB Reserve und prüft zusätzlichen Platz für
temporäre Dateien. Es gibt kein festes 500-MB-Limit und kein automatisches Löschen
vollständiger Downloads. Nach einem Kartenwechsel wird der neue freie Platz beim
Einlesen des Katalogs berücksichtigt. Hinweise zum Kopieren und Vergrößern der
Karte stehen in [tools/sdcard](../tools/sdcard/README.md); die Offline-Testversion
formatiert keine Karte.

## Abmelden und zurück zum bisherigen Player

**Einstellungen → Spotify → Titellisten & Offline → Abmelden** entfernt die
zusätzliche Anmeldung, stoppt deren Downloads/Wiedergabe und leert die Queue.
Ein noch offener Login darf danach keine Freigabe mehr installieren. Bereits
gespeicherte Audiodaten bleiben auf der Karte dem bisherigen Konto zugeordnet;
sie werden keinem anderen Konto zugänglich gemacht. Das gespeicherte Konto des
ursprünglichen Online-Players hat seine eigene Funktion **Konto des Jooki ändern**.

## Stand der Prüfung

Es handelt sich um eine unabhängige experimentelle Integration. Hörbare Offline-
Wiedergabe, die verwalteten Transportbefehle und ein vollständiger Download mit
18 Titeln aus der installierten Oberfläche wurden auf einem Jooki 2 geprüft.
Neue Queue-, Metadaten-, Free-Anzeige- und Anmeldewege haben zusätzliche Tests.
Der Neustart ohne Internet mit Start über die Oberfläche ist inzwischen ebenfalls
geprüft. Ein echter Free-Kontotest und der physische Figurentest stehen noch aus.
[Technischer Prüfstand](../docs/34-spotify-offline-test.md).
