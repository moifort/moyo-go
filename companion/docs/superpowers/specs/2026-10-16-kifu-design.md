# Kifu : enregistrer une partie de go réelle en SGF depuis un iPhone

Date : 2026-10-16
Statut : proposé, en attente de validation par Thibaut

## Intention

Deux personnes jouent une partie sur un goban 19x19 réel. Un iPhone posé sur
le côté de la table regarde le plateau. Entre « Commencer » et « Fin de
partie », l'app note chaque coup joué, dans l'ordre, et produit un fichier SGF
que Thibaut rejoue ensuite dans KaTrain, Sabaki ou Moyo.

Le contrat tient en trois mots : **ordre juste, zéro erreur**. L'app n'a pas
besoin d'être rapide ni de réagir en direct. Elle a besoin d'être juste, et de
le rester pendant une partie d'une heure où le soleil tourne, les ombres
bougent et des bras passent au-dessus du plateau.

Pourquoi un nouveau projet : GoBoardVision (dépôt `robot/ios`) vise un 9x9 vu
du dessus, à 5 images par seconde, pour guider un bras robot. Kifu vise un
19x19 vu de biais, sans contrainte de temps, pour produire un document. Les
briques de base sont reprises (image en niveaux de gris, homographie, modèle
de plateau), le reste est reconçu.

## Conditions de prise de vue

La photo `docs/photos/2026-10-16-prise-de-vue-rasante.jpg` est la référence :

- goban 19x19 en bois clair, lignes noires, pierres classiques ;
- iPhone sur le bord de la table, vue rasante, environ 20° au-dessus du plan
  du plateau, le bord proche du plateau en bas de l'image ;
- lumière naturelle avec une ombre franche qui traverse le plateau et se
  déplace pendant la partie ;
- le téléphone ne bouge pas pendant la partie, mais peut être heurté.

Thibaut pourra surélever le support plus tard. L'algorithme doit marcher dans
ces conditions, mais l'app mesure la qualité de la prise de vue au calibrage et
dit clairement quand monter le téléphone aiderait.

Conséquences de la vue rasante, à garder en tête partout :

- les rangées lointaines sont écrasées : l'espacement vertical peut descendre à
  une quinzaine de pixels alors qu'il en fait plus de cent au premier plan ;
- une pierre a une hauteur : son dessus apparaît décalé vers le haut de
  l'image par rapport à l'intersection où elle repose, d'une fraction
  d'espacement qui dépend de l'angle ;
- une pierre au premier plan masque partiellement l'intersection située juste
  derrière elle.

## Objectifs

- Produire un SGF exact : coups dans l'ordre, couleurs justes, captures
  déduites par la règle, pierres de handicap en position de départ.
- Ne jamais écrire dans le SGF quelque chose qui ne s'explique pas par la règle
  du jeu.
- Tenir une partie entière sans intervention, et demander un arbitrage humain
  sur le moment dans les rares cas où l'app perd le fil.
- Ne rien perdre si l'app est tuée en cours de partie.

## Non-objectifs

- Jouer contre une IA, dialoguer avec un robot ou un Mac.
- Détecter automatiquement le plateau dans l'image : le calibrage se fait au
  doigt, une fois par partie, et c'est voulu (voir plus bas).
- Compter le score, détecter la fin de partie, saisir le résultat.
- Les plateaux 9x9 et 13x13 (prévus par un paramètre, non testés en v1).
- Le ko et le superko dans le validateur : un coup qui reprend un ko
  immédiatement est accepté tel que vu.

## Anti-objectifs

- Un SGF qui a l'air juste mais avec un coup décalé d'une intersection ou une
  couleur inversée. Mieux vaut une alerte en cours de partie qu'une erreur
  silencieuse.
- Une app qui réclame l'attention des joueurs. Une seule interaction
  attendue : vérifier le calibrage avant « Commencer ».

## Principe de fonctionnement

