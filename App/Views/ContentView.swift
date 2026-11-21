import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Главная", systemImage: "shield.lefthalf.filled")
                }

            ServerListView()
                .tabItem {
                    Label("Серверы", systemImage: "server.rack")
                }

            SubscriptionView()
                .tabItem {
                    Label("Подписки", systemImage: "antenna.radiowaves.left.and.right")
                }

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
        }
        .tint(.blue)
        .alert("Уведомление", isPresented: Binding(
            get: { vm.errorMessage != nil || vm.successMessage != nil },
            set: { _ in
                vm.errorMessage = nil
                vm.successMessage = nil
            }
        )) {
            if let preview = vm.lastServerResponsePreview, !preview.isEmpty {
                Button("Скопировать ответ сервера") {
                    UIPasteboard.general.string = preview
                    let gen = UINotificationFeedbackGenerator()
                    gen.notificationOccurred(.success)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            if let err = vm.errorMessage {
                Text(err)
            } else if let success = vm.successMessage {
                Text(success)
            }
        }
    }
}
