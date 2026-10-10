# Building and releasing Moyo

Everything a contributor needs. The README is for people who want to play.

## How it works

```
Moyo.app  ──JSON lines over stdin/stdout──>  bridge.py  ──>  katrain.core  ──>  katago
      (SwiftUI)                                           (Python)     (pip, unmodified)
```

The bridge owns the state, the app owns the pixels. No go rule is written in Swift.

## Build

Requires macOS 26+ on Apple Silicon, Xcode, Python 3.11+, and `cmake`, `ninja`
and `pkgconf` from Homebrew.

```bash
git clone https://github.com/moifort/moyo-go.git
cd moyo-go
python3 -m venv .venv
.venv/bin/pip install -r bridge/requirements-dev.txt
./app/Scripts/build-katago.sh        # ~20 min, once
./app/Scripts/build-app.sh
open app/build/Moyo.app
```

`build-katago.sh` compiles KataGo with Abseil, protobuf and libzip linked
statically, and refuses to finish if the binary keeps any non-system dependency.
Homebrew's own `katago` carries 84 Homebrew dylibs and cannot be shipped.

The bundle is self-contained — interpreter, engine, models and configuration all
live inside it, because the App Store sandbox forbids reaching outside. It weighs
about 250 MB, most of it the two KataGo models.

To verify a built bundle end to end, from inside its own sandbox — it plays a move,
reads a record back and writes it out again as SGF, and exits non-zero on the first
phase that fails:

```bash
./app/build/Moyo.app/Contents/MacOS/Moyo --smoke
```

## Develop

`MOYO_DEV_ROOT` runs the bridge from the repository's virtual environment
instead of the bundle, and leaves `~/.katrain/config.json` in charge of the
engine — so a game played this way behaves exactly like KaTrain.

## Test

```bash
.venv/bin/python -m pytest bridge/tests
swift test --package-path app
```

## Release

Un tag annoté déclenche tout, sur GitHub Actions :

```bash
git tag -a v1.0 -m "Ce qui change dans cette version…"
git push origin v1.0
```

L'annotation du tag devient le texte « Nouveautés » de l'App Store, si bien que les
notes d'une version vivent avec la version plutôt que dans un changelog.

Un seul job, et c'est délibéré : découper obligerait à faire transiter un bundle de
257 Mo entre jobs par artefacts, pour rien. La chaîne est donc séquentielle — suites
unitaires, KataGo, modèles, bundle signé et `.pkg`, **la barrière**, App Store
Connect, attachement de la build et soumission, release GitHub.

KataGo et les modèles sont mis en cache : la première release paye vingt minutes de
compilation, les suivantes non.

### La barrière

`Moyo --smoke`. Le bundle joue un coup contre KataGo, ouvre un enregistrement, le
parcourt, déroule la proposition du moteur et le réécrit en SGF — depuis son propre
sandbox, seul
endroit d'où la preuve vaut. Il sort non nul à la première phase qui échoue, et rien
n'est publié ensuite.

Un runner GitHub sait la franchir : son GPU est paravirtualisé, mais Metal y tourne
— « MPSGraph initialized on Apple Paravirtual device » — et la barrière complète y
prend une trentaine de secondes. `MOYO_SMOKE_TIMEOUT` la desserre tout de même à
900 secondes : un runner chargé peut être bien plus lent, et cette barrière ne doit
jamais échouer pour une raison qui n'est pas la bonne.

### Éprouver sans publier

Deux arrêts d'urgence, en déclenchement manuel depuis l'onglet Actions ou en ligne
de commande :

```bash
gh workflow run release.yml -f smoke_only=true    # s'arrête après la barrière, sans certificat
gh workflow run release.yml -f skip_upload=true   # s'arrête avec le .pkg, sans rien envoyer
```

### Depuis ce Mac

`app/Scripts/release.sh` fait la même chaîne en local, pour le jour où GitHub est
indisponible ou pour déboguer une étape sans attendre un runner :

```bash
MOYO_PROVISION_PROFILE=~/.moyo-signing/Moyo.provisionprofile \
ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=… \
  ./app/Scripts/release.sh v1.0
```

Il accepte les mêmes arrêts : `MOYO_SMOKE_ONLY=1` et `MOYO_SKIP_UPLOAD=1`.

### Avant la première release

L'API App Store Connect ne sait pas créer la fiche d'une application. Elle doit
exister sur appstoreconnect.apple.com — nom, UGS, langue — avec sa catégorie, sa
classification d'âge, sa politique de confidentialité et son prix. Tout cela est
exigé avant la première soumission. Ensuite seulement une build peut être attachée.