La justesse ne vient pas d'une image parfaite, elle vient du nombre et de la
cohérence. Trois filtres successifs, chacun indépendant des deux autres :

1. **Lecture locale.** Chaque intersection est lue par rapport à son voisinage
   immédiat, jamais par rapport à une valeur globale du bois. Une ombre qui
   couvre une moitié du plateau ne change pas la lecture.
2. **Stabilité temporelle.** Un changement sur une intersection n'est retenu
   que s'il est lu identique sur plusieurs images consécutives. Une main qui
   passe ne tient pas en place.
3. **Règle du jeu.** Un nouvel état n'est accepté que si le passage depuis
   l'état précédent s'explique par un ou deux coups légaux, en alternance, avec
   les captures qu'ils entraînent. Une main immobile au-dessus du plateau
   « pose » trois pierres noires d'un coup : ça ne s'explique pas, donc ça
   n'entre pas.

Ce qui ne passe pas le troisième filtre attend. Si l'attente dure, l'app alerte
(vibration, bandeau) et demande un arbitrage sur place.

## Pipeline

### Caméra

- Caméra arrière grand-angle, plus grand format 4:3 disponible en sortie
  vidéo, 2 images par seconde traitées. Aucun enregistrement vidéo.
- Mise au point verrouillée après calibrage (le plateau ne bouge pas). Exposition
  et balance des blancs restent automatiques : la lecture locale les rend
  inoffensives, et les verrouiller ferait saturer l'image quand le soleil
  arrive.
- Écran maintenu allumé pendant la partie.

### Calibrage au doigt

L'utilisateur touche les quatre coins de la grille (intersections extrêmes,
pas le bord du bois) sur l'image figée, avec une loupe pour viser précisément.
Chaque toucher est ensuite affiné automatiquement : recherche, dans un petit
voisinage, du point qui maximise le croisement de deux lignes sombres. Les
pierres posées sur un coin (fréquent avec un handicap) désactivent
l'affinement pour ce coin.

Des quatre coins, une homographie plan du plateau → image donne la position
des 361 intersections. Le plateau est plan et les lignes équidistantes, c'est
exact à la précision des coins près.

L'app affiche alors la grille projetée et les pierres telles qu'elle les lit,
plus un **indicateur de qualité** : le plus petit espacement en pixels entre
deux intersections voisines. En dessous de 12 px, elle le dit en clair :
« Monte un peu le téléphone, les rangées du fond sont trop serrées ». Elle
n'empêche pas de continuer.

« Commencer » fige le calibrage et enregistre la position lue comme position
de départ.

### Lecture d'une intersection

Tout se fait dans l'image d'origine, sans redressement : redresser une vue
rasante étire les rangées lointaines et n'apporte rien.

Pour chaque intersection, deux zones définies dans le plan du plateau et
projetées dans l'image par l'homographie :

- **zone pierre** : un disque de rayon 0,35 espacement, dont le centre est
  décalé vers le haut de l'image de `stoneLift` espacements pour suivre le
  dessus de la pierre (voir « Hauteur des pierres ») ;
- **zone bois** : les quatre centres de cases adjacents, disques de rayon
  0,15 espacement, dont on garde la médiane de luminosité.

Mesures : luminosité moyenne de la zone pierre, luminosité du bois local,
écart-type dans la zone pierre. Décision avec hystérésis :

- contraste = moyenne pierre / bois local ;
- noir si contraste < 0,55 ; blanc si contraste > 1,35 ; vide sinon ;
- une intersection déjà occupée garde sa pierre tant que le contraste reste
  du bon côté d'un seuil plus large (0,70 et 1,20), pour ne pas clignoter.

Ces seuils sont des points de départ à régler sur les photos de référence.
L'écart-type sert à écarter les cas ambigus (une main a un relief, pas une
pierre) : si l'écart-type dépasse un seuil, l'intersection est « illisible »
et n'autorise aucun changement d'état cette image-là.

