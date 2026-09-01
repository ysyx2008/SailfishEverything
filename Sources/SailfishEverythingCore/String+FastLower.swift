import Foundation

extension String {
    func fastLowercased() -> String {
        guard let converted = utf8.withContiguousStorageIfAvailable({ buf -> String? in
            var needsLower = false
            for byte in buf {
                if byte >= 128 { return nil }
                if byte >= 65 && byte <= 90 { needsLower = true }
            }
            if !needsLower { return self }
            var out = Array(buf)
            for i in out.indices where out[i] >= 65 && out[i] <= 90 {
                out[i] += 32
            }
            return String(bytes: out, encoding: .utf8)
        }) else {
            return lowercased()
        }
        return converted ?? lowercased()
    }
}
