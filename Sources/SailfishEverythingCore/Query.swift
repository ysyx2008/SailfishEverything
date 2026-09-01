import Foundation

public enum SizeCompare: Equatable, Sendable {
    case greater(Int64)
    case less(Int64)
    case equal(Int64)
}

public enum DateCompare: Equatable, Sendable {
    case range(Date, Date)
    case after(Date)
    case before(Date)
}

public indirect enum QueryTerm: Equatable, Sendable {
    case text(String)
    case ext([String])
    case size(SizeCompare)
    case date(DateCompare)
    case created(DateCompare)
    case fileOnly
    case folderOnly
    case path(String)
    case parent(String)
    case name(String)
    case startsWith(String)
    case endsWith(String)
    case exact(String)
    case nameLength(SizeCompare)
    case regex(String)
    case emptyFile
    case not(QueryTerm)
}

public struct Query: Equatable, Sendable {
    public var orGroups: [[QueryTerm]]

    public static let empty = Query(orGroups: [])

    public var isEmpty: Bool { orGroups.isEmpty || orGroups.allSatisfy(\.isEmpty) }

    public var needsMetadata: Bool {
        orGroups.contains { group in
            group.contains(where: Self.termNeedsMetadata)
        }
    }

    private static func termNeedsMetadata(_ term: QueryTerm) -> Bool {
        switch term {
        case .size, .date, .created, .emptyFile:
            return true
        case .not(let inner):
            return termNeedsMetadata(inner)
        default:
            return false
        }
    }

    public var simpleText: String? {
        let groups = packedTextGroups
        guard let groups, groups.count == 1, groups[0].count == 1 else { return nil }
        return groups[0][0]
    }

    public var packedTextGroups: [[String]]? {
        guard !orGroups.isEmpty else { return nil }
        var groups: [[String]] = []
        groups.reserveCapacity(orGroups.count)
        for group in orGroups {
            guard !group.isEmpty else { return nil }
            var texts: [String] = []
            texts.reserveCapacity(group.count)
            for term in group {
                guard case .text(let text) = term, !text.contains("*"), !text.contains("?") else {
                    return nil
                }
                texts.append(text)
            }
            groups.append(texts)
        }
        return groups
    }

    public static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> Query {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let tokens = tokenize(trimmed)
        var groups: [[QueryTerm]] = [[]]
        var negateNext = false
        for token in tokens {
            switch token {
            case .or:
                if let last = groups.last, !last.isEmpty {
                    groups.append([])
                }
                negateNext = false
            case .and:
                continue
            case .not:
                negateNext.toggle()
            case .word(let word):
                guard let term = parseTerm(word, now: now, calendar: calendar) else {
                    negateNext = false
                    continue
                }
                groups[groups.count - 1].append(negateNext ? .not(term) : term)
                negateNext = false
            }
        }
        return Query(orGroups: groups.filter { !$0.isEmpty })
    }

    public func matches(_ entry: FileEntry, options: SearchOptions) -> Bool {
        if isEmpty { return true }
        return orGroups.contains { group in
            group.allSatisfy { term in
                evaluate(term, entry: entry, options: options)
            }
        }
    }

