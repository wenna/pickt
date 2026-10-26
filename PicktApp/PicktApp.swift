import SwiftUI

@main struct PicktApp: App {
    @StateObject private var store=AppStore()
    var body:some Scene { WindowGroup { content.environmentObject(store).tint(Theme.blue) } }
    @ViewBuilder private var content:some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--crop-preview") { CropDebugPreview() } else { RootView() }
        #else
        RootView()
        #endif
    }
}
struct RootView: View {
    @EnvironmentObject var store:AppStore
    @State private var selection=0
    var body:some View {
        Group {
            if store.ready {
                TabView(selection:$selection) {
                    LibraryView().tabItem { Label("错题本",systemImage:"books.vertical") }.tag(0)
                    CaptureHome { selection=0 }.tabItem { Label("拍试卷",systemImage:"camera.viewfinder") }.tag(1)
                    PracticeView().tabItem { Label("练一练",systemImage:"doc.text") }.tag(2)
                }
            } else {
                VStack(spacing:20) { Image(systemName:"books.vertical").font(.largeTitle).foregroundColor(Theme.blue);Text(store.error == nil ? "正在打开错题本…" : "资料暂时无法打开").font(.headline);Text(store.error ?? "").font(.footnote);Text("原有资料不会被清空。请保留备份，并反馈错误信息。").font(.footnote).foregroundColor(.secondary) }.padding()
            }
        }.alert("操作未完成",isPresented:Binding(get:{store.error != nil && store.ready},set:{if !$0{store.error=nil}})) { Button("知道了",role:.cancel){} } message:{Text(store.error ?? "")}
    }
}

struct EmptyHint: View {
    var title:String;var detail:String;var icon="tray"
    var body:some View { VStack(spacing:14) { Image(systemName:icon).font(.system(size:40)).foregroundColor(Theme.blue);Text(title).font(.headline);Text(detail).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center) }.frame(maxWidth:.infinity).padding(30) }
}
