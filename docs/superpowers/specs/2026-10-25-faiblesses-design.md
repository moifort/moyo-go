# Faiblesses des groupes

## Pourquoi

Pour progresser, il faut apprendre à voir où un groupe peut être attaqué : un groupe
adverse qu'on veut harceler, ou le sien qu'il faut protéger. La pastille verte dit le
meilleur coup, la lecture locale dit comment le combat tourne, mais rien ne montre
*où sont les faiblesses* avant qu'on choisisse où jouer.

L'usage visé : en analyse, repérer un point faible, y jouer, puis regarder la lecture
locale dérouler le combat à cet endroit. La lecture locale existante dessine déjà sa
zone autour du dernier coup joué, donc jouer sur le point suffit à la lancer au bon
endroit.

C'est un outil d'entraînement, pas une aide en partie contre l'IA.

## Ce que voit le joueur

- Un interrupteur « Faiblesses », comme « Estimer le score ». Allumé, il reste
  allumé d'une position à l'autre jusqu'à ce qu'on l'éteigne.
- Des **points ronds** sur des intersections vides, pas des pierres fantômes. **La
  couleur du point est celle de la pierre qui frapperait là** : un point noir veut dire
  « Noir attaque ici un groupe blanc ».
- Les deux camps en même temps : avant d'attaquer, on regarde ses propres faiblesses.
  Pas de notion de « mon camp » : en revue d'une partie importée, il n'y en a pas.
- Trois points par couleur au plus, les plus forts. Moins s'il n'y a rien de sérieux,
  et aucun point est une réponse valable.
- Un point qui frappe à la fois pour les deux couleurs (le point vital commun, cas
  fréquent : « le point vital de l'adversaire est le tien ») est dessiné mi-noir
  mi-blanc.
- Un clic sur un point joue, comme partout en analyse, la pierre du joueur au trait.
  Quand le point est de l'autre couleur, jouer là, c'est *défendre*. Pour essayer
  l'attaque de l'autre couleur, on passe d'abord (⌘P), comme aujourd'hui.

## Décisions

| Sujet | Choix | Raison |
|---|---|---|
| Source | KataGo seul, aucune règle de go en Swift ni heuristique de forme dans le pont | Principe du projet : le pont possède l'état, KataGo juge |
| Ce qu'est une faiblesse | Un coup après lequel un groupe existant bascule nettement vers le camp qui joue, d'après l'ownership de KataGo | « Attaquer un groupe », c'est exactement faire bouger sa propriété. Une coupe, un point vital, un œil retiré se voient tous ainsi, sans les nommer |
| Mesure | Pour chaque coup candidat : somme, sur les pierres de chaque groupe adverse, du basculement d'ownership vers le joueur du coup (`includeMovesOwnership`, passé par `extra_settings` de `request_analysis` de KaTrain). Le score du coup est le plus fort de ses groupes | Une somme sur les pierres pèse la taille du groupe : couper deux pierres compte moins qu'en menacer quinze |
| Seuil | Un coup ne compte que si son basculement dépasse un seuil (environ deux pierres, à régler sur des positions réelles) et que KataGo l'a vraiment envisagé (assez de visites) | Sans seuil, chaque position aurait ses trois points, et le bruit passerait pour une leçon |
| Territoire seul | Ignoré : seul le basculement sur des pierres existantes compte | Une invasion d'un moyo vide est un grand coup, pas une faiblesse de groupe |
| Les deux couleurs | Deux requêtes : la position telle quelle pour le joueur au trait, la même après un passe pour l'autre | KataGo ne propose de coups qu'au joueur au trait ; le passe est la façon usuelle de demander « et si l'autre jouait ? ». Chaque requête compare ses coups à sa propre ownership de départ |
| Rangement | Requêtes séparées, résultat gardé hors du nœud, par position, comme la lecture locale | Sinon elles se mêlent aux candidats de KaTrain et faussent la pastille verte et le graphique |
| Quand | Seulement interrupteur allumé, à chaque position où l'analyse s'arrête, une fois par position | Ne rien coûter à qui ne s'en sert pas |
| Où | En analyse (revue d'un fichier, arbre d'analyse, partie terminée lue en analyse). Pas en partie contre l'IA | Voir « Hors périmètre » |
| Rendu | Disque plein de la couleur de l'attaquant, environ 0,35 rayon de pierre, contour fin pour le blanc ; sous les pastilles verte et bleue, au-dessus du territoire | Rond pour ne pas se confondre avec les carrés du territoire estimé ; sous les pastilles parce que la proposition de KataGo reste la première chose à lire |
| Chargement | Rien d'affiché tant que les deux requêtes ne sont pas revenues ; un indicateur discret dans la barre latérale | Un camp affiché seul ferait croire que l'autre n'a pas de faiblesse |

## Protocole (pont ↔ app)

- `weaknesses {on}` : allume ou éteint, comme `estimate`. Refusé hors analyse avec
  `not_reviewing`, le code déjà employé quand aucune analyse n'est en cours.
- L'état gagne `weaknessing` (bool, l'interrupteur) et `weaknesses` : `null` si éteint
  ou pas encore revenu, sinon une liste de `{row, col, color, swing}`. `color` est
  `"B"` ou `"W"` (qui frappe), `swing` le basculement en pierres, arrondi au dixième.
  Un point commun aux deux couleurs apparaît deux fois.
- `weaknesses_pending` (bool) : vrai tant que l'une des deux requêtes manque.

Ce protocole est celui du pont et de l'app ; `docs/protocol.md` (Kifu) n'est pas
touché.

## Interface

- Menu Partie, sous « Estimer le score » : « Montrer les faiblesses » / « Masquer les
  faiblesses », ⌘⇧E. Grisé hors analyse.
- Un bouton dans la barre latérale d'analyse, à côté de celui de l'estimation.
- Les deux interrupteurs sont indépendants : estimation et faiblesses peuvent être
  affichées ensemble.

## Laissé au constructeur

- Comment créer le passe hypothétique sans l'ajouter à l'arbre (nœud détaché, ou
  requête retouchée en route comme `_Deepened` dans `local.py`).
- Le nombre de visites des deux requêtes, la valeur exacte du seuil et du minimum de
  visites : à régler sur trois ou quatre positions réelles (un groupe sans yeux, une
  coupe évidente, une position calme où rien ne doit s'afficher).
- La forme exacte de l'indicateur de chargement.

## Tests

- Pont : la sélection (fonction pure, données en entrée, données en sortie, comme
  `review.py` et `local.py`) testée sur des analyses KataGo figées : seuil, plafond de
  trois par couleur, groupes seuls comptés et pas le territoire, point commun aux deux
  couleurs.
- Pont : la session ne demande rien interrupteur éteint, une seule fois par position
  allumé, et ignore une réponse arrivée après un changement de position ou de fichier.
- App : décodage de l'état, ancien pont sans les champs compris.

## Hors périmètre

À consigner dans `TODO.md` lors du push :

- **En partie contre l'IA.** Montrer les faiblesses pendant qu'on joue, c'est souffler
  le coup ; l'outil sert à apprendre en relisant.
- **Nommer la faiblesse** (« coupe », « point vital », « œil »). Il faudrait des règles
  de forme écrites à la main, contre le principe du projet, et KataGo ne les donne pas.
- **Montrer quel groupe est visé** (un halo sur le groupe au survol du point). Utile,
  mais second : le point lui-même est l'essentiel, on verra à l'usage si le lien
  manque.
- **Cliquer pour jouer la couleur du point** même quand ce n'est pas son tour. Un
  passe implicite surprendrait dans l'arbre ; ⌘P le fait déjà explicitement.
