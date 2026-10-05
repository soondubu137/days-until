import Foundation

/// A translated phrase split at its number, so the number can be set apart: "80 days" is "", "80"
/// and "days". The number comes first in every language the app has, but a translation may put
/// words before it.
nonisolated struct NumberPhrase {
    var before = ""
    var number: String
    var after = ""

    init(_ phrase: String, number: String) {
        self.number = number
        guard let range = phrase.range(of: number) else {
            after = phrase
            return
        }
        before = phrase[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        after = phrase[range.upperBound...].trimmingCharacters(in: .whitespaces)
    }
}
