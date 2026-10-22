import SwiftUI
import UIKit

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var library=StudyLibrary()
    @Published var error: String?
    @Published private(set) var ready=false
    @Published private(set) var busy=false
    let assets: AssetStore?
    private var service: LibraryService?
    private var revision = -1
    init() {
        do {
            let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Pickt",isDirectory:true)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let newAssets=try AssetStore(root:root.appendingPathComponent("Images",isDirectory:true))
            let newService=try LibraryService(repository:CoreDataRepository(url:root.appendingPathComponent("Library.sqlite")))
            assets=newAssets;service=newService
        } catch { assets=nil;self.error="资料载入失败，原文件已保留。\n"+error.localizedDescription }
        if let service=service { Task { let (value,version)=await service.snapshot();library=value;revision=version;ready=true } }
    }
    @discardableResult func change(_ mutation:@escaping (inout StudyLibrary)throws->Void) async -> Bool {
        guard !busy else { error="正在保存，请稍候";return false }
        guard let service=service,ready else { error="资料库尚未就绪，不能保存";return false }
        busy=true;defer { busy=false }
        do { let (value,version)=try await service.transact(mutation);if version>=revision { library=value;revision=version };return true }
        catch { self.error=error.localizedDescription;return false }
    }
    func saveImage(_ image:UIImage) throws -> String {
        guard let assets=assets,let bytes=image.jpegData(compressionQuality:0.9) else { throw LibraryError("无法保存图片") }
        let name=UUID().uuidString+".jpg";try assets.write(bytes,name:name);return name
    }
    func imageURL(_ name:String) -> URL? { try? assets?.url(for:name) }
    func exportBackup() async -> URL? {
        guard let assets=assets,let service=service else { return nil }
        let (snapshot,_)=await service.snapshot()
        do {
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("拾题备份-"+UUID().uuidString.prefix(8)+".picktbackup")
            return try await Task.detached { try BackupArchive.export(library:snapshot,assets:assets,to:url) }.value
        } catch { self.error=error.localizedDescription;return nil }
    }
    func restoreBackup(_ url:URL) async -> Bool {
        guard let service=service,let assets=assets else { return false }
        guard !busy else { error="请等待当前保存完成";return false }
        busy=true;defer{busy=false}
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        do {
            let manifest=try await Task.detached { try BackupArchive.inspect(url) }.value
            // A failed validation cannot alter either the current database or files.
            let (old,_)=await service.snapshot()
            let safety=assets.root.deletingLastPathComponent().appendingPathComponent("BeforeRestore-"+UUID().uuidString+".picktbackup")
            _ = try await Task.detached{try BackupArchive.export(library:old,assets:assets,to:safety)}.value
            try await Task.detached { try BackupArchive.installAssets(from:url,manifest:manifest,into:assets) }.value
            let (value,version)=try await service.replace(manifest.library);library=value;revision=version;return true
        } catch { self.error=error.localizedDescription;return false }
    }
}

enum Theme {
    static let blue=Color(red:36/255,green:107/255,blue:212/255)
    static let background=Color(red:245/255,green:249/255,blue:1)
}

struct AssetImage: View {
    @EnvironmentObject var store:AppStore
    var name:String
    var body:some View {
        if let url=store.imageURL(name),let image=ThumbnailCache.image(url) { Image(uiImage:image).resizable().scaledToFit() }
        else { Label("图片暂时无法读取，请检查备份",systemImage:"photo").foregroundColor(.secondary).padding() }
    }
}

import ImageIO
enum ThumbnailCache {
    static let cache=NSCache<NSString,UIImage>()
    static func image(_ url:URL) -> UIImage? {
        if let image=cache.object(forKey:url.path as NSString) { return image }
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1400,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        let image=UIImage(cgImage:cg);cache.setObject(image,forKey:url.path as NSString,cost:cg.bytesPerRow*cg.height);cache.totalCostLimit=35_000_000;return image
    }
}
