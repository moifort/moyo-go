# Mode Analyse et arbre des variantes

## Pourquoi

Une partie se relit pour comprendre un combat : « ici, comment je m'en sortais ? ».
La revue d'aujourd'hui montre la réponse de KataGo (pastille verte) et celle du combat
local (pastille bleue, zone), mais le goban est en lecture seule : impossible de poser
soi-même une pierre, d'essayer une idée, de voir ce que KataGo en pense, puis de revenir
au coup de la partie et d'essayer autre chose. C'est ce que font les logiciels de go
avec un arbre de variantes, et c'est ce qui manque.

KaTrain tient déjà un vrai arbre. Le pont le cache : la revue suit `children[0]`, et
chaque variante déroulée est élaguée dès qu'on en sort.

## Ce que voit le joueur

Un sélecteur **En cours / Analyse** en haut de la fenêtre (barre d'outils).

- **En cours**, rien ne change par rapport à aujourd'hui :
  - contre l'IA, on joue normalement ;
  - en suivant l'iPhone, on voit la partie du vrai goban, avec la pastille verte et le
    coup local si l'analyse KataGo est allumée. **Un clic sur le goban passe en
    Analyse** depuis la position affichée, et y pose la pierre cliquée.
- **Analyse** :
  - un clic pose une pierre de la couleur au trait, noir et blanc en alternance, avec
    les prises normales ;
  - la position affichée est analysée : pastille verte, coup local et zone, comme dans
    la revue actuelle ;
  - chaque essai devient une branche, visible dans un **arbre dans la barre latérale**,
    qui défile ; un clic sur un nœud y ramène ;
  - jouer depuis le milieu d'une branche, ou depuis un coup de la partie, ouvre une
    nouvelle branche ; jouer un coup qui existe déjà à cet endroit y entre simplement ;
  - repasser à **En cours** ramène exactement là où on en était dans la partie.

**La revue devient le mode Analyse.** Une partie terminée — contre l'IA, suivie sur
l'iPhone — et un SGF ouvert s'affichent directement en Analyse. Il n'y a plus de
partie en cours : le sélecteur disparaît.

Maquette de référence : arbre en colonne dans la barre latérale (option A retenue),
ligne de la partie verticale à gauche, branches décalées à droite à partir du coup où
elles partent, comme un graphe git.

## Décisions

| Sujet | Choix | Raison |
|---|---|---|
| Un seul mode de lecture | La revue est absorbée par l'Analyse ; flèches, pastilles, zone, ⌥→ et ⇧⌥→ y restent tels quels | Demandé : « une revue, c'est la même chose » |
| Sélecteur | Visible seulement tant qu'une partie est vivante (contre l'IA ou suivie) ; désactivé pendant le comptage après deux passes | Sans partie vivante, En cours n'a rien à montrer ; le comptage doit être tranché avant de quitter la partie |
| IA pendant l'Analyse | Elle attend. Au retour, la partie reprend au même nœud, et l'IA joue si elle doit un coup | Choisi par le joueur |
| iPhone pendant l'Analyse | Les coups du vrai goban continuent d'être suivis en silence sur la ligne de la partie ; le curseur d'analyse ne bouge pas. Au retour, on retrouve la position réelle à jour | Choisi par le joueur |
| Fin d'une partie | Abandon, comptage accepté, fin annoncée par l'iPhone : on passe en Analyse sur la dernière position, le résultat reste affiché dans la barre latérale | Choisi par le joueur : « directement en Analyse » |
| Sauvegarde | Le SGF contient la ligne de la partie et toutes les branches d'analyse, ainsi que les branches d'un SGF importé | Choisi par le joueur ; KaTrain, Sabaki et OGS les relisent |
| Branches d'un SGF importé | Affichées dans l'arbre comme les autres, navigables, jouables | *Mon choix.* L'arbre est là ; les cacher serait arbitraire. Règle l'entrée correspondante de `TODO.md` |
| Proposition de KataGo et séquence locale (⌥→, ⇧⌥→) | Les coups déroulés deviennent une branche dès qu'on quitte la ligne autrement que par sa propre touche de retour : ←, →, un clic dans l'arbre, une pierre posée, « Revenir à la partie », la vue En cours. Seuls ⌥← et ⇧⌥← retirent ses coups, un à un. Pendant le déroulé, ils apparaissent en pointillés (`preview`) | Corrigé le 20 octobre 2026 : le premier choix — un aperçu provisoire, élagué quand on en sort — effaçait la séquence testée dès que le joueur revenait à son début avec ← pour en essayer une autre |
| Ce que l'arbre montre | La ligne de la partie, les nœuds d'analyse, les nœuds d'un SGF importé, et les ancêtres de tout cela. Les restes d'un « annuler » et les corrections du suivi iPhone restent cachés tant qu'aucune branche d'analyse n'en part | Ils sont dans l'arbre de KaTrain mais ne sont pas des essais du joueur. Même règle pour la sauvegarde |
| Ligne de la partie | Contre l'IA ou en suivi : de la racine au nœud vivant. SGF importé : `children[0]` partout | Inchangé par rapport à aujourd'hui |
| Courbe de score, « Coup N sur M », jauge d'analyse | Toujours sur la ligne de la partie, même quand le curseur est dans une branche | La courbe raconte la partie, pas les essais |
| Score affiché | Celui de la position affichée, branche comprise | C'est la question qu'on pose en essayant un coup |
| Analyse KataGo en Analyse | La position affichée est toujours analysée, même si l'analyse du suivi iPhone est éteinte | *Mon choix.* Un mode Analyse sans KataGo n'a pas de sens ; l'interrupteur du suivi ne gouverne que la partie vivante |
| Passer | Un bouton « Passer » en Analyse, qui ajoute une passe à la branche | *Mon choix.* Un tenuki se lit en passant ; sans lui, on ne peut pas étudier « et si je ne réponds pas ? » |
| Supprimer une branche | Clic droit sur un nœud d'analyse, ou `⌘⌫` : « Supprimer la variante » retire ce nœud et tout ce qui en descend. Refusé sur un nœud de la partie ou d'un SGF importé | *Mon choix.* Un clic de travers créerait sinon une branche gardée jusque dans le SGF |
| Curseur dans une branche supprimée | Il remonte au parent du nœud supprimé | Le seul endroit sûr |

