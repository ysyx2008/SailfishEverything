import Darwin
import Foundation

struct NamePack: Sendable {
    private static let separator: UInt8 = 0xFF

    private(set) var bytes: [UInt8] = []
    private(set) var offsets: [Int] = [0]
    private(set) var charCounts: [UInt16] = []
    var recordsCharCounts = false
    private var cachedDirectory = "\u{0}"
    private var cachedLower: [UInt8] = []
    private var cachedRaw: [UInt8] = []

    var count: Int { offsets.count - 1 }

    init(recordsCharCounts: Bool = false) {
        self.recordsCharCounts = recordsCharCounts
    }

    mutating func reset() {
        bytes.removeAll(keepingCapacity: true)
        offsets = [0]
        charCounts.removeAll(keepingCapacity: true)
        cachedDirectory = "\u{0}"
        cachedLower.removeAll(keepingCapacity: true)
        cachedRaw.removeAll(keepingCapacity: true)
    }

    mutating func reserve(_ names: Int, bytesHint: Int? = nil) {
        offsets.reserveCapacity(names + 1)
        if recordsCharCounts {
            charCounts.reserveCapacity(names)
        }
        if let bytesHint {
            bytes.reserveCapacity(bytesHint)
        } else {
            bytes.reserveCapacity(names * 24)
        }
    }

    mutating func append(_ nameLower: String) {
        appendLowercasing(nameLower)
    }

    mutating func appendLowercasing(_ raw: String) {
        writeLowercased(raw)
        finishEntry()
    }

    mutating func appendJoined(directory: String, name: String) {
        bytes.append(contentsOf: loweredDirectory(directory))
        if !directory.isEmpty && !directory.hasSuffix("/") {
            bytes.append(0x2F)
        }
        writeLowercased(name)
        finishEntry()
    }

    mutating func appendRaw(_ raw: String) {
        writeRaw(raw)
        finishEntry()
    }

    mutating func appendLowercasing(utf8 buf: UnsafeBufferPointer<UInt8>) {
        writeLowercased(utf8: buf)
        finishEntry()
    }

    mutating func appendRaw(utf8 buf: UnsafeBufferPointer<UInt8>) {
        bytes.append(contentsOf: buf)
        finishEntry()
    }

    mutating func appendJoined(directory: String, nameUTF8: UnsafeBufferPointer<UInt8>, lowercaseName: Bool) {
        if lowercaseName {
            bytes.append(contentsOf: loweredDirectory(directory))
        } else {
            bytes.append(contentsOf: rawDirectory(directory))
        }
        if !directory.isEmpty && !directory.hasSuffix("/") {
            bytes.append(0x2F)
        }
        if lowercaseName {
            writeLowercased(utf8: nameUTF8)
        } else {
            bytes.append(contentsOf: nameUTF8)
        }
        finishEntry()
    }

    mutating func appendJoinedRaw(directory: String, name: String) {
        bytes.append(contentsOf: rawDirectory(directory))
        if !directory.isEmpty && !directory.hasSuffix("/") {
            bytes.append(0x2F)
        }
        writeRaw(name)
        finishEntry()
    }

