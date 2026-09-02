import Darwin
import Foundation

private final class BulkScratch {
    var buffer = [UInt8](repeating: 0, count: 512 * 1024)
}

private enum WalkScratch {
    private static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { pointer in
            Unmanaged<BulkScratch>.fromOpaque(pointer).release()
        }
        return key
    }()

    static func current() -> BulkScratch {
        if let pointer = pthread_getspecific(key) {
            return Unmanaged<BulkScratch>.fromOpaque(pointer).takeUnretainedValue()
        }
        let scratch = BulkScratch()
        pthread_setspecific(key, Unmanaged.passRetained(scratch).toOpaque())
        return scratch
    }
}

enum FastWalk {
    static func walk(
        root: String,
        rootPath _: String,
        policy: ScanPolicy,
        stop: () -> Bool,
        emit: (IndexFragment) -> Void
    ) {
        emit(packRoot(path: root))
        let fd = open(root, O_RDONLY | O_DIRECTORY)
        walkChildren(
            dirfd: fd,
            path: root,
            relative: "",
            policy: policy,
            depth: 0,
            stop: stop,
            scratch: WalkScratch.current(),
            emit: emit
        )
        if fd >= 0 { close(fd) }
    }

    private static func walkChildren(
        dirfd: Int32,
        path: String,
        relative: String,
        policy: ScanPolicy,
        depth: Int,
        stop: () -> Bool,
        scratch: BulkScratch,
        emit: (IndexFragment) -> Void
    ) {
        if stop() { return }

        var fragment = IndexFragment()
        reserveFragment(&fragment)
        var subdirs: [(path: String, relative: String, name: String)] = []

        func flush() {
            guard fragment.origNamePack.count > 0 else { return }
            emit(fragment)
            fragment = IndexFragment()
            reserveFragment(&fragment)
        }

        func takeName(_ name: String, isDir: Bool, size: Int64 = -1, modified: Int64 = -1, created: Int64 = -1) {
            if name == "." || name == ".." { return }
            if policy.shouldOmitEntry(name: name) { return }
            let childRelative = relative.isEmpty ? name : relative + "/" + name
            let skipDown = policy.shouldSkipDescending(relative: childRelative, name: name)
                || (isDir && isPackageName(name))
            let packed = name.utf8.withContiguousStorageIfAvailable { buf in
                FileIndex.append(
                    directory: path,
                    nameUTF8: buf,
                    isDirectory: isDir,
                    size: size,
                    modified: modified,
                    created: created,
                    into: &fragment
                )
                return true
            }
            if packed != true {
                let bytes = Array(name.utf8)
                bytes.withUnsafeBufferPointer { buf in
                    FileIndex.append(
                        directory: path,
                        nameUTF8: buf,
                        isDirectory: isDir,
                        size: size,
                        modified: modified,
                        created: created,
                        into: &fragment
                    )
                }
            }
            if fragment.origNamePack.count >= 8192 { flush() }
            if isDir, !skipDown {
                subdirs.append((path + "/" + name, childRelative, name))
            }
        }

        func takeBytes(_ nameBytes: UnsafeBufferPointer<UInt8>, isDir: Bool, size: Int64, modified: Int64, created: Int64) {
            if isDotOrDotDot(nameBytes) { return }
            let hidden = nameBytes.count > 0 && nameBytes[0] == 0x2E
            if hidden {
                let name = String(decoding: nameBytes, as: UTF8.self)
                takeName(name, isDir: isDir, size: size, modified: modified, created: created)
                return
            }
            if isDir {
                FileIndex.append(
                    directory: path,
                    nameUTF8: nameBytes,
                    isDirectory: true,
                    size: size,
                    modified: modified,
                    created: created,
                    into: &fragment
                )
                if fragment.origNamePack.count >= 8192 { flush() }
                let name = String(decoding: nameBytes, as: UTF8.self)
                let childRelative = relative.isEmpty ? name : relative + "/" + name
                let skipDown = policy.shouldSkipDescending(relative: childRelative, name: name)
                    || isPackageName(name)
                if !skipDown {
                    subdirs.append((path + "/" + name, childRelative, name))
                }
                return
            }
            FileIndex.append(
                directory: path,
                nameUTF8: nameBytes,
                isDirectory: false,
                size: size,
                modified: modified,
                created: created,
                into: &fragment
            )
            if fragment.origNamePack.count >= 8192 { flush() }
        }

        if dirfd < 0 || !listBulk(fd: dirfd, stop: stop, scratch: scratch, take: takeBytes) {
            listDirent(path: path, stop: stop, take: takeBytes)
        }
        flush()

        guard !subdirs.isEmpty, !stop() else { return }
        if depth < 12, subdirs.count >= 2 {
            DispatchQueue.concurrentPerform(iterations: subdirs.count) { offset in
                if stop() { return }
                descend(
                    subdirs[offset],
                    dirfd: dirfd,
                    policy: policy,
                    depth: depth,
                    stop: stop,
                    emit: emit
                )
            }
        } else {
            for child in subdirs {
                descend(
                    child,
                    dirfd: dirfd,
                    policy: policy,
                    depth: depth,
                    stop: stop,
                    scratch: scratch,
                    emit: emit
                )
            }
        }
    }

