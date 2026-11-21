import SwiftUI

struct ServerListView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var searchText = ""
    @State private var isPinging = false

    var filteredServers: [ServerConfig] {
        if searchText.isEmpty {
            return vm.servers
        }
        return vm.servers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.address.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if vm.servers.isEmpty {
                    ContentUnavailableView(
                        "Нет серверов",
                        systemImage: "server.rack",
                        description: Text("Добавьте подписку во вкладке «Подписки» для загрузки узлов.")
                    )
                } else {
                    ForEach(filteredServers) { server in
                        ServerRowView(
                            server: server,
                            isSelected: vm.activeServer?.id == server.id
                        ) {
                            vm.selectServer(server)
                        } onPing: {
                            Task {
                                await vm.testPing(for: server)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                vm.deleteServer(server)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Поиск узла...")
            .navigationTitle("Узлы (\(vm.servers.count))")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPinging = true
                        Task {
                            await vm.testAllPings()
                            isPinging = false
                        }
                    } label: {
                        if isPinging {
                            ProgressView()
                        } else {
                            Image(systemName: "bolt.badge.clock")
                        }
                    }
                }
            }
        }
    }
}

struct ServerRowView: View {
    let server: ServerConfig
    let isSelected: Bool
    let onSelect: () -> Void
    let onPing: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        Text(server.address)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(server.network.uppercased())
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if server.security.lowercased() == "reality" {
                            Text("REALITY")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.15))
                                .foregroundColor(.purple)
                                .cornerRadius(3)
                        }
                    }
                }

                Spacer()

                Button(action: onPing) {
                    if let ping = server.pingMs {
                        Text(ping >= 0 ? "\(ping) ms" : "Error")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(ping >= 0 ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                            .foregroundColor(ping >= 0 ? .green : .red)
                            .cornerRadius(4)
                    } else {
                        Image(systemName: "bolt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.borderless)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
