# Conventions du projet

## TODO.md

**`TODO.md` est mis à jour à chaque push.** Toute idée écartée, tout report décidé en
cours de route y est consigné *avant* de pousser, avec la raison du report — c'est le
raisonnement qui doit survivre, pas seulement l'intention. Le fichier est écrit en
anglais, le reste de la documentation en français.

## Principe directeur

Le pont possède l'état, l'app possède les pixels. Aucune règle du go n'est écrite en
Swift : toute divergence de comportement avec KaTrain amont est un bug du pont.

## Le compagnon

`companion/` contient Kifu, l'app iPhone qui filme un vrai goban et enregistre la
partie. Elle a ses propres règles (l'arbitre de `KifuCore`), indépendantes du pont :
elle tourne sans Mac. Le seul lien avec Moyo est la ligne JSON décrite dans
`docs/protocol.md` ; tout changement de format passe par ce fichier, puis par les
deux côtés (`BoardBroadcast` dans Kifu, `PhoneBoard` dans Moyo) dans le même commit.

## Tests

```bash
.venv/bin/python -m pytest bridge/tests
swift test --package-path app
swift test --package-path companion/KifuCore
(cd companion/Kifu && xcodegen generate) && xcodebuild -project companion/Kifu/Kifu.xcodeproj \
  -scheme Kifu -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet build
```
