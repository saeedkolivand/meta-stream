import Foundation

extension NSRegularExpression {
    /// A pattern written in source: a typo is a programmer error, so it traps instead of making every caller handle it.
    public static func literal(_ pattern: String, options: Options = []) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            fatalError("Bad regex literal \(pattern): \(error)")
        }
    }
}
