import Foundation

struct NamePostings: Sendable {
    private var uni: [UInt32: [Int]] = [:]
    private var tri: [UInt64: [Int]] = [:]
    var isReady = false

    mutating func reset() {
        uni.removeAll(keepingCapacity: true)
        tri.removeAll(keepingCapacity: true)
        isReady = false
    }

    mutating func markDirty() {
        uni.removeAll(keepingCapacity: true)
        tri.removeAll(keepingCapacity: true)
        isReady = false
    }

    mutating func insert(_ nameLower: String, _ index: Int) {
        let scalars = Array(nameLower.unicodeScalars.map(\.value))
        guard !scalars.isEmpty else { return }
        var seen = Set<UInt64>()
        seen.reserveCapacity(min(scalars.count * 2, 64))
        for scalar in scalars {
            let key = UInt64(scalar)
            if seen.insert(key).inserted {
                uni[scalar, default: []].append(index)
            }
        }
        if scalars.count >= 3 {
            for i in 0..<(scalars.count - 2) {
                let key = Self.triKey(scalars[i], scalars[i + 1], scalars[i + 2])
                if seen.insert(key).inserted {
                    tri[key, default: []].append(index)
                }
            }
        }
    }

    mutating func rebuild(_ entries: [FileEntry]) {
        reset()
        uni.reserveCapacity(min(entries.count, 4096))
        tri.reserveCapacity(min(entries.count, 8192))
        for (index, entry) in entries.enumerated() {
            insert(entry.nameLower, index)
        }
        isReady = true
    }

    func candidates(for termLower: String, limit: Int) -> [Int]? {
        let scalars = Array(termLower.unicodeScalars.map(\.value))
        guard !scalars.isEmpty else { return nil }

        let list: [Int]
        if scalars.count >= 3 {
            var best: [Int]?
            for i in 0..<(scalars.count - 2) {
                let next = tri[Self.triKey(scalars[i], scalars[i + 1], scalars[i + 2])] ?? []
                if best == nil || next.count < best!.count {
                    best = next
                }
            }
            list = best ?? []
        } else if scalars.count == 2 {
            let a = uni[scalars[0]] ?? []
            let b = uni[scalars[1]] ?? []
            list = a.count <= b.count ? a : b
        } else {
            list = uni[scalars[0]] ?? []
        }

        if list.count > limit { return nil }
        return list
    }

    private static func triKey(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603_7
        hash ^= UInt64(a)
        hash &*= 1_099_511_628_211
        hash ^= UInt64(b)
        hash &*= 1_099_511_628_211
        hash ^= UInt64(c)
        hash &*= 1_099_511_628_211
        return hash
    }
}
