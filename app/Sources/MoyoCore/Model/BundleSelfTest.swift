import Foundation

/// Vérifie, depuis l'intérieur du sandbox, que le bundle sait jouer, relire et réécrire.
///
/// Lancer le python du bundle depuis un terminal ne prouverait rien : il porte
/// l'entitlement `inherit` et n'aurait alors aucun parent sandboxé dont hériter.
/// Le seul endroit d'où le test est fidèle, c'est l'application elle-même.
///
/// Invoquée par `Moyo --smoke`, c'est la barrière de publication : si Metal, les
/// modèles ou la chaîne de processus cassent sous sandbox, ça casse ici, et le tag
/// n'atteint pas l'App Store.
public enum BundleSelfTest {
    public static let flag = "--smoke"

    /// Un enregistrement minuscule, écrit ici plutôt que posé dans les ressources :
    /// il ne sert qu'à ce test et n'a rien à faire dans les 250 Mo qu'on expédie.
    /// Ni guillemet ni barre oblique inverse, donc il s'insère tel quel dans la
    /// commande JSON.
    private static let record =
        "(;GM[1]FF[4]SZ[9]KM[6.5]RU[japanese]PB[Noir]PW[Blanc]RE[B+R]"
        + ";B[ee];W[cc];B[gg];W[cg];B[gc])"

