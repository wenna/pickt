import Foundation
#if SWIFT_PACKAGE
import PicktCore
#endif

public final class AssetStore {
    public let root: URL
    public init(root: URL) throws {
        self.root=root.standardizedFileURL
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    }
    public func url(for name: String) throws -> URL {
        guard AssetName.isValid(name) else { throw LibraryError("图片路径无效") }
        return root.appendingPathComponent(name)
    }
    public func write(_ data:Data,name:String) throws {
        let target=try url(for:name)
        if FileManager.default.fileExists(atPath:target.path) {
            guard try Data(contentsOf:target)==data else { throw LibraryError("图片标识重复，已停止写入") };return
        }
        let temporary=root.appendingPathComponent(UUID().uuidString+".partial")
        defer { try? FileManager.default.removeItem(at:temporary) }
        try data.write(to:temporary,options:.atomic)
        do { try FileManager.default.linkItem(at:temporary,to:target) }
        catch {
            guard FileManager.default.fileExists(atPath:target.path),try Data(contentsOf:target)==data else { throw error }
        }
    }
}
