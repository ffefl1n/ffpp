import SwiftUI

struct SubscriptionView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showingAddSheet = false
    @State private var newURL = ""
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if vm.subscriptions.isEmpty {
                    ContentUnavailableView(
                        "Нет подписок",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Нажмите «+», чтобы добавить ссылку подписки (поддерживаются стандартные ссылки и эксклюзивные happ://).")
                    )
                } else {
                    ForEach(vm.subscriptions) { sub in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(sub.name)
                                    .font(.headline)
                                Spacer()
                                Button {
                                    Task {
                                        await vm.refreshSubscription(sub)
                                    }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.borderless)
                            }

                            HStack(spacing: 8) {
                                Label("\(sub.serverCount) узлов", systemImage: "server.rack")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let date = sub.lastUpdated {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(date, style: .time)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text("UA: \(sub.userAgentUsed) | HWID: \(sub.hwidUsed.prefix(8))...")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                vm.deleteSubscription(sub)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Подписки")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                NavigationStack {
                    Form {
                        Section(header: Text("Параметры подписки")) {
                            TextField("Название (необязательно)", text: $newName)

                            TextField("URL (https://... или happ://...)", text: $newURL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Button {
                                if let pasted = UIPasteboard.general.string {
                                    newURL = pasted
                                }
                            } label: {
                                Label("Вставить из буфера", systemImage: "doc.on.clipboard")
                            }
                        }

                        Section(footer: Text("Запрос будет отправлен с официальными заголовками Happ и уникальным постоянным HWID устройства.")) {
                            EmptyView()
                        }
                    }
                    .navigationTitle("Новая подписка")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отмена") {
                                showingAddSheet = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Добавить") {
                                let url = newURL
                                let name = newName
                                showingAddSheet = false
                                newURL = ""
                                newName = ""
                                Task {
                                    await vm.addSubscription(url: url, name: name)
                                }
                            }
                            .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}