### Hauteur des pierres

`stoneLift` est unique pour tout le plateau et estimé au calibrage : si des
pierres sont déjà posées (handicap), l'app cherche pour chacune le décalage qui
maximise le contraste, et prend la médiane. Sans pierre au calibrage, valeur
par défaut dérivée de l'angle de vue, lui-même déduit de l'homographie (rapport
entre l'espacement vertical au premier plan et au fond). À affiner sur les
photos de référence ; la v1 peut se contenter de la valeur par défaut si
l'estimation ne tient pas.

### Stabilité temporelle

Pour chaque intersection, l'app garde la lecture courante et depuis combien
d'images consécutives elle est identique. Une lecture ne devient
« candidate » qu'après 3 images identiques (1,5 s). Une seule image
différente remet le compteur à zéro.

### Validation par la règle

Un moteur de règles pur gère l'état de la partie : plateau, trait, captures,
suicide interdit. Il expose une seule fonction :

    explain(from: Position, to: Position, toPlay: Stone) -> [Move]?

qui rend la suite de coups (0, 1 ou 2, avec passes implicites) qui mène
exactement de `from` à `to`, ou nil. Les captures sont appliquées par le moteur
et doivent correspondre aux pierres disparues. Deux pierres apparues de la même
couleur sans passe visible ne s'expliquent pas.

À chaque image, l'app construit la position candidate (état accepté + lectures
candidates) et appelle `explain`. Si la réponse n'est pas nil, les coups sont
enregistrés et l'état accepté avance.

Cas particuliers gérés :

