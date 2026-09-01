import Darwin
import Foundation

enum FastContains {
    static func contains(_ haystack: String, _ needle: String) -> Bool {
        if needle.isEmpty { return true }
        return haystack.utf8.withContiguousStorageIfAvailable { hay -> Bool in
            needle.utf8.withContiguousStorageIfAvailable { need -> Bool in
                guard let hayPtr = hay.baseAddress, let needPtr = need.baseAddress else {
                    return needle.isEmpty
                }
                if need.count > hay.count { return false }
                return memmem(
                    UnsafeRawPointer(hayPtr),
                    hay.count,
                    UnsafeRawPointer(needPtr),
                    need.count
                ) != nil
            } ?? containsBytes(Array(hay), Array(needle.utf8))
        } ?? containsBytes(Array(haystack.utf8), Array(needle.utf8))
    }

    private static func containsBytes(_ hay: [UInt8], _ need: [UInt8]) -> Bool {
        if need.isEmpty { return true }
        if need.count > hay.count { return false }
        return hay.withUnsafeBufferPointer { hayBuf in
            need.withUnsafeBufferPointer { needBuf in
                guard let hayPtr = hayBuf.baseAddress, let needPtr = needBuf.baseAddress else {
                    return false
                }
                return memmem(hayPtr, hayBuf.count, needPtr, needBuf.count) != nil
            }
        }
    }
}
