import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @State private var showingFileImporter = false
    @State private var showingHWIDEditor = false
    @State private var customHWIDInput = ""

    var body: some View {
        NavigationStack {
            Form {
                // Device & Happ Section
                Section(header: Text("Идентификация Happ"), footer: Text("Этот постоянный HWID хранится в iOS Keychain и никогда не сбрасывается самостоятельно, что исключает ошибки привязки на серверах Happ.")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Аппаратный HWID")
                                .font(.subheadline)
                            Text(vm.hwid)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = vm.hwid
                            let gen = UINotificationFeedbackGenerator()
                            gen.notificationOccurred(.success)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                    }

                    Button("Изменить HWID вручную") {
                        customHWIDInput = vm.hwid
                        showingHWIDEditor = true
                    }
                }

                // Backup & Persistence Section
                Section(header: Text("Сохранность данных"), footer: Text("Все подписки и серверы автоматически дублируются в защищенное хранилище и кэш. Вы также можете сделать ручной бэкап в файл.")) {
                    Button {
                        if let url = vm.exportBackupURL() {
                            exportURL = url
                            showingExportSheet = true
                        }
                    } label: {
                        Label("Экспорт резервной копии (JSON)", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Импорт резервной копии", systemImage: "square.and.arrow.down")
                    }
                }

                // Routing & Core Section
                Section(header: Text("Параметры сети")) {
                    Toggle("Обход локальной сети (Bypass LAN)", isOn: $vm.settings.bypassLAN)
                        .onChange(of: vm.settings.bypassLAN) { _ in
                            vm.saveData()
                        }

                    HStack {
                        Text("Удаленный DNS")
                        Spacer()
                        TextField("DNS", text: $vm.settings.remoteDNS)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                            .onChange(of: vm.settings.remoteDNS) { _ in
                                vm.saveData()
                            }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("MTU туннеля")
                            Spacer()
                            TextField("MTU", value: $vm.settings.mtu, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.secondary)
                                .frame(width: 80)
                                .onChange(of: vm.settings.mtu) { newVal in
                                    if newVal < 576 { vm.settings.mtu = 576 }
                                    if newVal > 9000 { vm.settings.mtu = 9000 }
                                    vm.saveData()
                                }
                        }
                        HStack(spacing: 8) {
                            ForEach([1500, 1420, 1360, 1280], id: \.self) { val in
                                Button("\(val)") {
                                    vm.settings.mtu = val
                                    vm.saveData()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .tint(vm.settings.mtu == val ? .blue : .gray)
                            }
                        }
                    }
                }

                Section(header: Text("О приложении")) {
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text("1.0.3 (Build 4)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Ядро туннеля")
                        Spacer()
                        Text("sing-box 1.11 (Libbox)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Настройки")
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let selected = urls.first {
                        _ = selected.startAccessingSecurityScopedResource()
                        vm.importBackup(from: selected)
                        selected.stopAccessingSecurityScopedResource()
                    }
                case .failure(let error):
                    vm.errorMessage = "Ошибка выбора файла: \(error.localizedDescription)"
                }
            }
            .alert("Ручной ввод HWID", isPresented: $showingHWIDEditor) {
                TextField("Введите UUID", text: $customHWIDInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                Button("Сохранить") {
                    KeychainHelper.shared.setCustomHWID(customHWIDInput)
                    vm.hwid = KeychainHelper.shared.getOrCreateHWID()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Укажите желаемый HWID (формат UUID). Он будет сохранен в Keychain и отправлен при следующих обновлениях подписки.")
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
