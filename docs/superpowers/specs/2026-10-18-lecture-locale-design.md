# Lecture locale du combat

## Pourquoi

En revue, la pastille verte montre souvent un grand coup loin du combat. C'est juste,
mais ça n'apprend rien sur le combat lui-même : comment tuer, comment sortir. La
lecture locale répond à l'autre question — le meilleur coup *ici*, et la suite, des
deux côtés.

## Décisions

| Sujet | Choix | Raison |
|---|---|---|
| Zone | Déduite par le pont : dernier coup + groupes qui le touchent, marge de 2, au moins 7×7, prolongée jusqu'au bord s'il est à 3 lignes ou moins (le plus proche seulement sur un petit goban) | Demandé ainsi pour commencer |
| Zone tracée | Un glisser sur le goban trace un rectangle aligné sur les intersections, qui remplace la zone déduite | La déduction se trompe dès que le dernier coup est un tenuki, ou que le combat qui compte n'est pas celui qui vient d'être joué |
| Zone tracée et navigation | Elle reste en place d'un coup à l'autre, jusqu'à Échap | Un combat se lit sur plusieurs coups ; la retracer à chaque fois serait une corvée |
| Zone redessinée | La lecture de l'ancienne zone est jetée, la séquence locale en cours revient au record, une réponse tardive pour l'ancienne zone est ignorée | La séquence affichée doit toujours appartenir à la zone affichée |
| Zone couvrant tout le goban | Pas de lecture locale | Elle ne dirait rien de plus que la pastille verte |
| Contrainte | `avoidMoves` pour les deux couleurs sur 12 coups | KaTrain ne contraint que le premier coup ; sa suite repart ailleurs |
| Analyse | Requête séparée, rangée hors du nœud | Sinon elle se mêle aux candidats de KaTrain et fausse la pastille verte |
| Coût | `points_lost` contre l'analyse globale du nœud | Souvent la leçon elle-même |
| Coup global déjà dans la zone | Il est aussi le coup local, coût nul | La recherche locale ne pourrait différer que par le bruit |
| Quand | À la demande : maintenir ⌥ lance la lecture de la position affichée, une fois | Ne pas doubler le travail de KataGo sur les positions seulement traversées |
| Affichage | Rien de local par défaut ; zone, pastille bleue et chargement tant que ⌥ est tenue ou que la séquence est déroulée ; une zone tracée reste visible | Le goban montre d'abord le meilleur coup, le local est une question qu'on pose |
| ⌥→ trop tôt | Le pont garde l'appui et joue le premier coup dès que la lecture arrive | Sinon l'appui se perd et le goban semble bloqué |
| Rendu | Cadre pointillé bleu sous la grille, pastille bleue ; anneau bleu autour de la verte si elles coïncident | Les deux propositions ne se confondent jamais |

## Protocole

- `read_local` — demande la lecture locale de la position affichée ; l'état dit
  `local_pending` tant qu'elle n'est pas revenue, et `local_wanted` si ⌥→ attend.
- `variation {step, kind}` — `kind` vaut `best` (défaut) ou `local`. Passer de l'une
  à l'autre revient d'abord au record.
- L'état de revue gagne `variation_kind` (`best`, `local` ou `null`), `local_zone`
  (`{top, left, bottom, right}`, bornes incluses, ou `null`) et `local_move`
  (`{row, col, points_lost}` ou `null` ; `points_lost` est `null` tant que l'analyse
  globale manque, et pendant le déroulé).
- Pendant une séquence locale, `best_move` est `null` ; pendant la proposition de
  KataGo, `local_zone` et `local_move` le sont.
- `set_local_zone {zone}` — `zone` vaut `{top, left, bottom, right}` (les coins dans
  n'importe quel ordre, le pont les remet en ordre et refuse une zone hors du goban
  avec `bad_arguments`), ou est absent / `null` pour revenir à la zone déduite. En
  revue seulement. L'état de revue gagne `local_zone_drawn`, vrai quand la zone vient
  du joueur.

Raccourcis : `⌥→` `⌥←` déroulent la séquence locale, qui prend ainsi le raccourci de la
proposition de KataGo ; celle-ci passe à `⇧⌥→` `⇧⌥←`. `Échap` revient à la zone
automatique, comme le bouton « viseur » de la barre latérale.

Pendant le glisser, l'app dessine le rectangle en cours plus franchement que la zone
en place ; un glisser qui commence et finit sur la même intersection ne trace rien.

## Hors périmètre

Voir `TODO.md` : une zone tracée par position, zone tracée enregistrée dans le SGF,
lecture locale en partie contre l'IA, plusieurs zones, séquence qui sort de la zone.
