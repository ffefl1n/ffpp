import SwiftUI

@main
struct ffppApp: App {
    @StateObject private var vm = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .onAppear {
                    if vm.settings.autoConnectOnLaunch {
                        vm.toggleVPN()
                    }
                }
        }
    }
}
