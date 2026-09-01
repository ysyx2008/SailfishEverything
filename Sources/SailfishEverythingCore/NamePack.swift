import Darwin
import Foundation

struct NamePack: Sendable {
    private static let separator: UInt8 = 0xFF

    private(set) var bytes: [UInt8] = []
    private(set) var offsets: [Int] = [0]

    var count: Int { offsets.count - 1 }

    mutating func reset() {
        bytes.removeAll(keepingCapacity: true)
        offsets = [0]
    }

    mutating func reserve(_ names: Int, bytesHint: Int? = nil) {
        offsets.reserveCapacity(names + 1)
        if let bytesHint {
            bytes.reserveCapacity(bytesHint)
        } else {
            bytes.reserveCapacity(names * 24)
        }
    }

    mutating func append(_ nameLower: String) {
        nameLower.utf8.withContiguousStorageIfAvailable { buf in
            bytes.append(contentsOf: buf)
        } ?? bytes.append(contentsOf: Array(nameLower.utf8))
        bytes.append(Self.separator)
        offsets.append(bytes.count)
    }

    mutating func rebuild(_ names: [String]) {
        reset()
        reserve(names.count)
        for name in names {
            append(name)
        }
    }

    func hits(needle: String, candidates: [Int]? = nil) -> [Int] {
        let needleBytes = Array(needle.utf8)
        guard !needleBytes.isEmpty else { return [] }
        if let candidates {
            return scanCandidates(candidates, needle: needleBytes)
        }
        return scanBlob(needle: needleBytes)
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
        hits.reserveCapacity(needle.count <= 2 ? max(count / 8, 64) : 64)
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
}
