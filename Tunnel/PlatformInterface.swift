import Foundation
import NetworkExtension
import Network
import os.log
import Libbox

public final class PlatformInterface: NSObject, LibboxPlatformInterfaceProtocol {
    private weak var tunnel: NEPacketTunnelProvider?
    private var nwMonitor: NWPathMonitor?

    init(tunnel: NEPacketTunnelProvider) {
        self.tunnel = tunnel
        super.init()
    }

    public func autoDetectControl(_ fd: Int32) throws {
        // No-op
    }

    public func clearDNSCache() {
        // No-op
    }

    public func closeDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        nwMonitor?.cancel()
        nwMonitor = nil
    }

    public func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32, destinationAddress: String?, destinationPort: Int32, ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "PlatformInterface", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    public func getInterfaces() throws -> any LibboxNetworkInterfaceIteratorProtocol {
        guard let monitor = nwMonitor else { return EmptyInterfaceIterator() }
        let path = monitor.currentPath
        guard path.status != .unsatisfied else { return EmptyInterfaceIterator() }

        var list: [LibboxNetworkInterface] = []
        for iface in path.availableInterfaces {
            let item = LibboxNetworkInterface()
            item.name = iface.name
            item.index = Int32(iface.index)
            switch iface.type {
            case .wifi:
                item.type = LibboxInterfaceTypeWIFI
            case .cellular:
                item.type = LibboxInterfaceTypeCellular
            case .wiredEthernet:
                item.type = LibboxInterfaceTypeEthernet
            default:
                item.type = LibboxInterfaceTypeOther
            }
            list.append(item)
        }
        return NetworkInterfaceIterator(list)
    }

    public func includeAllNetworks() -> Bool {
        return false
    }

    public func openTun(_ options: (any LibboxTunOptionsProtocol)?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let tunnel = self.tunnel else {
            throw NSError(domain: "PlatformInterface", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tunnel provider is nil"])
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let reqMtu = options?.getMTU() ?? 0
        let mtu = reqMtu > 0 ? reqMtu : 1500
        settings.mtu = NSNumber(value: mtu)

        // DNS Servers
        var dnsServers = ["1.1.1.1", "8.8.8.8"]
        if let dnsBox = try? options?.getDNSServerAddress(), !dnsBox.value.isEmpty {
            dnsServers = [dnsBox.value]
        }
        let dnsSettings = NEDNSSettings(servers: dnsServers)
        dnsSettings.matchDomains = [""]
        settings.dnsSettings = dnsSettings

        // IPv4 Addresses & Subnets
        var ipv4Addresses: [String] = []
        var ipv4Masks: [String] = []
        if let addrIter = options?.getInet4Address() {
            while addrIter.hasNext() {
                if let prefix = addrIter.next() {
                    ipv4Addresses.append(prefix.address())
                    ipv4Masks.append(prefix.mask())
                }
            }
        }
        if ipv4Addresses.isEmpty {
            ipv4Addresses = ["172.19.0.1"]
            ipv4Masks = ["255.255.255.252"]
        }
        let ipv4Settings = NEIPv4Settings(addresses: ipv4Addresses, subnetMasks: ipv4Masks)

        // IPv4 Included Routes
        var ipv4Routes: [NEIPv4Route] = []
        if let routeIter = options?.getInet4RouteAddress() {
            while routeIter.hasNext() {
                if let prefix = routeIter.next() {
                    ipv4Routes.append(NEIPv4Route(destinationAddress: prefix.address(), subnetMask: prefix.mask()))
                }
            }
        }
        if ipv4Routes.isEmpty {
            ipv4Routes = [NEIPv4Route.default()]
        }
        ipv4Settings.includedRoutes = ipv4Routes

        // IPv4 Excluded Routes (LAN bypass)
        var ipv4ExcludeRoutes: [NEIPv4Route] = [
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0")
        ]
        if let excludeIter = options?.getInet4RouteExcludeAddress() {
            while excludeIter.hasNext() {
                if let prefix = excludeIter.next() {
                    ipv4ExcludeRoutes.append(NEIPv4Route(destinationAddress: prefix.address(), subnetMask: prefix.mask()))
                }
            }
        }
        ipv4Settings.excludedRoutes = ipv4ExcludeRoutes
        settings.ipv4Settings = ipv4Settings

        // Apply tunnel network settings
        let sem = DispatchSemaphore(value: 0)
        var applyError: Error?
        tunnel.setTunnelNetworkSettings(settings) { error in
            applyError = error
            sem.signal()
        }
        sem.wait()

        if let applyError = applyError {
            throw applyError
        }

        // Obtain TUN file descriptor
        if let tunFd = (tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? NSNumber)?.int32Value, tunFd >= 0 {
            ret0_?.pointee = tunFd
            return
        }
        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32, tunFd >= 0 {
            ret0_?.pointee = tunFd
            return
        }
        if let handle = tunnel.packetFlow.value(forKey: "socketFileHandle") as? FileHandle, handle.fileDescriptor >= 0 {
            ret0_?.pointee = handle.fileDescriptor
            return
        }

        let loopFd = LibboxGetTunnelFileDescriptor()
        if loopFd >= 0 {
            ret0_?.pointee = loopFd
            return
        }

        throw NSError(domain: "PlatformInterface", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to acquire TUN file descriptor"])
    }

    public func packageName(byUid uid: Int32, error: NSErrorPointer) -> String {
        return ""
    }

    public func readWIFIState() -> LibboxWIFIState? {
        return nil
    }

    public func send(_ notification: LibboxNotification?) throws {
        // No-op
    }

    public func startDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        guard let listener = listener else { return }
        let monitor = NWPathMonitor()
        self.nwMonitor = monitor
        monitor.pathUpdateHandler = { path in
            guard path.status != .unsatisfied,
                  let defaultInterface = path.availableInterfaces.first else {
                listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
                return
            }
            listener.updateDefaultInterface(
                defaultInterface.name,
                interfaceIndex: Int32(defaultInterface.index),
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained
            )
        }
        monitor.start(queue: DispatchQueue.global(qos: .default))
    }

    public func uid(byPackageName packageName: String?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        ret0_?.pointee = -1
    }

    public func underNetworkExtension() -> Bool {
        return true
    }

    public func usePlatformAutoDetectControl() -> Bool {
        return false
    }

    public func useProcFS() -> Bool {
        return false
    }

    public func writeLog(_ message: String?) {
        if let msg = message {
            NSLog("[Libbox] %@", msg)
        }
    }
}

private final class NetworkInterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    private var items: [LibboxNetworkInterface]
    private var index = 0

    init(_ items: [LibboxNetworkInterface]) {
        self.items = items
    }

    func hasNext() -> Bool {
        return index < items.count
    }

    func next() -> LibboxNetworkInterface? {
        guard index < items.count else { return nil }
        let item = items[index]
        index += 1
        return item
    }
}

private final class EmptyInterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    func hasNext() -> Bool { false }
    func next() -> LibboxNetworkInterface? { nil }
}
