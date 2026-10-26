#if DEBUG
import SwiftUI

/// Synthetic CI preview only. Never inserts sample questions into the library.
struct CropDebugPreview:View {
    @State private var rect=NormalizedRect(x:0.12,y:0.2,width:0.76,height:0.22)
    private static let page:UIImage = {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:600,height:900),format:format).image{ctx in
            UIColor.white.setFill();ctx.fill(CGRect(x:0,y:0,width:600,height:900))
            let lines=["Demo Math Worksheet", "1. 1/2 + 1/2 = ?", "2. 5 x 3 = ?", "3. 10 - 6 = ?"]
            for (i,line) in lines.enumerated(){(line as NSString).draw(at:CGPoint(x:40,y:45+i*190),withAttributes:[.font:UIFont.systemFont(ofSize:25),.foregroundColor:UIColor.black])}
        }
    }()
    var body:some View {
        NavigationView{VStack(spacing:12){
            Text("拖框内移动，拖圆点调整；框外重画，双指缩放。")
                .font(.footnote).padding(.horizontal)
            CropCanvas(image:Self.page,rect:$rect).background(Color.secondary.opacity(0.08))
            Button("重置选框"){rect=NormalizedRect()}.frame(minHeight:44)
            Text("仅 CI 虚构试卷预览，不写入资料库").font(.caption).foregroundColor(.secondary)
        }.padding().navigationTitle("选框交互预览").navigationBarTitleDisplayMode(.inline)}.navigationViewStyle(.stack)
    }
}
#endif
