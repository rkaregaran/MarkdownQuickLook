import AppKit
import Foundation

enum MarkdownSyntaxHighlighter {
    private static let stringRegex = try! NSRegularExpression(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'")
    private static let numberRegex = try! NSRegularExpression(pattern: "\\b\\d+\\.?\\d*\\b")
    private static let typeRegex = try! NSRegularExpression(pattern: "\\b[A-Z][a-zA-Z0-9]+\\b")
    private static let hashCommentRegex = try! NSRegularExpression(pattern: "#[^\\n]*")
    private static let htmlCommentRegex = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?-->")
    private static let slashCommentRegex = try! NSRegularExpression(pattern: "//[^\\n]*")
    private static let blockCommentRegex = try! NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/")

    static func apply(to attributed: NSMutableAttributedString, language: String?, font: NSFont) {
        let code = attributed.string
        let fullRange = NSRange(location: 0, length: attributed.length)
        let boldFont = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold)

        let commentColor = NSColor.secondaryLabelColor
        let stringColor = NSColor.systemGreen
        let keywordColor = NSColor.systemPink
        let numberColor = NSColor.systemBlue
        let typeColor = NSColor.systemPurple
        var colored = IndexSet()

        func applyRegex(_ regex: NSRegularExpression, color: NSColor, bold: Bool = false) {
            for match in regex.matches(in: code, range: fullRange) {
                let range = match.range
                guard !colored.contains(integersIn: range.location..<(range.location + range.length)) else { continue }
                attributed.addAttribute(.foregroundColor, value: color, range: range)
                if bold {
                    attributed.addAttribute(.font, value: boldFont, range: range)
                }
                colored.insert(integersIn: range.location..<(range.location + range.length))
            }
        }

        for regex in commentRegexes(for: language) {
            applyRegex(regex, color: commentColor)
        }

        applyRegex(stringRegex, color: stringColor)

        if let keywordRegex = keywordRegex(for: language) {
            applyRegex(keywordRegex, color: keywordColor, bold: true)
        }

        applyRegex(numberRegex, color: numberColor)
        applyRegex(typeRegex, color: typeColor)
    }

    private static func commentRegexes(for language: String?) -> [NSRegularExpression] {
        switch normalizedLanguage(language) {
        case "python", "ruby", "bash", "sh", "zsh", "yaml", "yml":
            return [hashCommentRegex]
        case "html", "xml":
            return [htmlCommentRegex]
        default:
            return [slashCommentRegex, blockCommentRegex]
        }
    }

    private static func keywordRegex(for language: String?) -> NSRegularExpression? {
        keywordRegexes[normalizedLanguage(language)]
    }

    private static func normalizedLanguage(_ language: String?) -> String {
        language?.lowercased() ?? "default"
    }

    private static func buildKeywordRegexes() -> [String: NSRegularExpression] {
        var result: [String: NSRegularExpression] = [:]
        for (language, keywords) in keywordLists {
            let escaped = keywords.map { NSRegularExpression.escapedPattern(for: $0) }
            let pattern = "\\b(" + escaped.joined(separator: "|") + ")\\b"
            result[language] = try! NSRegularExpression(pattern: pattern)
        }
        return result
    }

