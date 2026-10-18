# Kifu, le compagnon iPhone de Moyo

Enregistre une partie de go jouée sur un vrai goban, depuis un iPhone posé sur le côté de la
table, et produit le SGF à la fin. Design : `docs/superpowers/specs/2026-10-16-kifu-design.md`, protocole avec
Moyo : `docs/protocol.md` (à la racine du dépôt). Les commandes ci-dessous partent de
`companion/`.

## Tests du cœur de vision

    cd KifuCore && swift test

## Lire une photo avec l'outil en ligne de commande

    cd KifuCore && swift run -c release kifu-tool read photo.jpg \
      --anchors "0,0,712,581;18,0,1330,553;3,15,589,889;15,15,1465,871" --overlay out.png

`--corners x,y,... --rough` part de coins approximatifs et détecte la grille comme l'app ;
`--anchors` prend quatre intersections connues (`col,row,x,y`), les hoshi sont idéaux ;
`--fit 20` affine des coins déjà bons, `--measures` imprime les mesures par intersection.

## Générer, compiler, installer

    cd Kifu && xcodegen generate
    xcodebuild -project Kifu.xcodeproj -scheme Kifu -destination 'generic/platform=iOS' -allowProvisioningUpdates -quiet build
    APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Kifu*/Build/Products/Debug-iphoneos/Kifu.app" | head -1)
    xcrun devicectl device install app --device <identifiant> "$APP"
    xcrun devicectl device process launch --device <identifiant> com.thibautmottet.Kifu

## Recette

1. Nouvelle partie : « Figer l'image », zoomer à deux doigts et toucher précisément les quatre
   coins de la grille ; vérifier la grille jaune et les pierres lues, puis « Commencer ».
2. Jouer. Le bandeau dit « Partie suivie » et compte les coups ; le dernier coup porte un point rouge.
3. Après une capture, le bandeau demande de retirer les pierres capturées.
4. Si l'app perd le fil pendant 8 s, elle prend le plateau tel qu'elle le lit et continue, sans rien demander.
5. « Fin de partie » : le SGF est dans Fichiers > Kifu, et partageable depuis l'écran d'accueil.
