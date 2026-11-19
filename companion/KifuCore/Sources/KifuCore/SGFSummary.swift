import Foundation

/// What the list of saved games says about each one, read from its SGF.
public enum SGFSummary {
    /// The moves in the record, passes included: every `B` or `W` property. Text
    /// inside a value — a comment, a name — never counts, `;` and `B[` included.
    public static func moveCount(in sgf: String) -> Int {
        var count = 0
        var inValue = false
        var escaped = false
        var identifier = ""
        /// A value just closed: a letter now starts the next property's name.
        var closed = false
        for character in sgf {
            if inValue {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "]" {
                    inValue = false
                    closed = true
                }
                continue
            }
            if character == "[" {
                inValue = true
                closed = false
                if identifier == "B" || identifier == "W" { count += 1 }
                // Further values of the same property (`AB[dd][pp]`) keep its name.
                continue
            }
            if character.isLetter, character.isUppercase {
                if closed { identifier = ""; closed = false }
                identifier.append(character)
            } else if !character.isWhitespace {
                identifier = ""
            }
        }
        return count
    }
}