    private static func descend(
        _ child: (path: String, relative: String, name: String),
        dirfd: Int32,
        policy: ScanPolicy,
        depth: Int,
        stop: () -> Bool,
        scratch: BulkScratch? = nil,
        emit: (IndexFragment) -> Void
    ) {
        let childFd: Int32
        if dirfd >= 0 {
            childFd = child.name.withCString { openat(dirfd, $0, O_RDONLY | O_DIRECTORY) }
        } else {
            childFd = open(child.path, O_RDONLY | O_DIRECTORY)
        }
        walkChildren(
            dirfd: childFd,
            path: child.path,
            relative: child.relative,
            policy: policy,
            depth: depth + 1,
            stop: stop,
            scratch: scratch ?? WalkScratch.current(),
            emit: emit
        )
        if childFd >= 0 { close(childFd) }
    }

    private static func reserveFragment(_ fragment: inout IndexFragment) {
        fragment.namePack.reserve(1024)
        fragment.pathPack.reserve(1024, bytesHint: 1024 * 80)
        fragment.origNamePack.reserve(1024)
        fragment.origPathPack.reserve(1024, bytesHint: 1024 * 80)
        fragment.dirBits.reserve(1024)
        fragment.sizes.reserveCapacity(1024)
        fragment.modifieds.reserveCapacity(1024)
        fragment.createds.reserveCapacity(1024)
    }

    private static func listBulk(
        fd: Int32,
        stop: () -> Bool,
        scratch: BulkScratch,
        take: (UnsafeBufferPointer<UInt8>, Bool, Int64, Int64, Int64) -> Void
    ) -> Bool {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = Self.cmnReturned | Self.cmnName | Self.cmnObjType | Self.cmnCrTime | Self.cmnModTime
        list.fileattr = Self.fileDataLength

        while !stop() {
            let count = scratch.buffer.withUnsafeMutableBytes { raw -> Int32 in
                guard let base = raw.baseAddress else { return -1 }
                return getattrlistbulk(fd, &list, base, raw.count, 0)
            }
            if count == 0 { return true }
            if count < 0 { return false }
            if !parseBulk(scratch.buffer, count: Int(count), take: take) { return false }
        }
        return true
    }