    public static func makeRegex(_ pattern: String, matchCase: Bool = false) -> NSRegularExpression? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        var regexOptions: NSRegularExpression.Options = []
        if !matchCase { regexOptions.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: trimmed, options: regexOptions)
    }

    public static func isValidRegex(_ pattern: String, matchCase: Bool = false) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return makeRegex(trimmed, matchCase: matchCase) != nil
    }

    public static func matchesRegex(_ entry: FileEntry, pattern: String, options: SearchOptions) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        guard let regex = makeRegex(trimmed, matchCase: options.matchCase) else { return false }
        return matchesRegex(entry, regex: regex, options: options)
    }

    public static func matchesRegex(_ entry: FileEntry, regex: NSRegularExpression, options: SearchOptions) -> Bool {
        let haystack: String
        if options.matchPath {
            haystack = options.matchCase ? entry.path : entry.pathLower
        } else {
            haystack = options.matchCase ? entry.name : entry.nameLower
        }
        let range = NSRange(haystack.startIndex..., in: haystack)
        return regex.firstMatch(in: haystack, options: [], range: range) != nil
    }

    public static func canNarrow(from old: String, to new: String) -> Bool {
        guard !old.isEmpty, new.count >= old.count, new.hasPrefix(old) else { return false }
        if containsOrOperator(old) || containsOrOperator(new) { return false }
        let special = CharacterSet(charactersIn: "|!:")
        if old.unicodeScalars.contains(where: { special.contains($0) }) { return false }
        if new.dropFirst(old.count).unicodeScalars.contains(where: { special.contains($0) }) { return false }
        return true
    }

    private static func containsOrOperator(_ text: String) -> Bool {
        tokenize(text).contains { token in
            if case .or = token { return true }
            return false
        }
    }

    private enum RawToken: Equatable {
        case or
        case and
        case not
        case word(String)
    }

    private static func tokenize(_ text: String) -> [RawToken] {
        var tokens: [RawToken] = []
        var current = ""
        var inQuotes = false

        func flush(quoted: Bool) {
            guard !current.isEmpty else { return }
            if quoted {
                tokens.append(.word(current))
            } else {
                switch current.lowercased() {
                case "or": tokens.append(.or)
                case "and": tokens.append(.and)
                case "not": tokens.append(.not)
                default: tokens.append(.word(current))
                }
            }
            current = ""
        }

        for ch in text {
            if ch == "\"" {
                if inQuotes {
                    flush(quoted: true)
                    inQuotes = false
                } else {
                    flush(quoted: false)
                    inQuotes = true
                }
                continue
            }
            if !inQuotes, ch.isWhitespace {
                flush(quoted: false)
                continue
            }
            if !inQuotes, ch == "|" {
                flush(quoted: false)
                tokens.append(.or)
                continue
            }
            current.append(ch)
        }
        flush(quoted: inQuotes)
        return tokens
    }

    private static func parseTerm(_ token: String, now: Date, calendar: Calendar) -> QueryTerm? {
        if token.hasPrefix("!"), token.count > 1 {
            let inner = String(token.dropFirst())
            guard let term = parseTerm(inner, now: now, calendar: calendar) else { return nil }
            return .not(term)
        }
        let lower = token.lowercased()
        if lower == "file:" || lower == "files:" { return .fileOnly }
        if lower == "folder:" || lower == "folders:" { return .folderOnly }
        if lower.hasPrefix("ext:") {
            let list = token.dropFirst(4).split(separator: ";").map { String($0).lowercased().trimmingCharacters(in: .whitespaces) }
            return .ext(list.filter { !$0.isEmpty })
        }
        if lower.hasPrefix("size:") {
            return parseSize(String(token.dropFirst(5))) ?? .size(.equal(-1))
        }
        if let dateRaw = dateValue(from: token) {
            return parseDate(dateRaw, now: now, calendar: calendar)
        }
        if let createdRaw = createdValue(from: token) {
            if case .date(let pred) = parseDate(createdRaw, now: now, calendar: calendar) {
                return .created(pred)
            }
            return .created(.range(.distantFuture, .distantFuture))
        }
        if lower == "empty:" {
            return .emptyFile
        }
        if let value = prefixedValue(token, prefixes: ["startwith:", "startswith:"]) {
            return .startsWith(value)
        }
        if let value = prefixedValue(token, prefixes: ["endwith:", "endswith:"]) {
            return .endsWith(value)
        }
        if let value = prefixedValue(token, prefixes: ["exact:"]) {
            return .exact(value)
        }
        if let value = prefixedValue(token, prefixes: ["regex:"]) {
            return .regex(value)
        }
        if let value = prefixedValue(token, prefixes: ["len:"]) {
            return parseLength(value) ?? .nameLength(.equal(-1))
        }
        if lower.hasPrefix("path:") {
            return .path(String(token.dropFirst(5)))
        }
        if lower.hasPrefix("parent:") {
            return .parent(String(token.dropFirst(7)))
        }
        if lower.hasPrefix("name:") {
            return .name(String(token.dropFirst(5)))
        }
        return .text(token)
    }

    private static func dateValue(from token: String) -> String? {
        prefixedValue(token, prefixes: ["date-modified:", "datemodified:", "date:", "dm:"])
    }

    private static func createdValue(from token: String) -> String? {
        prefixedValue(token, prefixes: ["date-created:", "datecreated:", "dc:"])
    }

    private static func prefixedValue(_ token: String, prefixes: [String]) -> String? {
        let lower = token.lowercased()
        for prefix in prefixes where lower.hasPrefix(prefix) {
            return String(token.dropFirst(prefix.count))
        }
        return nil
    }

    private static func parseDate(_ raw: String, now: Date, calendar: Calendar) -> QueryTerm {
        let never = DateCompare.range(.distantFuture, .distantFuture)
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .date(never) }

        enum Mode { case range, afterDay, afterStart, beforeDay, beforeEnd }
        var mode = Mode.range
        var rest = text
        if text.hasPrefix(">=") {
            mode = .afterStart
            rest = String(text.dropFirst(2))
        } else if text.hasPrefix(">") {
            mode = .afterDay
            rest = String(text.dropFirst())
        } else if text.hasPrefix("<=") {
            mode = .beforeEnd
            rest = String(text.dropFirst(2))
        } else if text.hasPrefix("<") {
            mode = .beforeDay
            rest = String(text.dropFirst())
        }

        guard let window = dateWindow(rest, now: now, calendar: calendar) else {
            return .date(never)
        }
        switch mode {
        case .range: return .date(.range(window.start, window.end))
        case .afterDay: return .date(.after(window.end))
        case .afterStart: return .date(.after(window.start))
        case .beforeDay: return .date(.before(window.start))
        case .beforeEnd: return .date(.before(window.end))
        }
    }

    private static func dateWindow(_ token: String, now: Date, calendar: Calendar) -> (start: Date, end: Date)? {
        let startOfDay = calendar.startOfDay(for: now)
        if token == "today" {
            let end = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return (startOfDay, end)
        }
        if token == "yesterday" {
            let start = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
            return (start, startOfDay)
        }
        if token == "thisweek" {
            return calendar.dateInterval(of: .weekOfYear, for: now).map { ($0.start, $0.end) }
        }
        if token == "lastweek" {
            guard let this = calendar.dateInterval(of: .weekOfYear, for: now),
                  let prevDay = calendar.date(byAdding: .weekOfYear, value: -1, to: this.start) else { return nil }
            return calendar.dateInterval(of: .weekOfYear, for: prevDay).map { ($0.start, $0.end) }
        }
        if token == "thismonth" {
            return calendar.dateInterval(of: .month, for: now).map { ($0.start, $0.end) }
        }
        if token == "lastmonth" {
            guard let this = calendar.dateInterval(of: .month, for: now),
                  let prev = calendar.date(byAdding: .month, value: -1, to: this.start) else { return nil }
            return calendar.dateInterval(of: .month, for: prev).map { ($0.start, $0.end) }
        }
        if token == "thisyear" {
            return calendar.dateInterval(of: .year, for: now).map { ($0.start, $0.end) }
        }
        if token == "last7days" || token == "past7days" {
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now.addingTimeInterval(1))
        }
        if token == "last30days" || token == "past30days" {
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return (start, now.addingTimeInterval(1))
        }
        if token.hasPrefix("last"), token.hasSuffix("days") {
            let number = token.dropFirst(4).dropLast(4)
            if let days = Int(number), days > 0, days < 4000 {
                let start = calendar.date(byAdding: .day, value: -days, to: now) ?? now
                return (start, now.addingTimeInterval(1))
            }
        }
        if let day = parseCivilDate(token, calendar: calendar) {
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return (day, end)
        }
        return nil
    }

    private static func parseCivilDate(_ raw: String, calendar: Calendar) -> Date? {
        let normalized = raw.replacingOccurrences(of: "/", with: "-")
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd", "yyyyMMdd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return calendar.startOfDay(for: date)
            }
        }
        return nil
    }

    private static func parseSize(_ raw: String) -> QueryTerm? {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }
        let compare: (Int64) -> SizeCompare
        var rest = text
        if text.hasPrefix(">=") {
            rest = String(text.dropFirst(2))
            compare = { .greater($0 - 1) }
        } else if text.hasPrefix("<=") {
            rest = String(text.dropFirst(2))
            compare = { .less($0 + 1) }
        } else if text.hasPrefix(">") {
            rest = String(text.dropFirst())
            compare = { .greater($0) }
        } else if text.hasPrefix("<") {
            rest = String(text.dropFirst())
            compare = { .less($0) }
        } else {
            compare = { .equal($0) }
        }
        guard let bytes = parseByteCount(rest) else { return nil }
        return .size(compare(bytes))
    }

    private static func parseByteCount(_ raw: String) -> Int64? {
        let units: [(String, Int64)] = [
            ("tb", 1_099_511_627_776),
            ("gb", 1_073_741_824),
            ("mb", 1_048_576),
            ("kb", 1_024),
            ("b", 1),
        ]
        for (suffix, factor) in units {
            if raw.hasSuffix(suffix) {
                let number = raw.dropLast(suffix.count)
                if let value = Double(number) {
                    return Int64(value * Double(factor))
                }
            }
        }
        return Int64(raw)
    }

    private func evaluate(_ term: QueryTerm, entry: FileEntry, options: SearchOptions) -> Bool {
        switch term {
        case .not(let inner):
            return !evaluate(inner, entry: entry, options: options)
        case .fileOnly:
            return !entry.isDirectory
        case .folderOnly:
            return entry.isDirectory
        case .ext(let exts):
            let ext = entry.fileExtension
            return exts.contains(ext)
        case .size(let pred):
            guard !entry.isDirectory, let size = FileMetadata.size(of: entry) else { return false }
            switch pred {
            case .greater(let n): return size > n
            case .less(let n): return size < n
            case .equal(let n): return size == n
            }
        case .date(let pred):
            return dateMatches(FileMetadata.modified(of: entry), pred)
        case .created(let pred):
            return dateMatches(FileMetadata.created(of: entry), pred)
        case .startsWith(let needle):
            if needle.isEmpty { return false }
            return prefixMatches(entry, needle: needle, options: options)
        case .endsWith(let needle):
            if needle.isEmpty { return false }
            return suffixMatches(entry, needle: needle, options: options)
        case .exact(let needle):
            if needle.isEmpty { return false }
            let haystack = options.matchPath
                ? (options.matchCase ? entry.path : entry.pathLower)
                : (options.matchCase ? entry.name : entry.nameLower)
            let term = options.matchCase ? needle : needle.lowercased()
            return haystack == term
        case .nameLength(let pred):
            let count = Int64(entry.name.count)
            switch pred {
            case .greater(let n): return count > n
            case .less(let n): return count < n
            case .equal(let n): return count == n
            }
        case .regex(let pattern):
            if pattern.isEmpty { return false }
            return regexMatches(entry, pattern: pattern, options: options)
        case .emptyFile:
            return !entry.isDirectory && FileMetadata.size(of: entry) == 0
        case .path(let needle):
            if needle.isEmpty { return false }
            return textMatches(haystack: options.matchCase ? entry.path : entry.pathLower, needle: needle, options: options, forcePath: true)
        case .parent(let needle):
            if needle.isEmpty { return false }
            let parentName = URL(fileURLWithPath: entry.directory).lastPathComponent
            let haystack = options.matchCase ? parentName : parentName.lowercased()
            return textMatches(haystack: haystack, needle: needle, options: options, forcePath: false)
        case .name(let needle):
            if needle.isEmpty { return false }
            let haystack = options.matchCase ? entry.name : entry.nameLower
            return textMatches(haystack: haystack, needle: needle, options: options, forcePath: false)
        case .text(let needle):
            let haystack: String
            if options.matchPath {
                haystack = options.matchCase ? entry.path : entry.pathLower
            } else {
                haystack = options.matchCase ? entry.name : entry.nameLower
            }
            return textMatches(haystack: haystack, needle: needle, options: options, forcePath: false)
        }
    }

    private func dateMatches(_ date: Date?, _ pred: DateCompare) -> Bool {
        guard let date else { return false }
        switch pred {
        case .range(let start, let end):
            return date >= start && date < end
        case .after(let bound):
            return date >= bound
        case .before(let bound):
            return date < bound
        }
    }

    private func prefixMatches(_ entry: FileEntry, needle: String, options: SearchOptions) -> Bool {
        let haystack = options.matchPath
            ? (options.matchCase ? entry.path : entry.pathLower)
            : (options.matchCase ? entry.name : entry.nameLower)
        let term = options.matchCase ? needle : needle.lowercased()
        return haystack.hasPrefix(term)
    }

    private func suffixMatches(_ entry: FileEntry, needle: String, options: SearchOptions) -> Bool {
        let haystack = options.matchPath
            ? (options.matchCase ? entry.path : entry.pathLower)
            : (options.matchCase ? entry.name : entry.nameLower)
        let term = options.matchCase ? needle : needle.lowercased()
        return haystack.hasSuffix(term)
    }

    private func regexMatches(_ entry: FileEntry, pattern: String, options: SearchOptions) -> Bool {
        guard Query.isValidRegex(pattern, matchCase: options.matchCase) else { return false }
        let haystack = options.matchPath
            ? (options.matchCase ? entry.path : entry.pathLower)
            : (options.matchCase ? entry.name : entry.nameLower)
        var regexOptions: NSRegularExpression.Options = []
        if !options.matchCase { regexOptions.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else { return false }
        let range = NSRange(haystack.startIndex..., in: haystack)
        return regex.firstMatch(in: haystack, options: [], range: range) != nil
    }

    private static func parseLength(_ raw: String) -> QueryTerm? {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }
        let compare: (Int64) -> SizeCompare
        var rest = text
        if text.hasPrefix(">=") {
            rest = String(text.dropFirst(2))
            compare = { .greater($0 - 1) }
        } else if text.hasPrefix("<=") {
            rest = String(text.dropFirst(2))
            compare = { .less($0 + 1) }
        } else if text.hasPrefix(">") {
            rest = String(text.dropFirst())
            compare = { .greater($0) }
        } else if text.hasPrefix("<") {
            rest = String(text.dropFirst())
            compare = { .less($0) }
        } else {
            compare = { .equal($0) }
        }
        guard let value = Int64(rest), value >= 0 else { return nil }
        return .nameLength(compare(value))
    }

    private func textMatches(haystack: String, needle: String, options: SearchOptions, forcePath: Bool) -> Bool {
        _ = forcePath
        if options.regex {
            var regexOptions: NSRegularExpression.Options = []
            if !options.matchCase { regexOptions.insert(.caseInsensitive) }
            guard let regex = try? NSRegularExpression(pattern: needle, options: regexOptions) else { return false }
            let range = NSRange(haystack.startIndex..., in: haystack)
            return regex.firstMatch(in: haystack, options: [], range: range) != nil
        }
        let term = options.matchCase ? needle : needle.lowercased()
        if options.matchWholeWord {
            return Self.containsWholeWord(haystack, term: term)
        }
        if term.contains("*") || term.contains("?") {
            return Self.wildcardMatch(haystack, pattern: term)
        }
        return haystack.contains(term)
    }

    public static func wildcardMatch(_ text: String, pattern: String) -> Bool {
        let regexPattern = wildcardToRegex(pattern)
        return text.range(of: regexPattern, options: .regularExpression) != nil
    }

    public static func wildcardToRegex(_ pattern: String) -> String {
        var out = "^"
        for ch in pattern {
            switch ch {
            case "*": out += ".*"
            case "?": out += "."
            case ".", "[", "]", "(", ")", "{", "}", "+", "^", "$", "|", "\\":
                out += "\\\(ch)"
            default:
                out.append(ch)
            }
        }
        out += "$"
        return out
    }

    public static func containsWholeWord(_ text: String, term: String) -> Bool {
        guard !term.isEmpty else { return true }
        var searchStart = text.startIndex
        while let range = text.range(of: term, range: searchStart..<text.endIndex) {
            let beforeOK: Bool = {
                if range.lowerBound == text.startIndex { return true }
                let prev = text.index(before: range.lowerBound)
                return !text[prev].isLetter && !text[prev].isNumber
            }()
            let afterOK: Bool = {
                if range.upperBound == text.endIndex { return true }
                return !text[range.upperBound].isLetter && !text[range.upperBound].isNumber
            }()
            if beforeOK && afterOK { return true }
            searchStart = range.upperBound
        }
        return false
    }
}

public extension FileEntry {
    var fileExtension: String {
        let name = self.name
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }
}
