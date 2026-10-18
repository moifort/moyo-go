# Lecture locale du combat

## Pourquoi

En revue, la pastille verte montre souvent un grand coup loin du combat. C'est juste,
mais ça n'apprend rien sur le combat lui-même : comment tuer, comment sortir. La
lecture locale répond à l'autre question — le meilleur coup *ici*, et la suite, des
deux côtés.

## Décisions

| Sujet | Choix | Raison |
|---|---|---|
| Zone | Déduite par le pont : dernier coup + groupes qui le touchent, marge de 2, au moins 7×7 | Demandé ainsi pour commencer ; la tracer à la main viendra plus tard |
| Zone couvrant tout le goban | Pas de lecture locale | Elle ne dirait rien de plus que la pastille verte |
| Contrainte | `avoidMoves` pour les deux couleurs sur 12 coups | KaTrain ne contraint que le premier coup ; sa suite repart ailleurs |
| Analyse | Requête séparée, rangée hors du nœud | Sinon elle se mêle aux candidats de KaTrain et fausse la pastille verte |
| Coût | `points_lost` contre l'analyse globale du nœud | Souvent la leçon elle-même |
| Coup global déjà dans la zone | Il est aussi le coup local, coût nul | La recherche locale ne pourrait différer que par le bruit |
| Quand | Seule la position affichée est lue, une fois | Ne pas doubler le travail de KataGo sur tout le record |
| Rendu | Cadre pointillé bleu sous la grille, pastille bleue ; anneau bleu autour de la verte si elles coïncident | Les deux propositions ne se confondent jamais |

## Protocole

- `variation {step, kind}` — `kind` vaut `best` (défaut) ou `local`. Passer de l'une
  à l'autre revient d'abord au record.
- L'état de revue gagne `variation_kind` (`best`, `local` ou `null`), `local_zone`
  (`{top, left, bottom, right}`, bornes incluses, ou `null`) et `local_move`
  (`{row, col, points_lost}` ou `null` ; `points_lost` est `null` tant que l'analyse
  globale manque, et pendant le déroulé).
- Pendant une séquence locale, `best_move` est `null` ; pendant la proposition de
  KataGo, `local_zone` et `local_move` le sont.

Raccourcis : `⌥→` `⌥←` déroulent la séquence locale, qui prend ainsi le raccourci de la
proposition de KataGo ; celle-ci passe à `⇧⌥→` `⇧⌥←`.

## Hors périmètre

Voir `TODO.md` : zone tracée à la main, lecture locale en partie contre l'IA,
plusieurs zones, séquence qui sort de la zone.
