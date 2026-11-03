# AIOStreams per iPhone

App iOS non ufficiale per [AIOStreams](https://github.com/Viren070/AIOStreams): mostra l'app web della tua istanza dentro un guscio nativo con Liquid Glass, e riproduce i video con [AetherEngine](https://github.com/superuser404notfound/AetherEngine).

- **Si aggiorna da sola.** L'interfaccia arriva dal tuo server, quindi le novità di AIOStreams compaiono senza reinstallare l'app.
- **Liquid Glass vero.** La barra in basso, i pulsanti AirPlay e PiP e la schermata del server usano i materiali di sistema di iOS 26.
- **Player.** Dolby Vision e HDR10 sui display che li supportano, audio multicanale e Atmos, sottotitoli testuali e PGS, Picture in Picture, AirPlay, controlli dalla schermata di blocco.

## Requisiti

- iPhone con **iOS 26** o successivo.
- Un'istanza AIOStreams raggiungibile dall'iPhone.

## Installazione

1. Apri l'ultima [release](../../releases/latest) e scarica **AIOStreams.ipa**.
2. Installala con uno di questi:
   - **LiveContainer**: tocca **+**, scegli l'ipa, poi avvia AIOStreams dalla lista.
   - **SideStore** o **AltStore**: **My Apps** → **+** → scegli l'ipa.
3. Al primo avvio incolla l'indirizzo del tuo server, per esempio `https://aiostreams.example.com`. Va bene anche il link **Open in browser** che trovi in *Save & Install → AIOStreams app*.

Per cambiare server più avanti tieni premuta la scheda **Account** nella barra in basso.

L'ipa non è firmata: la firma la aggiunge l'app che usi per installarla.

## Come funziona

L'app carica l'app web di AIOStreams in una WebView e si presenta come app nativa tramite il bridge `window.aiostreamsApp`, lo stesso che usa l'app Android. Così il sito delega al codice nativo la riproduzione, i livelli di volume e luminosità, lo schermo intero e la schermata di blocco. La barra di navigazione del sito resta nascosta e al suo posto c'è quella nativa in Liquid Glass.

## Compilare

La build gira su GitHub Actions (`.github/workflows/build.yml`). In locale servono Xcode 27 e [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
sh Scripts/fetch-aetherengine.sh   # AetherEngine con le patch dell'app, in Vendor/
xcodegen generate
open AIOStreams.xcodeproj
```

Le patch al motore stanno in `Patches/AetherEngine/`:
- `0001-airplay-compatible-aac-audio.patch` aggiunge `AudioBridgeMode.airPlayCompat`, che converte l'audio in AAC stereo. Serve per le TV con AirPlay integrato (per esempio LG webOS), che rifiutano E-AC-3 e FLAC.

## Licenze

AetherEngine è distribuito con licenza LGPL v3 (più un'eccezione per gli store). AIOStreams e il suo logo appartengono ai rispettivi autori. Questo progetto non è affiliato ad AIOStreams.
