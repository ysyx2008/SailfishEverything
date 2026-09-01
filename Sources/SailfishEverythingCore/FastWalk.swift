import Darwin
import Foundation

enum FastWalk {
    static func walk(
        root: String,
        rootPath: String,
        policy: ScanPolicy,
        stop: () -> Bool,
        emit: ([FileEntry]) -> Void
    ) {
        let rootLower = root.fastLowercased()
        emit([directoryEntry(path: root, pathLower: rootLower)])
        walkChildren(
            path: root,
            pathLower: rootLower,
            relative: "",
            rootPath: rootPath,
            policy: policy,
            depth: 0,
            stop: stop,
            emit: emit
        )
    }

    private static func walkChildren(
        path: String,
        pathLower: String,
        relative: String,
        rootPath: String,
        policy: ScanPolicy,
        depth: Int,
        stop: () -> Bool,
        emit: ([FileEntry]) -> Void
    ) {
        if stop() { return }

        var local: [FileEntry] = []
        local.reserveCapacity(256)
        var subdirs: [(path: String, pathLower: String, relative: String)] = []

        func flush() {
            guard !local.isEmpty else { return }
            emit(local)
            local.removeAll(keepingCapacity: true)
        }

        func take(_ name: String, isDir: Bool) {
            if name == "." || name == ".." { return }
            if policy.shouldOmitEntry(name: name) { return }
            let nameLower = name.fastLowercased()
            let childRelative = relative.isEmpty ? name : relative + "/" + name
            let childPath = path + "/" + name
            let childPathLower = pathLower + "/" + nameLower
            let skipDown = policy.shouldSkipDescending(relative: childRelative, name: name)
                || (isDir && isPackageName(name))
            local.append(FileEntry(
                name: name,
                nameLower: nameLower,
                directory: path,
                path: childPath,
                pathLower: childPathLower,
                size: nil,
                modified: nil,
                created: nil,
                isDirectory: isDir,
                isCloudOnly: false
            ))
            if local.count >= 512 { flush() }
            if isDir, !skipDown {
                subdirs.append((childPath, childPathLower, childRelative))
            }
        }

        if !listBulk(path: path, stop: stop, take: take) {
            listDirent(path: path, stop: stop, take: take)
        }
        flush()

        guard !subdirs.isEmpty, !stop() else { return }
        if depth < 3, subdirs.count >= 2 {
            DispatchQueue.concurrentPerform(iterations: subdirs.count) { offset in
                if stop() { return }
                let child = subdirs[offset]
                walkChildren(
                    path: child.path,
                    pathLower: child.pathLower,
                    relative: child.relative,
                    rootPath: rootPath,
                    policy: policy,
                    depth: depth + 1,
                    stop: stop,
                    emit: emit
                )
            }
        } else {
            for child in subdirs {
                walkChildren(
                    path: child.path,
                    pathLower: child.pathLower,
                    relative: child.relative,
                    rootPath: rootPath,
                    policy: policy,
                    depth: depth + 1,
                    stop: stop,
                    emit: emit
                )
            }
        }
    }

    private static func listBulk(path: String, stop: () -> Bool, take: (String, Bool) -> Void) -> Bool {
        let fd = open(path, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = Self.cmnReturned | Self.cmnName | Self.cmnObjType

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while !stop() {
            let count = buffer.withUnsafeMutableBytes { raw -> Int32 in
                guard let base = raw.baseAddress else { return -1 }
                return getattrlistbulk(fd, &list, base, raw.count, 0)
            }
            if count == 0 { return true }
            if count < 0 { return false }
            if !parseBulk(buffer, count: Int(count), take: take) { return false }
        }
        return true
    }

    private static func parseBulk(_ buffer: [UInt8], count: Int, take: (String, Bool) -> Void) -> Bool {
        return buffer.withUnsafeBytes { raw in
            guard var cursor = raw.baseAddress else { return false }
            let end = cursor + raw.count
            for _ in 0..<count {
                if cursor + 4 > end { return false }
                let length = Int(cursor.load(as: UInt32.self))
                if length < 8 || cursor + length > end { return false }
                let record = cursor
                var field = cursor + 4
                let returned = field.load(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.stride
                field = align4(field, record: record)

                let returnedBits = returned.commonattr
                guard returnedBits & Self.cmnName != 0 else { return false }
                let nameRef = field.load(as: attrreference_t.self)
                let namePtr = field + Int(nameRef.attr_dataoffset)
                if namePtr < record || namePtr >= record + length { return false }
                let name = String(cString: namePtr.assumingMemoryBound(to: CChar.self))
                field += MemoryLayout<attrreference_t>.stride
                field = align4(field, record: record)

                var isDir = false
                if returnedBits & Self.cmnObjType != 0 {
                    let objType = field.load(as: UInt32.self)
                    isDir = objType == Self.vdir
                }
                take(name, isDir)
                cursor += length
            }
            return true
        }
    }

    private static func align4(_ pointer: UnsafeRawPointer, record: UnsafeRawPointer) -> UnsafeRawPointer {
        let offset = pointer - record
        let aligned = (offset + 3) & ~3
        return record + aligned
    }

    private static func listDirent(path: String, stop: () -> Bool, take: (String, Bool) -> Void) {
        guard let dir = opendir(path) else { return }
        defer { closedir(dir) }
        while let entry = readdir(dir) {
            if stop() { return }
            let name = nameOf(entry)
            let kind = entry.pointee.d_type
            let childPath = path + "/" + name
            take(name, isDirectory(kind: kind, path: childPath))
        }
    }

    private static func directoryEntry(path: String, pathLower: String) -> FileEntry {
        let name = (path as NSString).lastPathComponent
        let directory = (path as NSString).deletingLastPathComponent
        let nameLower = name.fastLowercased()
        return FileEntry(
            name: name.isEmpty ? path : name,
            nameLower: name.isEmpty ? pathLower : nameLower,
            directory: directory,
            path: path,
            pathLower: pathLower,
            size: nil,
            modified: nil,
            created: nil,
            isDirectory: true,
            isCloudOnly: false
        )
    }

    private static func nameOf(_ entry: UnsafeMutablePointer<dirent>) -> String {
        let pointer = UnsafeRawPointer(entry).advanced(by: MemoryLayout<dirent>.offset(of: \dirent.d_name) ?? 0)
        return String(cString: pointer.assumingMemoryBound(to: CChar.self))
    }

    private static func isDirectory(kind: UInt8, path: String) -> Bool {
        if kind == DT_DIR { return true }
        if kind == DT_REG || kind == DT_LNK || kind == DT_FIFO || kind == DT_SOCK { return false }
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFDIR
    }

    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnObjType: UInt32 = 0x0000_0008
    private static let cmnReturned: UInt32 = 0x8000_0000
    private static let vdir: UInt32 = 2
    private static func isPackageName(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        switch name[dot...].lowercased() {
        case ".app", ".bundle", ".framework", ".plugin", ".xpc", ".appex", ".lproj":
            return true
        default:
            return false
        }
    }
}