    private static func parseBulk(_ buffer: [UInt8], count: Int, take: (UnsafeBufferPointer<UInt8>, Bool, Int64, Int64, Int64) -> Void) -> Bool {
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
                let nameBytes = Self.nameBytes(namePtr, length: Int(nameRef.attr_length), recordEnd: record + length)
                field += MemoryLayout<attrreference_t>.stride
                field = align4(field, record: record)

                var isDir = false
                if returnedBits & Self.cmnObjType != 0 {
                    let objType = field.load(as: UInt32.self)
                    isDir = objType == Self.vdir
                    field += MemoryLayout<UInt32>.stride
                    field = align4(field, record: record)
                }
                var created: Int64 = -1
                if returnedBits & Self.cmnCrTime != 0, field + 16 <= record + length {
                    let sec = field.loadUnaligned(as: Int64.self)
                    if sec > 0, sec < 4_000_000_000 { created = sec }
                    field += 16
                    field = align4(field, record: record)
                }
                var modified: Int64 = -1
                if returnedBits & Self.cmnModTime != 0, field + 16 <= record + length {
                    let sec = field.loadUnaligned(as: Int64.self)
                    if sec > 0, sec < 4_000_000_000 { modified = sec }
                    field += 16
                    field = align4(field, record: record)
                }
                var size: Int64 = -1
                if !isDir, returned.fileattr & Self.fileDataLength != 0, field + 8 <= record + length {
                    let value = field.loadUnaligned(as: Int64.self)
                    if value >= 0, value < 1_000_000_000_000 {
                        size = value
                    }
                }
                take(nameBytes, isDir, size, modified, created)
                cursor += length
            }
            return true
        }
    }

    private static func nameBytes(
        _ pointer: UnsafeRawPointer,
        length: Int,
        recordEnd: UnsafeRawPointer
    ) -> UnsafeBufferPointer<UInt8> {
        let chars = pointer.assumingMemoryBound(to: UInt8.self)
        var count = length
        if count > 0, pointer + count > recordEnd {
            count = recordEnd - pointer
        }
        if count > 0, chars[count - 1] == 0 {
            count -= 1
        }
        if count > 0 {
            return UnsafeBufferPointer(start: chars, count: count)
        }
        var n = 0
        while (chars + n).pointee != 0 { n += 1 }
        return UnsafeBufferPointer(start: chars, count: n)
    }

    private static func align4(_ pointer: UnsafeRawPointer, record: UnsafeRawPointer) -> UnsafeRawPointer {
        let offset = pointer - record
        let aligned = (offset + 3) & ~3
        return record + aligned
    }

    private static func listDirent(path: String, stop: () -> Bool, take: (UnsafeBufferPointer<UInt8>, Bool, Int64, Int64, Int64) -> Void) {
        guard let dir = opendir(path) else { return }
        defer { closedir(dir) }
        while let entry = readdir(dir) {
            if stop() { return }
            let namePtr = UnsafeRawPointer(entry).advanced(by: MemoryLayout<dirent>.offset(of: \dirent.d_name) ?? 0)
                .assumingMemoryBound(to: UInt8.self)
            var nameLen = 0
            while (namePtr + nameLen).pointee != 0 { nameLen += 1 }
            let nameBytes = UnsafeBufferPointer(start: namePtr, count: nameLen)
            let kind = entry.pointee.d_type
            if kind == DT_DIR {
                take(nameBytes, true, -1, -1, -1)
            } else if kind == DT_REG || kind == DT_LNK || kind == DT_FIFO || kind == DT_SOCK || kind == DT_CHR || kind == DT_BLK {
                take(nameBytes, false, -1, -1, -1)
            } else {
                let name = String(decoding: nameBytes, as: UTF8.self)
                take(nameBytes, isDirectory(kind: kind, path: path + "/" + name), -1, -1, -1)
            }
        }
    }

    private static func packRoot(path: String) -> IndexFragment {
        let name = (path as NSString).lastPathComponent
        let directory = (path as NSString).deletingLastPathComponent
        return IndexFragment.pack([
            FileEntry(
                name: name.isEmpty ? path : name,
                directory: directory,
                modified: Date(),
                created: Date(),
                isDirectory: true
            )
        ])
    }

    private static func isDotOrDotDot(_ name: UnsafeBufferPointer<UInt8>) -> Bool {
        if name.count == 1, name[0] == 0x2E { return true }
        if name.count == 2, name[0] == 0x2E, name[1] == 0x2E { return true }
        return false
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
    private static let cmnCrTime: UInt32 = 0x0000_0200
    private static let cmnModTime: UInt32 = 0x0000_0400
    private static let fileDataLength: UInt32 = 0x0000_0200
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