## Menu Analyse et raccourcis

Demandé : chaque raccourci se retrouve dans un menu de la barre de menus, avec sa
touche affichée, pour qu'on puisse le découvrir sans le connaître. C'est déjà la règle
de `GameCommands` (« every action lives here as well as in the sidebar ») ; le menu
« Revue » devient le menu « Analyse » et la reprend entièrement. Un élément inutilisable
dans l'état courant est grisé, jamais caché, pour que le menu garde sa forme.

| Élément du menu Analyse | Touche | Effet |
|---|---|---|
| Partie en cours | `⌘1` | Sélecteur sur En cours ; grisé sans partie vivante ou pendant le comptage |
| Analyse | `⌘2` | Sélecteur sur Analyse |
| — | | |
| Coup précédent | `←` | Le parent du nœud affiché, dans une branche comme dans la partie |
| Coup suivant | `→` | L'enfant par lequel on est passé en dernier, à défaut le premier |
| Variante précédente | `↑` | Variante sœur précédente au même coup |
| Variante suivante | `↓` | Variante sœur suivante au même coup |
| Début de la partie | `⌘←` | La racine |
| Fin de la variante | `⌘→` | Fin de la branche affichée (fin de la partie sur la ligne de la partie) |
| Revenir à la partie | `⌘↑` | Le coup de la ligne de la partie d'où part la branche affichée |
| — | | |
| Supprimer la variante | `⌘⌫` | Supprime le nœud affiché et sa descendance ; grisé hors nœud d'analyse |
| — | | |
| Dérouler / Remonter la séquence locale | `⌥→` `⌥←` | Inchangé |
| Dérouler / Remonter la proposition | `⇧⌥→` `⇧⌥←` | Inchangé |
| Revenir à la zone automatique | `Échap` | Inchangé |

Dans le menu « Partie », existant :

- **Passer** (`⌘P`) passe aussi en Analyse : la passe s'ajoute à la branche.
- **Annuler le coup** (`⌘Z`) en Analyse retire la dernière pierre posée quand le nœud
  affiché est une feuille d'analyse ; grisé sinon. *Mon choix* : c'est le geste
  qu'on attend après un clic de travers, et `←` suffit pour reculer sans effacer.

Les boutons de la barre latérale (Passer, Revenir à la partie) restent : le menu les
double, il ne les remplace pas.

## Pont

Le pont possède l'arbre et les deux curseurs ; l'app ne fait qu'afficher et demander.

- **Deux curseurs.** Le nœud vivant (tête de la partie contre l'IA ou suivie) et le
  nœud affiché. En En cours, ils coïncident. En Analyse, `game.current_node` est le
  nœud affiché ; le nœud vivant est gardé à part.
- **Suivi pendant l'Analyse.** `follow_board` se place sur le nœud vivant, cherche le
  chemin comme aujourd'hui, enregistre le nouveau nœud vivant, puis rend le curseur
  d'analyse. Si le coup du vrai goban est déjà une branche d'analyse à cet endroit,
  `Game.play` y entre : ce nœud devient un nœud de la partie, et la suite de la branche
  reste une branche.
- **IA pendant l'Analyse.** `_maybe_play_ai_move` ne joue jamais tant qu'on est en
  Analyse. Au retour en En cours, il est rappelé.
- **Jouer en Analyse.** `play` et `pass` posent la pierre de la couleur au trait au nœud
  affiché, quel que soit le camp de l'IA. Ils sont refusés hors Analyse comme
  aujourd'hui selon le statut de la partie.
- **Origine des nœuds.** Le pont sait, pour chaque nœud, s'il vient de la partie, d'un
  SGF importé, ou d'un coup joué en Analyse ; c'est ce qui décide de l'affichage dans
  l'arbre, de la sauvegarde et de la suppression. Le moyen (ensemble d'identifiants,
  attribut sur le nœud) est laissé à l'implémentation.
