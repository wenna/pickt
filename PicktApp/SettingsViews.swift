import SwiftUI
import UniformTypeIdentifiers

struct SettingsView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    @State private var share:SharedFile?
    @State private var importing=false
    @State private var restoreURL:URL?
    @State private var confirm=false
    @State private var working=false
    var body:some View{NavigationView{List{
        Section("资料管理"){NavigationLink("最近删除（可恢复）"){TrashView()};NavigationLink("来源试卷"){List(store.library.sources){source in NavigationLink(source.title){SourceDetail(source:source)}}.navigationTitle("来源试卷")}}
        Section("备份与恢复"){Button(working ? "处理中…":"导出完整备份"){working=true;Task{if let url=await store.exportBackup(){share=SharedFile(url:url)};working=false}}.disabled(working);Button("从文件恢复备份"){importing=true}.disabled(working);NavigationLink("恢复前安全备份"){SafetyBackupsView()};Text("备份包含原图与练习记录。请存到文件 App 或电脑。恢复前会在 App 内保留一份当前资料安全备份。").font(.footnote)}
        Section("识别说明"){Text("使用苹果系统本地文字识别。知识点为可修改的关键词建议。复杂公式、手写步骤与解答题需人工核对。当前不接入大模型服务，无 API 费用。").font(.footnote)}
        Section{Text("拾题 0.1 · iOS 15.5+");Text("侧载刷新时请覆盖安装，勿先卸载。卸载前务必导出备份。").font(.footnote)}
    }.navigationTitle("家长设置").toolbar{Button("完成"){dismiss()}}}.navigationViewStyle(.stack).sheet(item:$share){ShareSheet(url:$0.url)}.fileImporter(isPresented:$importing,allowedContentTypes:[UTType(filenameExtension:"picktbackup") ?? .package]){result in switch result{case .success(let url):restoreURL=url;confirm=true;case .failure(let error):store.error=error.localizedDescription}}.alert("使用备份替换当前资料？",isPresented:$confirm){Button("取消",role:.cancel){};Button("校验并恢复",role:.destructive){if let url=restoreURL{working=true;Task{_ = await store.restoreBackup(url);working=false}}}}message:{Text("先校验全部图片与格式，再保留当前安全备份。任一步失败会停止替换。")}}
}
struct SafetyBackupsView:View {
    @EnvironmentObject var store:AppStore
    @State private var urls:[URL]=[]
    @State private var share:SharedFile?
    @State private var candidate:URL?
    @State private var confirm=false
    var body:some View{List{if urls.isEmpty{Text("暂无恢复前备份")};ForEach(urls,id:\.self){url in VStack(alignment:.leading){Text((try? url.resourceValues(forKeys:[.creationDateKey]).creationDate)?.formatted() ?? url.lastPathComponent).font(.caption);HStack{Button("导出"){share=SharedFile(url:url)}.buttonStyle(.bordered);Button("恢复此备份"){candidate=url;confirm=true}.buttonStyle(.bordered)}}}}.navigationTitle("恢复前安全备份").onAppear{if let root=store.assets?.root.deletingLastPathComponent(){urls=((try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.creationDateKey])) ?? []).filter{$0.lastPathComponent.hasPrefix("BeforeRestore-") && $0.pathExtension=="picktbackup"}.sorted{$0.lastPathComponent<$1.lastPathComponent}}}.sheet(item:$share){ShareSheet(url:$0.url)}.alert("恢复此安全备份？",isPresented:$confirm){Button("取消",role:.cancel){};Button("校验并恢复",role:.destructive){if let url=candidate{Task{_ = await store.restoreBackup(url)}}}}message:{Text("会先保留当前资料安全备份，再替换资料库。")}}
}
struct TrashView:View {
    @EnvironmentObject var store:AppStore
    var body:some View{List{Section("错题"){ForEach(store.library.questions.filter{$0.deletedAt != nil}){q in NavigationLink{QuestionDetail(id:q.id)}label:{Text(q.text.isEmpty ? "图片题目":String(q.text.prefix(60)))}}};Section("练习卷"){ForEach(store.library.papers.filter{$0.deletedAt != nil}){p in NavigationLink(p.title){PaperDetail(id:p.id)}}};Text("只软删除，不自动清理。打开详情可恢复。").font(.footnote).foregroundColor(.secondary)}.navigationTitle("最近删除")}
}