- **Retour en arrière** : la position candidate est égale à un état accepté
  antérieur (jusqu'à 3 coups en arrière) : les coups correspondants sont
  retirés du kifu.
- **Pierre recentrée** : une pierre disparaît et réapparaît à la même
  intersection : rien à faire, le filtre temporel absorbe.
- **Aucun changement** : rien.

### Perte du fil

Si la position candidate reste stable 8 s sans s'expliquer, l'app vibre et
affiche un bandeau : « Je ne comprends pas la position ». L'écran montre le
plateau tel qu'elle le lit, les intersections en désaccord en orange, et deux
boutons :

- « C'est bon » : l'état lu devient l'état accepté, les pierres ajoutées sont
  enregistrées comme coups dans l'ordre d'alternance, les pierres retirées
  comme captures ou retraits manuels (`AE` en SGF) ;
- « Recalibrer » : retour au calibrage, la partie enregistrée est conservée.

Un heurt du téléphone est détecté par le même mécanisme : la grille ne
correspond plus, beaucoup d'intersections deviennent illisibles ou changent
ensemble. Le bandeau propose alors « Recalibrer » en premier.

### Écriture du SGF

Le fichier est écrit dans le dossier Documents de l'app, visible dans Fichiers,
réécrit en entier après chaque coup accepté. Une app tuée ne perd donc que le
coup en cours.

    (;GM[1]FF[4]CA[UTF-8]AP[Kifu:1.0]SZ[19]DT[2026-10-16]
      KM[6.5]
      ;B[pd];W[dp]...)

Avec handicap : `HA[n]`, `AB[..][..]`, `KM[0.5]`, blanc joue en premier. Les
pierres blanches présentes au départ vont dans `AW`. Un retrait manuel validé
par « C'est bon » s'écrit `AE[..]` dans le nœud du coup suivant.

« Fin de partie » ajoute rien de plus, ferme la partie et ouvre la feuille de
partage. La liste des parties passées est accessible depuis l'écran d'accueil.

## Écrans

1. **Accueil** : bouton « Nouvelle partie », liste des SGF enregistrés
   (partage, suppression).
2. **Calibrage** : image caméra figée, consigne « Touche le coin haut-gauche
   de la grille », loupe sous le doigt, quatre repères numérotés, puis grille
   projetée et pierres lues, indicateur de qualité, boutons « Reprendre les
   coins » et « Commencer ».
3. **Partie** : image caméra en direct, grille, pierres acceptées (disques
   pleins) et dernier coup marqué, compteur de coups, bandeau d'état, boutons
   « Annuler le dernier coup » et « Fin de partie ». Le bandeau « Je ne
   comprends pas la position » avec ses deux boutons apparaît par-dessus.

Textes en français. Portrait et paysage acceptés : le téléphone est posé comme
il tombe.

## Structure du code

Dépôt `~/Code/kifu`, deux cibles :

- **`KifuCore`**, paquet Swift pur, testé sur macOS avec `swift test` :
  - `GrayImage`, `Point`, `Homography` : repris de GoBoardVisionCore ;
  - `BoardGeometry` : quatre coins → homographie → intersections et zones de
    mesure ; affinement d'un coin ;
  - `IntersectionReader` : mesures et décision par intersection ;
  - `StabilityFilter` : compteurs par intersection ;
  - `Rules` : plateau, coups légaux, captures, `explain` ;
  - `GameRecord` : coups, handicap, retraits, `undo` ;
  - `SGFWriter` ;
  - `Recorder` : enchaîne lecture, filtre, règles, kifu, à partir d'une
    `GrayImage` et d'un calibrage ; c'est lui qu'on teste de bout en bout sur
    des séquences de photos.
- **`Kifu`**, app SwiftUI générée par xcodegen, cible iOS 26 : caméra, écrans,
  stockage des fichiers. Elle ne contient aucune logique de vision ni de
  règle.

Code, commentaires et messages de commit en anglais, textes d'interface en
français, conformément à `~/Code/AGENTS.md`. Pas de dépendance externe.

## Tests

- Règles : captures simples et multiples, suicide, `explain` sur un coup, deux
  coups, deux coups de la même couleur (nil), retour en arrière.
- SGF : handicap, coups, `AE`, caractères et dates.
- Géométrie : homographie depuis quatre coins, projection des intersections,
  affinement d'un coin sur une image synthétique.
- Lecteur : plateau synthétique avec gradient d'éclairage et ombre franche,
  pierres de hauteur simulée.
- **Photos réelles** : dossier `Fixtures/` avec des photos du vrai plateau,
  quatre coins et position attendue dans un fichier annexe. Au minimum :
  plateau vide, la photo de référence à cinq pierres, une position dense, une
  main au-dessus du plateau. Le test de bout en bout rejoue une séquence de
  photos et compare le SGF produit au SGF attendu.

Les photos réelles sont le juge de paix des seuils. Thibaut les prend avec
l'app Appareil photo, téléphone sur son support ; l'app elle-même proposera
plus tard d'exporter une photo brute avec son calibrage pour alimenter les
fixtures.

## Critère de réussite

Une partie complète jouée à deux, téléphone sur son support actuel, sans
toucher à l'app entre « Commencer » et « Fin de partie », et le SGF rejoué
dans KaTrain est identique à la partie, coup pour coup. Au plus une alerte
« Je ne comprends pas la position » par partie est tolérée pendant la mise au
point, zéro à terme.

## Ce qui est laissé au bâtisseur

- Les valeurs exactes des seuils et des rayons, à régler sur les fixtures.
- La méthode d'estimation de `stoneLift` sans pierre au calibrage.
- Le format de stockage du calibrage à côté du SGF (utile pour reprendre une
  partie après un crash de l'app).
- La mise en page précise des écrans, dans l'esprit sobre des autres apps de
  Thibaut.

## Suite envisagée, hors v1

- Un petit classifieur CoreML par intersection, entraîné sur des vignettes du
  plateau de Thibaut étiquetées automatiquement par les parties acceptées, si
  la lecture par contraste ne suffit pas.
- Détection automatique du plateau pour éviter le calibrage au doigt.
- Reprise d'une partie interrompue.