    func string(at index: Int) -> String? {
        guard index >= 0, index < count else { return nil }
        let start = offsets[index]
        let length = offsets[index + 1] - start - 1
        guard length >= 0, start + length <= bytes.count else { return nil }
        if length == 0 { return "" }
        return bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return "" }
            return String(decoding: UnsafeBufferPointer(start: base + start, count: length), as: UTF8.self)
        }
    }

    private mutating func writeLowercased(_ raw: String) {
        let wrote = raw.utf8.withContiguousStorageIfAvailable { buf -> Bool in
            writeLowercased(utf8: buf)
            return true
        }
        if wrote == true { return }
        let lowered = raw.fastLowercased()
        writeRaw(lowered)
    }

    private mutating func writeLowercased(utf8 buf: UnsafeBufferPointer<UInt8>) {
        for byte in buf where byte >= 128 {
            let raw = String(decoding: buf, as: UTF8.self)
            writeRaw(raw.fastLowercased())
            return
        }
        bytes.reserveCapacity(bytes.count + buf.count + 1)
        for byte in buf {
            bytes.append(byte >= 65 && byte <= 90 ? byte + 32 : byte)
        }
    }

    private mutating func writeRaw(_ raw: String) {
        raw.utf8.withContiguousStorageIfAvailable { buf in
            bytes.append(contentsOf: buf)
        } ?? bytes.append(contentsOf: Array(raw.utf8))
    }

    private mutating func loweredDirectory(_ directory: String) -> [UInt8] {
        refreshDirectoryCache(directory)
        return cachedLower
    }

    private mutating func rawDirectory(_ directory: String) -> [UInt8] {
        refreshDirectoryCache(directory)
        return cachedRaw
    }

    private mutating func refreshDirectoryCache(_ directory: String) {
        if directory == cachedDirectory { return }
        cachedDirectory = directory
        cachedRaw = Array(directory.utf8)
        if cachedRaw.allSatisfy({ $0 < 128 }) {
            cachedLower = cachedRaw.map { byte in
                byte >= 65 && byte <= 90 ? byte + 32 : byte
            }
        } else {
            cachedLower = Array(directory.fastLowercased().utf8)
        }
    }

    private mutating func finishEntry() {
        if recordsCharCounts {
            let start = offsets[offsets.count - 1]
            let nameLen = bytes.count - start
            let chars = bytes.withUnsafeBufferPointer { buf -> Int in
                guard let base = buf.baseAddress, nameLen > 0 else { return 0 }
                return Self.characterCount(base: base, start: start, nameLen: nameLen)
            }
            charCounts.append(UInt16(clamping: chars))
        }
        bytes.append(Self.separator)
        offsets.append(bytes.count)
    }

    mutating func append(contentsOf other: NamePack) {
        guard other.count > 0 else { return }
        let shift = bytes.count
        bytes.append(contentsOf: other.bytes)
        offsets.reserveCapacity(offsets.count + other.count)
        for offset in other.offsets.dropFirst() {
            offsets.append(shift + offset)
        }
        if recordsCharCounts {
            if other.recordsCharCounts, other.charCounts.count == other.count {
                charCounts.append(contentsOf: other.charCounts)
            } else {
                charCounts.append(contentsOf: repeatElement(UInt16(0), count: other.count))
            }
        }
    }

    mutating func rebuild(_ names: [String]) {
        reset()
        reserve(names.count)
        for name in names {
            append(name)
        }
    }

    func compare(_ lhs: Int, _ rhs: Int) -> Int {
        guard lhs >= 0, rhs >= 0, lhs < count, rhs < count else { return lhs - rhs }
        return bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return 0 }
            let aStart = offsets[lhs]
            let aLen = offsets[lhs + 1] - aStart - 1
            let bStart = offsets[rhs]
            let bLen = offsets[rhs + 1] - bStart - 1
            let n = min(aLen, bLen)
            if n > 0 {
                let cmp = memcmp(base + aStart, base + bStart, n)
                if cmp != 0 { return Int(cmp) }
            }
            return aLen - bLen
        }
    }

    func ordered(_ indices: [Int], ties: NamePack? = nil, ascending: Bool) -> [Int] {
        indices.sorted { lhs, rhs in
            let cmp = compare(lhs, rhs)
            if cmp != 0 { return ascending ? cmp < 0 : cmp > 0 }
            if let ties {
                let tied = ties.compare(lhs, rhs)
                if tied != 0 { return tied < 0 }
            }
            return lhs < rhs
        }
    }

    func hits(needle: String, candidates: [Int]? = nil) -> [Int] {
        hits(atom: .contains(needle), candidates: candidates)
    }

    func hits(atom: PackedAtom, candidates: [Int]? = nil, wholeWord: Bool = false, matchCase: Bool = false) -> [Int] {
        switch atom {
        case .files, .folders, .anySuffix, .not, .fileSize, .modified, .created, .emptyFile:
            return candidates ?? []
        case .regexPattern(let pattern):
            guard let regex = Query.makeRegex(pattern, matchCase: matchCase) else { return [] }
            var pool = candidates
            if let hint = PackedAtom.regexLiteralHint(pattern), hint.count >= 2 {
                pool = hits(atom: .contains(hint), candidates: candidates, matchCase: matchCase)
            }
            return scanRegex(regex, candidates: pool)
        case .parentContains(let text):
            return parentContains(text, candidates: candidates, wholeWord: wholeWord, matchCase: matchCase)
        case .parentGlob(let pattern):
            return parentGlob(pattern, candidates: candidates, matchCase: matchCase)
        case .question(let pattern):
            return scanQuestion(pattern, candidates: candidates, matchCase: matchCase)
        case .glob(let pattern), .nameGlob(let pattern), .pathGlob(let pattern):
            return scanGlob(pattern, candidates: candidates, matchCase: matchCase)
        case .nameLength(let pred):
            return scanNameLength(pred, candidates: candidates)
        case .prefixAndSuffix(let pre, let suf):
            let first = hits(atom: .prefix(pre), candidates: candidates, matchCase: matchCase)
            return hits(atom: .suffix(suf), candidates: first, matchCase: matchCase)
        default:
            break
        }

        let needle: String
        let mode: Affix
        switch atom {
        case .contains(let text), .pathContains(let text), .nameContains(let text):
            needle = text
            mode = .contains
        case .prefix(let text):
            needle = text
            mode = .prefix
        case .suffix(let text):
            needle = text
            mode = .suffix
        case .exact(let text):
            needle = text
            mode = .exact
        default:
            return candidates ?? []
        }
        let needleBytes = Array((matchCase ? needle : needle.fastLowercased()).utf8)
        guard !needleBytes.isEmpty else { return [] }
        if wholeWord, mode == .contains {
            if candidates == nil {
                return scanBlobWholeWord(needle: needleBytes)
            }
            return scanContainsWholeWord(candidates, needle: needleBytes)
        }
        if mode == .contains, candidates == nil {
            return scanBlob(needle: needleBytes)
        }
        return scanAffix(candidates, needle: needleBytes, mode: mode)
    }

    private func scanCandidates(_ candidates: [Int], needle: [UInt8]) -> [Int] {
        var hits: [Int] = []
        hits.reserveCapacity(min(candidates.count, 64))
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            needle.withUnsafeBufferPointer { need in
                guard let needBase = need.baseAddress else { return }
                for index in candidates {
                    guard index >= 0, index < count else { continue }
                    let start = offsets[index]
                    let length = offsets[index + 1] - start
                    if need.count > length { continue }
                    if memmem(base + start, length, needBase, need.count) != nil {
                        hits.append(index)
                    }
                }
            }
        }
        return hits
    }

    private func scanBlob(needle: [UInt8]) -> [Int] {
        guard !bytes.isEmpty, count > 0 else { return [] }
        var hits: [Int] = []
        hits.reserveCapacity(needle.count <= 4 ? max(count / 2, 64) : max(64, count / 16))
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            needle.withUnsafeBufferPointer { need in
                guard let needBase = need.baseAddress else { return }
                var cursor = base
                let end = base + buf.count
                var index = 0
                while cursor < end {
                    let remaining = end - cursor
                    guard let raw = memmem(cursor, remaining, needBase, need.count) else { return }
                    let offset = UnsafeRawPointer(raw) - UnsafeRawPointer(base)
                    while index + 1 < offsets.count, offsets[index + 1] <= offset {
                        index += 1
                    }
                    hits.append(index)
                    if index + 1 >= offsets.count { return }
                    cursor = base + offsets[index + 1]
                    index += 1
                }
            }
        }
        return hits
    }

    private enum Affix {
        case contains, prefix, suffix, exact
    }

    private func scanAffix(_ candidates: [Int]?, needle: [UInt8], mode: Affix) -> [Int] {
        let n = needle.count
        var hits: [Int] = []
        let pool = candidates ?? Array(0..<count)
        hits.reserveCapacity(min(pool.count, 64))
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            needle.withUnsafeBufferPointer { need in
                guard let needBase = need.baseAddress else { return }
                for index in pool {
                    guard index >= 0, index < count else { continue }
                    let start = offsets[index]
                    let nameLen = offsets[index + 1] - start - 1
                    let matched: Bool
                    switch mode {
                    case .contains:
                        matched = n <= nameLen && memmem(base + start, nameLen + 1, needBase, n) != nil
                    case .prefix:
                        matched = n <= nameLen && memcmp(base + start, needBase, n) == 0
                    case .suffix:
                        matched = n <= nameLen && memcmp(base + start + nameLen - n, needBase, n) == 0
                    case .exact:
                        matched = n == nameLen && memcmp(base + start, needBase, n) == 0
                    }
                    if matched { hits.append(index) }
                }
            }
        }
        return hits
    }

    func inFolder(_ folder: String, candidates: [Int]? = nil) -> [Int] {
        let folderLower = folder.fastLowercased()
        guard !folderLower.isEmpty else { return candidates ?? Array(0..<count) }
        let childPrefix = folderLower.hasSuffix("/") ? folderLower : folderLower + "/"
        let folderBytes = Array(folderLower.utf8)
        let prefixBytes = Array(childPrefix.utf8)
        var hits: [Int] = []
        let pool = candidates ?? Array(0..<count)
        hits.reserveCapacity(min(pool.count, 64))
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            folderBytes.withUnsafeBufferPointer { folderBuf in
                prefixBytes.withUnsafeBufferPointer { prefixBuf in
                    guard let folderPtr = folderBuf.baseAddress, let prefixPtr = prefixBuf.baseAddress else { return }
                    for index in pool {
                        guard index >= 0, index < count else { continue }
                        let start = offsets[index]
                        let nameLen = offsets[index + 1] - start - 1
                        let isSelf = nameLen == folderBuf.count && memcmp(base + start, folderPtr, folderBuf.count) == 0
                        let isChild = nameLen >= prefixBuf.count && memcmp(base + start, prefixPtr, prefixBuf.count) == 0
                        if isSelf || isChild { hits.append(index) }
                    }
                }
            }
        }
        return hits
    }

    func parentContains(_ needle: String, candidates: [Int]? = nil, wholeWord: Bool = false, matchCase: Bool = false) -> [Int] {
        let needleBytes = Array((matchCase ? needle : needle.fastLowercased()).utf8)
        guard !needleBytes.isEmpty else { return [] }
        var hits: [Int] = []
        let pool = candidates ?? Array(0..<count)
        hits.reserveCapacity(min(pool.count, 64))
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            needleBytes.withUnsafeBufferPointer { need in
                guard let needPtr = need.baseAddress else { return }
                for index in pool {
                    guard index >= 0, index < count else { continue }
                    let start = offsets[index]
                    let end = offsets[index + 1] - 1
                    var lastSlash = -1
                    var prevSlash = -1
                    var i = start
                    while i < end {
                        if (base + i).pointee == 0x2F {
                            prevSlash = lastSlash
                            lastSlash = i
                        }
                        i += 1
                    }
                    guard lastSlash >= start else { continue }
                    let parentStart = prevSlash >= start ? prevSlash + 1 : start
                    let parentLen = lastSlash - parentStart
                    guard need.count <= parentLen else { continue }
                    if wholeWord {
                        if Self.containsWholeWord(
                            base: base,
                            rangeStart: parentStart,
                            rangeEnd: lastSlash,
                            needle: needPtr,
                            needleCount: need.count
                        ) {
                            hits.append(index)
                        }
                    } else if memmem(base + parentStart, parentLen, needPtr, need.count) != nil {
                        hits.append(index)
                    }
                }
            }
        }
        return hits
    }

    func parentGlob(_ pattern: String, candidates: [Int]? = nil, matchCase: Bool = false) -> [Int] {
        let lowered = matchCase ? pattern : pattern.fastLowercased()
        let patBytes = Array(lowered.utf8)
        let patASCII = patBytes.allSatisfy { $0 < 128 }
        var pool = candidates
        if pool == nil, let literal = Self.longestLiteral(patBytes), literal.count >= 2 {
            pool = scanBlob(needle: literal)
        }
        let names = pool ?? Array(0..<count)
        var hits: [Int] = []
        hits.reserveCapacity(min(names.count, 64))
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for index in names {
                guard index >= 0, index < count else { continue }
                let start = offsets[index]
                let end = offsets[index + 1] - 1
                var lastSlash = -1
                var prevSlash = -1
                var i = start
                while i < end {
                    if (base + i).pointee == 0x2F {
                        prevSlash = lastSlash
                        lastSlash = i
                    }
                    i += 1
                }
                guard lastSlash >= start else { continue }
                let parentStart = prevSlash >= start ? prevSlash + 1 : start
                let parentLen = lastSlash - parentStart
                if patASCII, Self.nameIsASCII(base: base, start: parentStart, nameLen: parentLen) {
                    if Self.globASCII(name: base + parentStart, nameLen: parentLen, pat: patBytes) {
                        hits.append(index)
                    }
                } else {
                    let parent = String(
                        decoding: UnsafeBufferPointer(start: base + parentStart, count: parentLen),
                        as: UTF8.self
                    )
                    if Query.wildcardMatch(parent, pattern: lowered) {
                        hits.append(index)
                    }
                }
            }
        }
        return hits
    }

    func scanRegex(_ regex: NSRegularExpression, candidates: [Int]?) -> [Int] {
        let pool = candidates ?? Array(0..<count)
        guard !pool.isEmpty else { return [] }
        if pool.count < 4_096 {
            return scanRegexSerial(regex, pool: pool)
        }
        let workers = min(8, max(2, ProcessInfo.processInfo.activeProcessorCount))
        let chunk = (pool.count + workers - 1) / workers
        let gather = NSLock()
        var parts = Array(repeating: [Int](), count: workers)
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            let start = worker * chunk
            let end = min(pool.count, start + chunk)
            guard start < end else { return }
            let part = scanRegexSerial(regex, pool: Array(pool[start..<end]))
            gather.lock()
            parts[worker] = part
            gather.unlock()
        }
        var hits: [Int] = []
        hits.reserveCapacity(parts.reduce(0) { $0 + $1.count })
        for part in parts {
            hits.append(contentsOf: part)
        }
        return hits
    }

    private func scanRegexSerial(_ regex: NSRegularExpression, pool: [Int]) -> [Int] {
        var hits: [Int] = []
        hits.reserveCapacity(min(pool.count, 64))
        for index in pool {
            guard let text = string(at: index) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                hits.append(index)
            }
        }
        return hits
    }

    private func scanBlobWholeWord(needle: [UInt8]) -> [Int] {
        guard !bytes.isEmpty, count > 0 else { return [] }
        var hits: [Int] = []
        hits.reserveCapacity(64)
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            needle.withUnsafeBufferPointer { need in
                guard let needBase = need.baseAddress else { return }
                var cursor = base
                let end = base + buf.count
                var index = 0
                while cursor < end {
                    let remaining = end - cursor
                    guard let raw = memmem(cursor, remaining, needBase, need.count) else { return }
                    let offset = UnsafeRawPointer(raw) - UnsafeRawPointer(base)
                    while index + 1 < offsets.count, offsets[index + 1] <= offset {
                        index += 1
                    }
                    let nameStart = offsets[index]
                    let nameEnd = offsets[index + 1] - 1
                    if Self.isWholeWord(
                        base: base,
                        nameStart: nameStart,
                        nameEnd: nameEnd,
                        matchStart: offset,
                        matchLen: need.count
                    ) {
                        hits.append(index)
                        if index + 1 >= offsets.count { return }
                        cursor = base + offsets[index + 1]
                        index += 1
                    } else {
                        cursor = base + offset + 1
                    }
                }
            }
        }
        return hits
    }

    private func scanContainsWholeWord(_ candidates: [Int]?, needle: [UInt8]) -> [Int] {
        let pool = candidates ?? Array(0..<count)
        var hits: [Int] = []
        hits.reserveCapacity(min(pool.count, 64))
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            needle.withUnsafeBufferPointer { need in
                guard let needBase = need.baseAddress else { return }
                for index in pool {
                    guard index >= 0, index < count else { continue }
                    let start = offsets[index]
                    let nameEnd = offsets[index + 1] - 1
                    if Self.containsWholeWord(
                        base: base,
                        rangeStart: start,
                        rangeEnd: nameEnd,
                        needle: needBase,
                        needleCount: need.count
                    ) {
                        hits.append(index)
                    }
                }
            }
        }
        return hits
    }

    private func scanGlob(_ pattern: String, candidates: [Int]?, matchCase: Bool = false) -> [Int] {
        let lowered = matchCase ? pattern : pattern.fastLowercased()
        let patBytes = Array(lowered.utf8)
        let patASCII = patBytes.allSatisfy { $0 < 128 }
        var hits: [Int] = []
        var pool = candidates
        if pool == nil, let literal = Self.longestLiteral(patBytes), literal.count >= 2 {
            pool = scanBlob(needle: literal)
        }
        let names = pool ?? Array(0..<count)
        hits.reserveCapacity(min(names.count, 64))
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for index in names {
                guard index >= 0, index < count else { continue }
                let start = offsets[index]
                let nameLen = offsets[index + 1] - start - 1
                if patASCII, Self.nameIsASCII(base: base, start: start, nameLen: nameLen) {
                    if Self.globASCII(name: base + start, nameLen: nameLen, pat: patBytes) {
                        hits.append(index)
                    }
                } else {
                    let name = String(
                        decoding: UnsafeBufferPointer(start: base + start, count: nameLen),
                        as: UTF8.self
                    )
                    if Query.wildcardMatch(name, pattern: lowered) {
                        hits.append(index)
                    }
                }
            }
        }
        return hits
    }

    private static func longestLiteral(_ pat: [UInt8]) -> [UInt8]? {
        var best: [UInt8] = []
        var current: [UInt8] = []
        for byte in pat {
            if byte == 0x2A || byte == 0x3F {
                if current.count > best.count { best = current }
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
        }
        if current.count > best.count { best = current }
        return best.isEmpty ? nil : best
    }

    private static func nameIsASCII(base: UnsafePointer<UInt8>, start: Int, nameLen: Int) -> Bool {
        var i = 0
        while i < nameLen {
            if (base + start + i).pointee >= 128 { return false }
            i += 1
        }
        return true
    }

    private static func globASCII(name: UnsafePointer<UInt8>, nameLen: Int, pat: [UInt8]) -> Bool {
        var n = 0
        var p = 0
        var starN: Int?
        var starP: Int?
        while n < nameLen {
            if p < pat.count, pat[p] == 0x2A {
                starP = p
                starN = n
                p += 1
                continue
            }
            if p < pat.count, pat[p] == 0x3F || pat[p] == (name + n).pointee {
                n += 1
                p += 1
                continue
            }
            if let savedP = starP, let savedN = starN {
                let next = savedN + 1
                starN = next
                p = savedP + 1
                n = next
                continue
            }
            return false
        }
        while p < pat.count, pat[p] == 0x2A { p += 1 }
        return p == pat.count
    }

    private func scanQuestion(_ pattern: String, candidates: [Int]?, matchCase: Bool = false) -> [Int] {
        let lowered = matchCase ? pattern : pattern.fastLowercased()
        let patBytes = Array(lowered.utf8)
        guard !patBytes.isEmpty else { return [] }
        let patASCII = patBytes.allSatisfy { $0 < 128 }
        var hits: [Int] = []
        var pool = candidates
        if pool == nil, let literal = Self.longestLiteral(patBytes), literal.count >= 2 {
            pool = scanBlob(needle: literal)
        }
        let names = pool ?? Array(0..<count)
        hits.reserveCapacity(min(names.count, 64))
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for index in names {
                guard index >= 0, index < count else { continue }
                let start = offsets[index]
                let nameLen = offsets[index + 1] - start - 1
                var nameASCII = true
                var i = 0
                while i < nameLen {
                    if (base + start + i).pointee >= 128 {
                        nameASCII = false
                        break
                    }
                    i += 1
                }
                if patASCII && nameASCII {
                    guard nameLen == patBytes.count else { continue }
                    var ok = true
                    var j = 0
                    while j < nameLen {
                        let expected = patBytes[j]
                        if expected != 0x3F, expected != (base + start + j).pointee {
                            ok = false
                            break
                        }
                        j += 1
                    }
                    if ok { hits.append(index) }
                } else {
                    let name = String(
                        decoding: UnsafeBufferPointer(start: base + start, count: nameLen),
                        as: UTF8.self
                    )
                    if Query.wildcardMatch(name, pattern: lowered) {
                        hits.append(index)
                    }
                }
            }
        }
        return hits
    }

    private func scanNameLength(_ pred: SizeCompare, candidates: [Int]?) -> [Int] {
        var hits: [Int] = []
        func keep(_ index: Int) {
            guard index >= 0, index < charCounts.count else { return }
            let count = Int64(charCounts[index])
            let matched: Bool
            switch pred {
            case .greater(let n): matched = count > n
            case .less(let n): matched = count < n
            case .equal(let n): matched = count == n
            }
            if matched { hits.append(index) }
        }
        if let candidates {
            hits.reserveCapacity(candidates.count)
            for index in candidates { keep(index) }
        } else {
            hits.reserveCapacity(charCounts.count)
            for index in charCounts.indices { keep(index) }
        }
        return hits
    }

    private static func characterCount(base: UnsafePointer<UInt8>, start: Int, nameLen: Int) -> Int {
        var i = 0
        while i < nameLen {
            if (base + start + i).pointee >= 128 {
                return String(
                    decoding: UnsafeBufferPointer(start: base + start, count: nameLen),
                    as: UTF8.self
                ).count
            }
            i += 1
        }
        return nameLen
    }

    private static func containsWholeWord(
        base: UnsafePointer<UInt8>,
        rangeStart: Int,
        rangeEnd: Int,
        needle: UnsafePointer<UInt8>,
        needleCount: Int
    ) -> Bool {
        guard needleCount <= rangeEnd - rangeStart else { return false }
        var cursor = base + rangeStart
        let end = base + rangeEnd
        while cursor < end {
            let remaining = end - cursor
            guard remaining >= needleCount else { return false }
            guard let raw = memmem(cursor, remaining, needle, needleCount) else { return false }
            let matchStart = UnsafeRawPointer(raw) - UnsafeRawPointer(base)
            if isWholeWord(
                base: base,
                nameStart: rangeStart,
                nameEnd: rangeEnd,
                matchStart: matchStart,
                matchLen: needleCount
            ) {
                return true
            }
            cursor = base + matchStart + 1
        }
        return false
    }

    private static func isWholeWord(
        base: UnsafePointer<UInt8>,
        nameStart: Int,
        nameEnd: Int,
        matchStart: Int,
        matchLen: Int
    ) -> Bool {
        let matchEnd = matchStart + matchLen
        let beforeOK: Bool
        if matchStart <= nameStart {
            beforeOK = true
        } else {
            var i = matchStart - 1
            while i > nameStart, (base + i).pointee & 0xC0 == 0x80 {
                i -= 1
            }
            beforeOK = !isWordScalar(base: base, at: i, limit: matchStart)
        }
        let afterOK: Bool
        if matchEnd >= nameEnd {
            afterOK = true
        } else {
            afterOK = !isWordScalar(base: base, at: matchEnd, limit: nameEnd)
        }
        return beforeOK && afterOK
    }

    private static func isWordScalar(base: UnsafePointer<UInt8>, at i: Int, limit: Int) -> Bool {
        guard let scalar = decodeScalar(base: base, at: i, limit: limit) else { return false }
        return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }

    private static func decodeScalar(base: UnsafePointer<UInt8>, at i: Int, limit: Int) -> UnicodeScalar? {
        guard i < limit else { return nil }
        let b0 = UInt32((base + i).pointee)
        if b0 < 0x80 {
            return UnicodeScalar(b0)
        }
        if b0 & 0xE0 == 0xC0, i + 1 < limit {
            let b1 = UInt32((base + i + 1).pointee)
            return UnicodeScalar(((b0 & 0x1F) << 6) | (b1 & 0x3F))
        }
        if b0 & 0xF0 == 0xE0, i + 2 < limit {
            let b1 = UInt32((base + i + 1).pointee)
            let b2 = UInt32((base + i + 2).pointee)
            return UnicodeScalar(((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F))
        }
        if b0 & 0xF8 == 0xF0, i + 3 < limit {
            let b1 = UInt32((base + i + 1).pointee)
            let b2 = UInt32((base + i + 2).pointee)
            let b3 = UInt32((base + i + 3).pointee)
            return UnicodeScalar(((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F))
        }
        return nil
    }
}