    private static let keywordLists: [String: [String]] = [
        "swift": ["import", "let", "var", "func", "class", "struct", "enum", "protocol",
                  "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat",
                  "return", "throw", "throws", "try", "catch", "in", "where", "as", "is",
                  "true", "false", "nil", "self", "Self", "super", "init", "deinit",
                  "public", "private", "internal", "fileprivate", "open", "static", "override",
                  "async", "await", "some", "any", "typealias", "associatedtype", "extension",
                  "final", "lazy", "weak", "unowned", "mutating", "nonmutating",
                  "convenience", "required", "optional", "dynamic", "indirect",
                  "break", "continue", "fallthrough", "do", "defer", "inout"],
        "python": ["import", "from", "def", "class", "if", "elif", "else", "for", "while",
                   "return", "yield", "try", "except", "finally", "raise", "with", "as",
                   "True", "False", "None", "and", "or", "not", "in", "is", "lambda",
                   "pass", "break", "continue", "global", "nonlocal", "assert", "del",
                   "async", "await", "self"],
        "ruby": ["import", "from", "def", "class", "if", "elif", "else", "for", "while",
                 "return", "yield", "try", "except", "finally", "raise", "with", "as",
                 "True", "False", "None", "and", "or", "not", "in", "is", "lambda",
                 "pass", "break", "continue", "global", "nonlocal", "assert", "del",
                 "async", "await", "self"],
        "javascript": ["import", "export", "from", "let", "const", "var", "function", "class",
                       "if", "else", "switch", "case", "default", "for", "while", "do",
                       "return", "throw", "try", "catch", "finally", "new", "delete", "typeof",
                       "true", "false", "null", "undefined", "this", "super",
                       "async", "await", "yield", "of", "in", "instanceof",
                       "break", "continue", "void", "interface", "type", "enum", "extends", "implements"],
        "js": ["import", "export", "from", "let", "const", "var", "function", "class",
               "if", "else", "switch", "case", "default", "for", "while", "do",
               "return", "throw", "try", "catch", "finally", "new", "delete", "typeof",
               "true", "false", "null", "undefined", "this", "super",
               "async", "await", "yield", "of", "in", "instanceof",
               "break", "continue", "void", "interface", "type", "enum", "extends", "implements"],
        "typescript": ["import", "export", "from", "let", "const", "var", "function", "class",
                       "if", "else", "switch", "case", "default", "for", "while", "do",
                       "return", "throw", "try", "catch", "finally", "new", "delete", "typeof",
                       "true", "false", "null", "undefined", "this", "super",
                       "async", "await", "yield", "of", "in", "instanceof",
                       "break", "continue", "void", "interface", "type", "enum", "extends", "implements"],
        "ts": ["import", "export", "from", "let", "const", "var", "function", "class",
               "if", "else", "switch", "case", "default", "for", "while", "do",
               "return", "throw", "try", "catch", "finally", "new", "delete", "typeof",
               "true", "false", "null", "undefined", "this", "super",
               "async", "await", "yield", "of", "in", "instanceof",
               "break", "continue", "void", "interface", "type", "enum", "extends", "implements"],
        "go": ["package", "import", "func", "type", "struct", "interface", "map",
               "if", "else", "switch", "case", "default", "for", "range", "select",
               "return", "go", "defer", "chan", "var", "const",
               "true", "false", "nil", "break", "continue", "fallthrough"],
        "rust": ["use", "mod", "fn", "let", "mut", "const", "static", "struct", "enum", "trait", "impl",
                 "if", "else", "match", "for", "while", "loop", "in",
                 "return", "pub", "self", "Self", "super", "crate",
                 "true", "false", "as", "ref", "move", "async", "await", "where",
                 "break", "continue", "unsafe", "dyn", "type"],
        "java": ["import", "package", "class", "interface", "enum", "extends", "implements",
                 "if", "else", "switch", "case", "default", "for", "while", "do",
                 "return", "throw", "try", "catch", "finally", "new",
                 "true", "false", "null", "this", "super", "void",
                 "public", "private", "protected", "static", "final", "abstract",
                 "break", "continue", "instanceof", "synchronized", "volatile",
                 "var", "val", "fun", "when", "object", "companion", "data", "sealed"],
        "kotlin": ["import", "package", "class", "interface", "enum", "extends", "implements",
                   "if", "else", "switch", "case", "default", "for", "while", "do",
                   "return", "throw", "try", "catch", "finally", "new",
                   "true", "false", "null", "this", "super", "void",
                   "public", "private", "protected", "static", "final", "abstract",
                   "break", "continue", "instanceof", "synchronized", "volatile",
                   "var", "val", "fun", "when", "object", "companion", "data", "sealed"],
        "c": ["#include", "#import", "#define", "#ifdef", "#ifndef", "#endif", "#pragma",
              "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
              "if", "else", "switch", "case", "default", "for", "while", "do",
              "return", "break", "continue", "goto", "sizeof", "typedef",
              "struct", "union", "enum", "class", "namespace", "template", "typename",
              "const", "static", "extern", "volatile", "register", "auto",
              "true", "false", "NULL", "nullptr", "this",
              "public", "private", "protected", "virtual", "override", "final",
              "new", "delete", "throw", "try", "catch", "using"],
        "cpp": ["#include", "#import", "#define", "#ifdef", "#ifndef", "#endif", "#pragma",
                "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
                "if", "else", "switch", "case", "default", "for", "while", "do",
                "return", "break", "continue", "goto", "sizeof", "typedef",
                "struct", "union", "enum", "class", "namespace", "template", "typename",
                "const", "static", "extern", "volatile", "register", "auto",
                "true", "false", "NULL", "nullptr", "this",
                "public", "private", "protected", "virtual", "override", "final",
                "new", "delete", "throw", "try", "catch", "using"],
        "c++": ["#include", "#import", "#define", "#ifdef", "#ifndef", "#endif", "#pragma",
                "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
                "if", "else", "switch", "case", "default", "for", "while", "do",
                "return", "break", "continue", "goto", "sizeof", "typedef",
                "struct", "union", "enum", "class", "namespace", "template", "typename",
                "const", "static", "extern", "volatile", "register", "auto",
                "true", "false", "NULL", "nullptr", "this",
                "public", "private", "protected", "virtual", "override", "final",
                "new", "delete", "throw", "try", "catch", "using"],
        "objc": ["#include", "#import", "#define", "#ifdef", "#ifndef", "#endif", "#pragma",
                 "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
                 "if", "else", "switch", "case", "default", "for", "while", "do",
                 "return", "break", "continue", "goto", "sizeof", "typedef",
                 "struct", "union", "enum", "class", "namespace", "template", "typename",
                 "const", "static", "extern", "volatile", "register", "auto",
                 "true", "false", "NULL", "nullptr", "this",
                 "public", "private", "protected", "virtual", "override", "final",
                 "new", "delete", "throw", "try", "catch", "using"],
        "objective-c": ["#include", "#import", "#define", "#ifdef", "#ifndef", "#endif", "#pragma",
                        "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
                        "if", "else", "switch", "case", "default", "for", "while", "do",
                        "return", "break", "continue", "goto", "sizeof", "typedef",
                        "struct", "union", "enum", "class", "namespace", "template", "typename",
                        "const", "static", "extern", "volatile", "register", "auto",
                        "true", "false", "NULL", "nullptr", "this",
                        "public", "private", "protected", "virtual", "override", "final",
                        "new", "delete", "throw", "try", "catch", "using"],
        "bash": ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                 "case", "esac", "in", "function", "return", "local", "export",
                 "echo", "exit", "set", "unset", "readonly", "shift", "source",
                 "true", "false"],
        "sh": ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
               "case", "esac", "in", "function", "return", "local", "export",
               "echo", "exit", "set", "unset", "readonly", "shift", "source",
               "true", "false"],
        "zsh": ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                "case", "esac", "in", "function", "return", "local", "export",
                "echo", "exit", "set", "unset", "readonly", "shift", "source",
                "true", "false"],
        "default": ["if", "else", "for", "while", "return", "function", "class", "import",
                    "true", "false", "null", "nil", "let", "var", "const", "def", "fn"]
    ]

    private static let keywordRegexes = buildKeywordRegexes()
}