    /// Délai par défaut, et de quoi le desserrer là où la machine est lente.
    ///
    /// Un runner GitHub est une machine virtuelle : son GPU est paravirtualisé et
    /// KataGo y analyse bien plus lentement que sur un Mac de bureau. `MOYO_SMOKE_TIMEOUT`
    /// laisse la CI accorder le temps qu'il faut sans toucher au code.
    public static var configuredTimeout: TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment["MOYO_SMOKE_TIMEOUT"],
            let seconds = TimeInterval(raw), seconds > 0
        else { return 240 }
        return seconds
    }

    /// Code de sortie : 0 si toutes les phases passent, 1 à la première qui échoue.
    public static func run(timeout: TimeInterval = configuredTimeout) -> Int32 {
        guard let location = BridgeLocation.resolve() else {
            note("aucun emplacement de pont n'a pu être résolu")
            return 1
        }
        note("conteneur : \(NSHomeDirectory())")
        note("pont      : \(location.script.path)")

        let bridge: Conversation
        do {
            bridge = try Conversation(location: location)
        } catch {
            note("le pont n'a pas démarré — \(error)")
            return 1
        }
        defer { bridge.stop() }

        let deadline = Date().addingTimeInterval(timeout)
        for phase in phases {
            note("→ \(phase.name)")
            guard phase.body(bridge, deadline) else {
                note("ÉCHEC — \(phase.name)")
                return 1
            }
        }
        note("OK — le bundle joue, relit et réécrit")
        return 0
    }

    private struct Phase {
        let name: String
        let body: (Conversation, Date) -> Bool
    }

    private static var phases: [Phase] {
        [
            Phase(name: "KataGo répond depuis le bundle") { bridge, deadline in
                bridge.send(
                    #"{"cmd":"new_game","id":1,"size":9,"komi":5.5,"rules":"japanese","#
                        + #""human_color":"B","ai_strategy":"ai:default"}"#)
                bridge.send(#"{"cmd":"play","id":2,"row":4,"col":4}"#)
                // Le pont n'annonce pas « l'IA a joué », il republie l'état : la
                // preuve que KataGo a répondu, c'est l'apparition d'une pierre blanche.
                return bridge.await(#""color":"W""#, by: deadline)
            },

            Phase(name: "un enregistrement s'ouvre") { bridge, deadline in
                // Interpolation plutôt que concaténation : c'est là qu'un guillemet
                // ouvrant s'était perdu, et le pont répondait `bad_json`.
                bridge.send(
                    #"{"cmd":"load_sgf","id":3,"name":"smoke.sgf","contents":"\#(record)"}"#)
                return bridge.await(#""status":"review""#, by: deadline)
                    && bridge.await(#""move_count":5"#, by: deadline, alreadySeen: true)
            },

            Phase(name: "toute la partie s'analyse") { bridge, deadline in
                // La variante est inexploitable tant que l'analyse tient de la seule
                // politique : elle ne fait alors qu'un coup de long.
                bridge.await(#""done":6,"total":6"#, by: deadline)
            },

            Phase(name: "on recule d'un coup et KataGo propose") { bridge, deadline in
                bridge.send(#"{"cmd":"goto","id":4,"move_number":4}"#)
                return bridge.await(#""best_move":{"#, by: deadline)
            },

            Phase(name: "la proposition se déroule") { bridge, deadline in
                bridge.send(#"{"cmd":"variation","id":5,"step":1}"#)
                return bridge.await(#""variation_depth":1"#, by: deadline)
            },

            Phase(name: "le record reste intact") { bridge, deadline in
                bridge.send(#"{"cmd":"goto","id":6,"move_number":5}"#)
                return bridge.await(#""variation_depth":0"#, by: deadline)
            },

            Phase(name: "la partie repart en SGF") { bridge, deadline in
                // Le pont rend du texte, il n'écrit rien : c'est l'aller-retour qui
                // compte ici, le dernier coup du record doit y être.
                bridge.send(#"{"cmd":"export_sgf","id":7}"#)
                return bridge.await(#""event":"sgf""#, by: deadline)
                    && bridge.await("B[gc]", by: deadline, alreadySeen: true)
            },
        ]
    }

    private static func note(_ message: String) {
        FileHandle.standardError.write(Data("smoke: \(message)\n".utf8))
    }

    /// Le pont, ses tuyaux, et de quoi attendre une ligne sans risquer l'éternité.
    ///
    /// Les lignes arrivent sur un fil à part : lire à même le tuyau bloquerait sans
    /// échéance, et une phase qui n'aboutit pas resterait suspendue au lieu d'échouer.
    /// `@unchecked` parce que tout l'état partagé passe par le verrou, comme
    /// `BridgeProcess` — le compilateur ne peut pas le voir, nous si.
    private final class Conversation: @unchecked Sendable {
        private let process = Process()
        private let toBridge = Pipe()
        private let fromBridge = Pipe()
        private let lock = NSLock()
        private var lines: [String] = []
        private var cursor = 0
        private var buffer = Data()

        init(location: BridgeLocation) throws {
            process.executableURL = location.python
            process.arguments = [location.script.path]
            process.currentDirectoryURL = location.script.deletingLastPathComponent()
            process.environment = ProcessInfo.processInfo.environment
                .merging(location.environment) { _, new in new }
            process.standardInput = toBridge
            process.standardOutput = fromBridge
            process.standardError = FileHandle.standardError

            fromBridge.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.ingest(handle.availableData)
            }
            try process.run()
        }

        private func ingest(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock()
            defer { lock.unlock() }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                if let line = String(data: buffer[..<newline], encoding: .utf8) {
                    lines.append(line)
                    if line.contains("\"engine_failed\"") || line.contains("\"event\":\"error\"") {
                        note("le pont signale : \(line.prefix(240))")
                    }
                }
                buffer.removeSubrange(...newline)
            }
        }

        func send(_ command: String) {
            try? toBridge.fileHandleForWriting.write(contentsOf: Data((command + "\n").utf8))
        }

        /// Attend une ligne contenant `needle`, sans repasser sur celles déjà lues —
        /// sauf demande expresse, quand deux attentes portent sur le même événement.
        func await(_ needle: String, by deadline: Date, alreadySeen: Bool = false) -> Bool {
            var index = alreadySeen ? 0 : cursor
            while Date() < deadline {
                lock.lock()
                let available = lines.count
                let slice = index < available ? Array(lines[index..<available]) : []
                lock.unlock()
                for line in slice where line.contains(needle) {
                    cursor = available
                    return true
                }
                index = available
                if !alreadySeen { cursor = available }
                guard process.isRunning else {
                    note("le pont s'est arrêté en attendant \(needle)")
                    return false
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            note("expiration en attendant \(needle)")
            return false
        }

        func stop() {
            fromBridge.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }
    }
}
