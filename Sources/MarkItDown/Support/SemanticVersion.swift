import Foundation

struct SemanticVersion: Comparable, Equatable {
    let components: [Int]

    init(_ rawValue: String) {
        self.components = SemanticVersion.normalized(rawValue)
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    static func normalized(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
