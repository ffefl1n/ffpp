import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject private var vpnManager = VPNManager.shared
    @State private var pulse = false

    var isConnected: Bool {
        vpnManager.status == .connected
    }

    var isConnecting: Bool {
        vpnManager.status == .connecting
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Device & Status Banner
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .scaleEffect(isConnecting ? 1.4 : 1.0)
                        .animation(isConnecting ? Animation.easeInOut(duration: 0.8).repeatForever() : .default, value: isConnecting)

                    Text(vpnManager.status.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(20)
                .padding(.top, 16)

                Spacer()

                // Main Connect Button
                ZStack {
                    Circle()
                        .stroke(statusColor.opacity(0.15), lineWidth: 28)
                        .frame(width: 190, height: 190)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 150, height: 150)
                        .shadow(color: statusColor.opacity(0.4), radius: isConnected ? 20 : 8, x: 0, y: 8)

                    VStack(spacing: 6) {
                        Image(systemName: "power")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.white)

                        Text(isConnected ? "ВКЛ" : "ВЫКЛ")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .onTapGesture {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    vm.toggleVPN()
                }

                Spacer()

                // Active Node Card with Geo Location
                if let server = vm.activeServer {
                    NavigationLink(destination: ServerListView()) {
                        HStack(spacing: 14) {
                            // Location Flag or Server Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 40, height: 40)

                                if let flag = server.flagEmoji, !flag.isEmpty {
                                    Text(flag)
                                        .font(.title2)
                                } else {
                                    Image(systemName: serverIcon(server))
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(server.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .foregroundColor(.primary)

                                    if let country = server.countryName, !country.isEmpty {
                                        Text("• \(country)")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                            .lineLimit(1)
                                    }
                                }

                                Text("\(server.address):\(server.port) • \(protocolBadgeText(server))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if let ping = server.pingMs {
                                Text(ping >= 0 ? "\(ping) ms" : "Timeout")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(ping >= 0 ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                                    .foregroundColor(ping >= 0 ? .green : .red)
                                    .cornerRadius(6)
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                    }
                    .padding(.horizontal)
                } else {
                    NavigationLink(destination: SubscriptionView()) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("Добавьте подписку или узел")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(14)
                        .padding(.horizontal)
                    }
                }

                // Device and Happ HWID Card
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "iphone")
                            .foregroundColor(.blue)
                        Text("Устройство:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(DeviceHelper.modelName) (\(DeviceHelper.modelIdentifier))")
                            .font(.caption2.bold())
                            .foregroundColor(.primary)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.green)
                        Text("Happ HWID:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(vm.hwid.prefix(8) + "...")
                            .font(.caption2.monospaced())
                            .foregroundColor(.primary)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = vm.hwid
                            let gen = UINotificationFeedbackGenerator()
                            gen.notificationOccurred(.success)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .navigationTitle("ffpp")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                vpnManager.updateStatus()
            }
        }
    }

    private func serverIcon(_ server: ServerConfig) -> String {
        let proto = server.protocolType.lowercased()
        if proto.contains("hysteria") || proto.contains("hy2") {
            return "wind"
        }
        return "bolt.horizontal.fill"
    }

    private func protocolBadgeText(_ server: ServerConfig) -> String {
        let proto = server.protocolType.uppercased()
        if proto.contains("HYSTERIA2") || proto == "HY2" {
            return "HYSTERIA 2"
        }
        if proto.contains("HYSTERIA") {
            return "HYSTERIA"
        }
        if server.security.lowercased() == "reality" {
            return "VLESS REALITY"
        }
        return "VLESS"
    }

    private var statusColor: Color {
        switch vpnManager.status {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnecting:
            return .gray
        case .disconnected:
            return .blue
        case .invalid:
            return .red
        }
    }
}
