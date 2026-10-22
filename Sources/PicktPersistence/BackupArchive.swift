import Foundation
import CryptoKit
#if SWIFT_PACKAGE
import PicktCore
#endif

public struct BackupManifest: Codable, Equatable {
    public var version=1;public var library:StudyLibrary;public var assets:[String:String]
}
public enum BackupArchive {
    public static func export(library: StudyLibrary,assets:AssetStore,to destination:URL) throws -> URL {
        try LibraryCommands.validate(library)
        guard !FileManager.default.fileExists(atPath:destination.path) else { throw LibraryError("备份目标已存在") }
        let temporary=destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString+".partial")
        try FileManager.default.createDirectory(at:temporary.appendingPathComponent("assets"),withIntermediateDirectories:true)
        do {
            var hashes:[String:String]=[:]
            for name in library.referencedAssets {
                let original=try assets.url(for:name)
                let bytes=try checkedData(original,limit:50_000_000)
                hashes[name]=digest(bytes)
                try bytes.write(to:temporary.appendingPathComponent("assets").appendingPathComponent(name),options:.atomic)
            }
            let manifest=BackupManifest(library:library,assets:hashes)
            try JSONEncoder().encode(manifest).write(to:temporary.appendingPathComponent("manifest.json"),options:.atomic)
            try FileManager.default.moveItem(at:temporary,to:destination);return destination
        } catch { try? FileManager.default.removeItem(at:temporary);throw error }
    }
    public static func inspect(_ directory:URL) throws -> BackupManifest {
        let root=directory.standardizedFileURL
        let manifest=try JSONDecoder().decode(BackupManifest.self,from:checkedData(root.appendingPathComponent("manifest.json"),limit:20_000_000))
        guard manifest.version==1,Set(manifest.assets.keys)==manifest.library.referencedAssets else { throw LibraryError("备份版本或图片清单不匹配") }
        try LibraryCommands.validate(manifest.library)
        for (name,expected) in manifest.assets {
            guard AssetName.isValid(name) else { throw LibraryError("备份图片路径不安全") }
            let url=root.appendingPathComponent("assets").appendingPathComponent(name)
            guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path+"/") else { throw LibraryError("备份图片位于资料包外部") }
            guard digest(try checkedData(url,limit:50_000_000))==expected else { throw LibraryError("备份图片缺失或校验失败") }
        }
        return manifest
    }
    public static func installAssets(from directory:URL,manifest:BackupManifest,into assets:AssetStore) throws {
        // Inspection happens before any writes. Immutable names prevent replacing a
        // different existing image. A failed DB restore can leave only orphan files.
        let fresh=try inspect(directory)
        guard fresh==manifest else { throw LibraryError("备份在核对后发生变化，已取消恢复") }
        let root=directory.resolvingSymlinksInPath().standardizedFileURL
        for (name,expected) in fresh.assets {
            let path=directory.appendingPathComponent("assets").appendingPathComponent(name)
            guard path.resolvingSymlinksInPath().path.hasPrefix(root.path+"/") else { throw LibraryError("备份路径在恢复期间变化") }
            let bytes=try checkedData(path,limit:50_000_000)
            guard digest(bytes)==expected else { throw LibraryError("图片在恢复期间变化，已取消恢复") }
            try assets.write(bytes,name:name)
        }
    }
    private static func checkedData(_ url:URL,limit:Int) throws -> Data {
        let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? Int.max)<=limit else { throw LibraryError("文件缺失、过大或类型不安全") }
        return try Data(contentsOf:url)
    }
    private static func digest(_ data:Data) -> String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
}
