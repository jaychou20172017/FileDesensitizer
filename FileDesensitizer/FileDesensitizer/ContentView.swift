import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .desensitize

    var body: some View {
        TabView(selection: $selectedTab) {
            DesensitizeView()
                .tabItem {
                    Label("脱敏处理", systemImage: "shield.lefthalf.filled")
                }
                .tag(Tab.desensitize)

            RecoverView()
                .tabItem {
                    Label("数据恢复", systemImage: "arrow.trianglehead.clockwise")
                }
                .tag(Tab.recover)
        }
    }
}

enum Tab {
    case desensitize
    case recover
}