- **Identifiants.** Chaque nœud reçoit un entier stable pour la durée de la session,
  attribué par le pont ; l'app ne connaît que lui.
- **Élagage.** Seul `_pop_variation` (⌥←, ⇧⌥←) retire un coup de l'aperçu. Toute
  autre sortie passe par `_keep_preview`, qui marque les nœuds déroulés comme nœuds
  d'analyse et vide la pile de l'aperçu sans élaguer.
- **Sauvegarde.** `record.text` reçoit l'ensemble des nœuds à garder (ligne de la
  partie, nœuds d'analyse, nœuds importés, et leurs ancêtres) plutôt qu'une ligne
  unique.

## Protocole (pont ↔ app)

Rien ne change entre Kifu et Moyo : `docs/protocol.md` n'est pas touché.

Commandes nouvelles ou étendues :

- `set_view {view}` — `live` ou `analysis`. `live` refusé sans partie vivante, et
  pendant le comptage.
- `goto_node {node_id}` — affiche ce nœud ; passe en Analyse si on était en En cours.
- `navigate {to}` — les flèches : `back`, `forward`, `previous_sibling`,
  `next_sibling`, `start`, `end`, `game` (le coup de la partie d'où part la branche).
  Sans destination possible, la position reste.
- `delete_branch {node_id}` — refusé (`not_analysis_node`) sur un nœud de la partie ou
  importé.
- `play`, `pass` — acceptés en Analyse, sur le nœud affiché. En suivi, `play` depuis
  la vue En cours passe d'abord en Analyse.
- `undo` — en Analyse, retire la dernière pierre posée à la main (ou recule d'un coup
  dans l'aperçu de KataGo) ; `nothing_to_undo` sinon.
- `goto {move_number}` reste, sur la ligne de la partie.

État :

- `view` (`live` ou `analysis`), `node_id` (nœud affiché), `live_node_id` (ou `null`).
- `status` continue de décrire la partie vivante. L'ancien statut `review` désigne
  désormais « aucune partie vivante » ; son nom peut changer, l'app suit.
- Les champs de revue (`best_move`, `local_*`, `variation_*`, `score_history`…) sont
  envoyés en Analyse, quelle que soit la partie derrière.

Événement nouveau :

- `tree {nodes}` — envoyé quand la forme de l'arbre visible change (nœud ajouté,
  supprimé, rendu visible), pas à chaque état. Chaque nœud :
  `{id, parent, color, row, col, pass, origin}` où `origin` vaut `game`, `record`,
  `analysis` ou `preview` (aperçu de KataGo en cours), dans l'ordre des enfants de
  KaTrain. Un ancêtre caché gardé pour relier une branche compte comme `analysis`.
  Le numéro du coup se déduit de la profondeur.

## App

- **Sélecteur** dans la barre d'outils, un `Picker` segmenté « En cours / Analyse »,
  absent sans partie vivante.
- **Barre latérale en Analyse** : score de la position affichée, résultat de la partie
  s'il y en a un, bouton « Passer », bouton « Revenir à la partie », puis l'arbre qui
  occupe le reste de la hauteur et défile. Le nœud affiché est cerclé et gardé visible
  quand il change ; le nœud vivant est signalé.
- **Arbre** : dessin en colonnes à la manière d'un graphe git — ligne de la partie dans
  la première colonne, chaque branche dans la première colonne libre à droite à partir
  de son point de départ ; pierres noires et blanches, numéro du coup en face. Clic :
  `goto_node`. Clic droit sur un nœud d'analyse : « Supprimer la variante ».
- **Goban** : interactif en Analyse (clic = `play`, glisser = zone comme aujourd'hui).
  En suivi iPhone, un clic en En cours envoie `set_view analysis` puis `play`.
- L'interrupteur « Analyse KataGo » du suivi iPhone change de nom (par exemple
  « Suggestions KataGo ») pour ne pas se confondre avec le mode Analyse.

## Hors périmètre

À consigner dans `TODO.md` avec la raison :

- Promouvoir une branche en ligne principale d'un SGF importé.
- Afficher ou écrire les commentaires `C[]` dans l'arbre.
- Reprendre la partie contre l'IA depuis une branche d'analyse (« et si j'avais joué
  ça ? » contre l'IA) : la partie vivante reste celle qui a été jouée.
- Une zone tracée par nœud.
- Plier ou replier des branches dans l'arbre.

Les entrées de `TODO.md` réglées par ce travail en sortent : « A record under review is
read-only », « Only one variation survives a save », « Variations in an imported
record ».

## Tests

- Pont (`bridge/tests`) : deux curseurs et retour au nœud vivant ; IA muette en Analyse
  puis qui rejoue au retour ; suivi iPhone pendant l'Analyse sans bouger le curseur ;
  coup du vrai goban qui entre dans une branche d'analyse ; aperçu rendu permanent par
  un clic ; suppression refusée sur la partie ; règle de visibilité (restes d'annuler
  cachés, sauf ancêtres d'une branche) ; SGF exporté avec branches, sans restes.
- App (`swift test --package-path app`) : décodage de `tree`, `view`, `node_id` ; mise
  en colonnes de l'arbre (fonction pure, testée sans vue).
