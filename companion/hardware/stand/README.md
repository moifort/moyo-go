# Support d'iPhone 17 Pro pour filmer le goban

Support imprimé en 3D (Bambu Lab X2D, 256 × 256 × 261 mm) qui tient l'iPhone au
bord du goban, grand-angle 13 mm tourné vers le plateau. Quatre pièces, pas de
vis : socle avec languette qui passe sous le goban, rallonge de colonne, tête
inclinée, berceau. L'app doit être en mode « Grand-angle (0,5×) » (réglage sur
l'écran d'accueil).

Fichiers :

- `geometry.py` : les calculs optiques, et `python3 geometry.py --scad` écrit
  `params.scad` ;
- `stand.scad` : le modèle paramétrique OpenSCAD ;
- `stand-*.stl` : les quatre pièces, déjà orientées pour l'impression.

## Hauteur optimale : ce que disent les optiques

Modèle : l'objectif est à `h` au-dessus de la surface du plateau et à `d` à
l'extérieur du bord, l'axe optique plonge de `alpha` sous l'horizontale. On
projette les quatre coins de la zone à voir (grille 19×19 + une pierre et demie
de marge, soit 477 × 446 mm) et on exige qu'ils tombent à 8 % du bord de l'image.
Champ retenu pour le grand-angle, après correction de distorsion : 106°
horizontal en 4:3, soit 118° en diagonale (Apple annonce « 120° ») ; objectif
principal 24 mm : 72°.

Résultat, grand-angle en paysage (le petit côté de l'image dans la profondeur) :

| h au-dessus du plateau | d minimal | élévation sur le bord lointain | px par case au fond (4032 px) |
|---|---|---|---|
| 200 mm | 90 mm | 21° | 73 × 28 |
| 225 mm | 30 mm | 26° | 83 × 41 |
| 250 mm | surplomb possible | 34° | 101 × 68 |
| 300 mm | surplomb possible | 39° | 91 × 65 |

Le grand-angle cadre tout le goban dès 225 mm, objectif à l'aplomb du bord. En
dessous, il faut reculer le téléphone et l'angle sur le fond redevient rasant.
Au-dessus, on gagne en élévation sur les rangées du fond (moins d'occultation
par les pierres, cases du fond moins écrasées) et on perd lentement en
résolution. L'objectif principal, lui, demande au moins 375 mm avec un recul de
90 mm pour voir les coins proches : le grand-angle est ce qui permet un support
compact posé au bord.

Choix retenu : **objectif à 300 mm au-dessus du plateau, 25 mm à l'extérieur du
bord, axe à 60° sous l'horizontale** (téléphone incliné à 30° de l'horizontale,
écran vers le joueur). Le goban occupe 67 % du cadre, bord proche vu à 87°,
bord lointain à 33°, 75 × 45 px par case au fond. Pour le goban de 60 mm
d'épaisseur, l'objectif est donc à 360 mm au-dessus de la table.

Le portrait marche aussi (le berceau l'accepte) mais le petit côté de l'image
se retrouve dans la largeur du plateau : il faut alors 300 mm minimum, et le
paysage reste meilleur à hauteur égale.

## Pièces et impression

| Pièce | Orientation | Notes |
|---|---|---|
| `stand-base.stl` | debout, telle quelle | socle 140 × 130 mm, languette de 2,4 mm sur 80 mm sous le goban, colonne 20 × 40 jusqu'à 255 mm |
| `stand-extension.stl` | retournée, douille en bas | 81 mm pour un goban de 60 mm, recalculée par `stand.scad` ; inutile si la colonne tient en une pièce |
| `stand-head.stl` | couchée sur le flanc | tête à 30°, tenon, bossage qui positionne le berceau |
| `stand-frame.stl` | dos sur le plateau | berceau 160 × 100 mm, fenêtres pour le plateau caméra aux deux bouts, poche pour le bossage |

PLA ou PETG, 0,2 mm, 4 parois, 20 % de remplissage, aucun support. Tenon et
douille ont 0,25 mm de jeu par côté ; si l'emboîtement est trop serré ou trop
lâche, ajuster `joint_play` et réexporter.

Export :

    python3 geometry.py --scad
    openscad -o stand-base.stl      -D 'part="base"'      stand.scad
    openscad -o stand-extension.stl -D 'part="extension"' stand.scad
    openscad -o stand-head.stl      -D 'part="head"'      stand.scad
    openscad -o stand-frame.stl     -D 'part="frame"'     stand.scad

## Mise en place

1. Glisser la languette sous le bord du goban, côté long, la marche du socle
   contre la face du goban. Le poids du goban bloque le support.
2. Emboîter rallonge, tête, puis poser le berceau sur la tête : son bossage
   entre dans la poche au dos du berceau, la gravité fait le reste.
3. Poser l'iPhone en paysage, le bloc caméra d'un côté ou de l'autre, le dos
   contre le berceau, un grand côté sur la lèvre. La lèvre ne touche le
   téléphone qu'aux deux bouts (zones sans bouton), les boutons sont dans le
   renfoncement central. Les encoches des parois laissent passer un câble USB-C
   pour une longue partie.
4. Faire glisser le support le long du bord pour que l'objectif grand-angle
   soit au milieu du goban, puis calibrer dans l'app.

Avec l'objectif grand-angle du côté de la lèvre, il est 25 mm à l'extérieur du
bord, 300 mm au-dessus du plateau, exactement les chiffres ci-dessus. Téléphone
retourné (objectif du côté haut du berceau), il est 33 mm plus vers le plateau
et 19 mm plus haut : encore un peu mieux.

## Adapter

Tout part de `geometry.py` : épaisseur du goban (`BOARD_THICKNESS`), hauteur et
recul voulus (`DESIGN_H`, `DESIGN_D`), inclinaison (`DESIGN_ALPHA`), étui
(ajouter à `PHONE_T`, `PHONE_W`, `PHONE_L`). Le script annonce si le cadrage
tient, puis `stand.scad` dérive la hauteur de colonne et coupe la rallonge
en conséquence. Position de l'objectif grand-angle sur le dos (17 mm du bord
long, 30 mm du haut) : approximative, la fenêtre du berceau a 46 × 78 mm pour
tout le bloc caméra.
