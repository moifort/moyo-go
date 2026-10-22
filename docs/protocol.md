# Le plateau vu par le téléphone

Le seul lien entre Moyo et Kifu, son compagnon iPhone (`companion/`). Le format vient
de GoBoardVision ; ce fichier fait foi, et le code des deux côtés y renvoie.

## Transport

- Le téléphone s'annonce en Bonjour sous `_goboard._tcp` et écoute en TCP. Kifu
  s'annonce sous le nom « Kifu — iPhone » ; Moyo affiche plutôt le nom d'hôte résolu
  (voir `TODO.md`).
- Moyo garde la liste des téléphones en vue dès son lancement ; le joueur en choisit
  un depuis « Connecter », et Moyo ne lit que celui-là. Rien ne remonte vers le
  téléphone.
- Une ligne JSON en UTF-8 par message, terminée par `\n`. Kifu renvoie la dernière
  position à un Mac qui se connecte en cours de partie.

## La position

Envoyée à chaque changement de la position :

```json
{"follow":true,"next":"W","rows":["X........","....O....","..."],"size":9,"status":"locked"}
```

| Champ    | Type                   | Sens |
|----------|------------------------|------|
| `size`   | entier                 | Taille du plateau (9, 13, 19). |
| `rows`   | `size` chaînes         | Une par rangée, rangée 0 en haut, colonne 0 à gauche : `X` noir, `O` blanc, `.` vide. |
| `status` | `locked` / `uncertain` | `locked` quand le plateau correspond au kifu, `uncertain` quand l'arbitre de Kifu attend. Absent : `locked`. Moyo le décode mais ne s'en sert pas. |
| `follow` | booléen, facultatif    | Envoyé `true` par Kifu ; ignoré par Moyo, qui suit la partie dès que le joueur a choisi ce téléphone. |
| `next`   | `B` / `W`, facultatif  | Le trait. Envoyé par Kifu, ignoré par Moyo pour l'instant (voir `TODO.md`). |

### L'historique, à la connexion

La première ligne qu'un Mac reçoit en se connectant porte en plus la partie telle que
Kifu l'a enregistrée, pour qu'une partie rejointe en cours garde ses coups et ses
prisonniers :

```json
{"history":{"moves":[{"color":"B","point":[3,15]},{"color":"W"},{"color":"B","point":[4,4],"erased":[[2,2]]}],"setup":{"B":[],"W":[]}},"next":"W","rows":["..."],"size":19,"status":"locked"}
```

| Champ              | Type                         | Sens |
|--------------------|------------------------------|------|
| `history.setup`    | `B`, `W` : listes de `[row, col]` | Les pierres de départ (handicap, partie commencée en cours sur le téléphone). |
| `history.moves`    | liste d'objets               | Les coups dans l'ordre. `color` `B` ou `W` ; `point` `[row, col]`, absent pour une passe ; `erased`, facultatif, les pierres retirées sans capture que l'arbitre de Kifu a dû accepter avant ce coup. |

Les points sont dans la même orientation que `rows`. Les lignes suivantes n'ont pas
d'historique : seul un nouveau venu en a besoin.

Une ligne qui ne se décode pas, ou dont `rows` n'a pas `size` rangées de `size`
caractères, est ignorée.

## La fin de partie

```json
{"end":true,"result":"W+R"}
```

`result` est au format SGF (`RE[]`) et absent quand la partie s'est simplement
terminée : le téléphone ne compte pas. Moyo ouvre alors la partie suivie comme un
enregistrement en relecture, et la position suivante commence une nouvelle partie.
Kifu n'envoie pas encore ce message (voir `TODO.md`).

## Ce que Kifu envoie

Seulement la **position acceptée**, celle que les règles ont expliquée, jamais une
lecture brute de la caméra. Le plateau est tourné d'un quart de tour pour être vu
depuis la place du joueur de gauche ou de droite de l'image, au choix sur l'écran
d'accueil : le téléphone est posé sur un troisième côté de la table.

## Ce que Moyo en fait

Le téléphone n'envoie que des positions ; retrouver les coups est l'affaire du pont
(`bridge/follow.py`, `Session.follow_board`). Chaque position reçue est atteinte en
avançant de un à six coups alternés (le téléphone envoie parfois le plateau en
retard), précédés au besoin d'une passe, en revenant à une position antérieure
(un coup repris) ou en corrigeant une lecture jusqu'à trois coups en arrière ; chaque
candidat est joué par le cœur de KaTrain et gardé seulement si le plateau obtenu est
celui reçu, captures comprises. Une partie rejointe en cours rejoue l'historique
envoyé à la connexion, puis atteint la position reçue de la même façon. Une position qu'aucun coup n'explique est posée telle
quelle (`AE`, puis `AB`/`AW`) : Moyo montre le vrai plateau, signalé « Position non
reconnue », et suit le coup suivant à partir de là. Sans historique, une partie rejointe en cours place les
pierres déjà posées comme position de départ.

## Dans le code

- Kifu : `companion/KifuCore/Sources/KifuCore/BoardBroadcast.swift` (la ligne),
  `companion/Kifu/Sources/BoardServer.swift` (Bonjour et TCP).
- Moyo : `app/Sources/MoyoCore/Phone/PhoneBoard.swift` (`PhoneBoard`,
  `PhoneGameEnd`), `PhoneLink.swift` (Bonjour et TCP), `bridge/follow.py` et
  `bridge/session.py` (le suivi).

Les deux côtés ont chacun leur propre encodeur et décodeur, et leurs tests suivent ce
fichier. Un package Swift partagé est reporté (voir `TODO.md`).
