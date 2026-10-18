import CoreGraphics
import Testing

@testable import MoyoCore

@Suite("Géométrie de la courbe de score")
struct ScoreCurveTests {
    @Test("Un point par coup analysé, dans l'ordre")
    func onePointPerAnalysedMove() {
        let points = ScoreCurve.points(scores: [2: 1.0, 0: 0.5, 1: -0.2], upTo: 2)
        #expect(points.map(\.move) == [0, 1, 2])
        #expect(points.map(\.value) == [0.5, -0.2, 1.0])
    }

    @Test("Un coup non analysé laisse un trou, pas un zéro")
    func missingAnalysisIsAHole() {
        let points = ScoreCurve.points(scores: [0: 0.5, 3: 1.0], upTo: 3)
        #expect(points.map(\.move) == [0, 3])
    }

    @Test("Les coups annulés ne sont plus tracés")
    func stopsAtTheCurrentMove() {
        let points = ScoreCurve.points(scores: [0: 0.5, 1: 1.0, 2: 2.0], upTo: 1)
        #expect(points.map(\.move) == [0, 1])
    }

    @Test("Le début de partie ne s'étire pas sur toute la largeur")
    func earlyGameKeepsAMinimumSpan() {
        #expect(ScoreCurve.span(moveNumber: 4, moveCount: nil) == ScoreCurve.minimumSpan)
    }

    @Test("Une partie longue couvre tous ses coups")
    func longGameSpansItself() {
        #expect(ScoreCurve.span(moveNumber: 240, moveCount: nil) == 240)
    }

    @Test("Une revue couvre tout le fichier, pas seulement la position courante")
    func reviewSpansTheWholeRecord() {
        #expect(ScoreCurve.span(moveNumber: 12, moveCount: 180) == 180)
    }

    @Test("L'échelle ne descend pas sous son plancher")
    func scaleFloor() {
        let points = [ScoreCurve.Point(move: 0, value: 0.2)]
        #expect(ScoreCurve.scale(for: points) == ScoreCurve.minimumScale)
    }

    @Test("L'échelle suit un écart important")
    func scaleFollowsPeak() {
        let points = [ScoreCurve.Point(move: 0, value: -32.0), ScoreCurve.Point(move: 1, value: 3)]
        #expect(ScoreCurve.scale(for: points) == 32)
    }

    @Test("Le dernier coup d'une partie pleine touche le bord droit")
    func lastMoveReachesTheRightEdge() {
        #expect(ScoreCurve.x(move: 100, span: 100, width: 200) == 200)
        #expect(ScoreCurve.x(move: 50, span: 100, width: 200) == 100)
    }

    @Test("Une avance monte, un retard descend, l'égalité reste au milieu")
    func leadRisesDeficitSinks() {
        #expect(ScoreCurve.y(value: 0, scale: 5, height: 40) == 20)
        #expect(ScoreCurve.y(value: 5, scale: 5, height: 40) == 0)
        #expect(ScoreCurve.y(value: -5, scale: 5, height: 40) == 40)
        #expect(ScoreCurve.y(value: 2.5, scale: 5, height: 40) == 10)
    }

    @Test("Un écart au-delà de l'échelle reste dans le graphe")
    func clampsToTheChart() {
        #expect(ScoreCurve.y(value: 500, scale: 5, height: 40) == 0)
        #expect(ScoreCurve.y(value: -500, scale: 5, height: 40) == 40)
    }
}

@Suite("Mise en forme du chiffre de score")
struct ScoreLabelTests {
    @Test("Le chiffre nu, sans signe : la couleur porte le sens")
    func label() {
        #expect(ScoreChart.label(for: 2.4) == "2,4")
        #expect(ScoreChart.label(for: -0.3) == "0,3")
    }

    @Test("Le chiffre signé, pour la lecture en tête du graphe")
    func signedLabel() {
        #expect(ScoreChart.signedLabel(for: 2.4) == "+2,4")
        #expect(ScoreChart.signedLabel(for: -0.3) == "−0,3")
    }

    @Test("Une partie serrée affiche zéro sans signe")
    func closeGame() {
        #expect(ScoreChart.label(for: 0) == "0")
        #expect(ScoreChart.label(for: 0.02) == "0")
        #expect(ScoreChart.signedLabel(for: -0.04) == "0")
    }

    @Test("Les grands écarts restent lisibles")
    func wideMargins() {
        #expect(ScoreChart.label(for: 132.5) == "132,5")
        #expect(ScoreChart.signedLabel(for: -7) == "−7,0")
    }
}
