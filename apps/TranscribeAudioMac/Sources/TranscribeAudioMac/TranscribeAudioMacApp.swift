import SwiftUI

@main
struct TranscribeAudioMacApp: App {
    @StateObject private var store = TranscribeStore()

    var body: some Scene {
        WindowGroup("Transcribe Audio") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 760)
                .task {
                    store.reload()
                }
        }
        .defaultSize(width: 1480, height: 920)
    }
}
