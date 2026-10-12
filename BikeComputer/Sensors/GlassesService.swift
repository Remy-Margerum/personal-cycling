import CoreBluetooth
import Foundation
import Observation
import RideKit

/// Shows power, heart rate, speed and cadence on ActiveLook glasses (ENGO 2
/// and others), refreshed once a second, using the layouts built into the
/// glasses (see `GlassesDashboard`).
///
/// Like the power meter, the chosen glasses are remembered and reconnected
/// automatically whenever they're switched on. Glasses accept one connection
/// at a time, so the ENGO app or a head unit must let go of them first.
@Observable
final class GlassesService: NSObject {
    enum ConnectionState: Equatable { case poweredOff, idle, scanning, connecting, connected }

    struct Discovered: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    private(set) var state: ConnectionState = .poweredOff
    private(set) var discovered: [Discovered] = []
    private(set) var connectedName: String?
    private(set) var batteryLevel: Int?
    private(set) var firmware: String?
    /// Set when the glasses can't show the dashboard (e.g. no built-in layouts).
    private(set) var problem: String?

    /// What to show; read once a second while connected.
    @ObservationIgnored var metrics: (() -> GlassesMetrics)?

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var seen: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var ignored: Set<UUID> = []
    @ObservationIgnored private var rx: CBCharacteristic?
    @ObservationIgnored private var queue = ActiveLook.CommandQueue()
    @ObservationIgnored private var reader = ActiveLook.ResponseReader()
    @ObservationIgnored private var flowPaused = false
    /// Text last sent to each layout, so unchanged values aren't resent.
    @ObservationIgnored private var shown: [UInt8: String] = [:]
    @ObservationIgnored private var timer: Timer?

    private static let savedPeripheralKey = "GlassesService.peripheralID"
    private let commandService = CBUUID(string: ActiveLook.commandService)
    private let rxUUID = CBUUID(string: ActiveLook.rxCharacteristic)
    private let txUUID = CBUUID(string: ActiveLook.txCharacteristic)
    private let controlUUID = CBUUID(string: ActiveLook.controlCharacteristic)
    private let touchUUID = CBUUID(string: ActiveLook.touchCharacteristic)
    private let batteryService = CBUUID(string: BluetoothUUIDs.batteryService)
    private let batteryLevelUUID = CBUUID(string: BluetoothUUIDs.batteryLevel)

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var savedPeripheralID: UUID? {
        UserDefaults.standard.string(forKey: Self.savedPeripheralKey).flatMap(UUID.init(uuidString:))
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        discovered = []
        state = .scanning
        DebugLog.shared.log(.glasses, "scan started")
        // No service filter: pairing happens with the app open, and the only
        // service the glasses advertise (FEF5, firmware update) may not be
        // advertised by every model. Glasses are picked out in didDiscover.
        central.scanForPeripherals(withServices: nil)
    }

    func stopScan() {
        central.stopScan()
        if state == .scanning {
            state = .idle
            DebugLog.shared.log(.glasses, "scan stopped")
        }
    }

    func connect(to id: UUID) {
        guard let target = seen[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else {
            DebugLog.shared.log(.glasses, "connect: glasses \(id.uuidString.prefix(8)) not known to CoreBluetooth")
            return
        }
        DebugLog.shared.log(.glasses, "connecting to \(target.name ?? "unnamed") \(id.uuidString.prefix(8))")
        central.stopScan()
        UserDefaults.standard.set(id.uuidString, forKey: Self.savedPeripheralKey)
        peripheral = target
        target.delegate = self
        state = .connecting
        central.connect(target)
    }

    func forget() {
        DebugLog.shared.log(.glasses, "forget glasses")
        UserDefaults.standard.removeObject(forKey: Self.savedPeripheralKey)
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        connectedName = nil
        state = .idle
        reset()
    }

    // MARK: Dashboard

    /// Glasses connected and services found: select the built-in layouts,
    /// clear the screen and start the once-a-second refresh.
    private func start() {
        DebugLog.shared.log(.glasses, "ready, max write \(peripheral?.maximumWriteValueLength(for: .withoutResponse) ?? 0) bytes")
        queue.enqueue(.version)
        queue.enqueue(.configurationRead(ActiveLook.defaultConfiguration))
        queue.enqueue(.configurationSet(ActiveLook.defaultConfiguration))
        queue.enqueue(.clear)
        shown = [:]
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        guard let metrics = metrics?() else { return }
        for (field, text) in GlassesDashboard.fields(metrics) where shown[field.layout] != text {
            shown[field.layout] = text
            queue.enqueue(.layoutClearAndDisplay(id: field.layout, x: field.x, y: field.y, text: text),
                          key: "layout-\(field.layout)")
        }
        send()
    }

    /// Writes the next queued chunk, one at a time (write with response, as
    /// ActiveLook recommends), unless the glasses asked us to pause.
    private func send() {
        guard !flowPaused, let peripheral, let rx,
              let chunk = queue.nextWrite(maxLength: peripheral.maximumWriteValueLength(for: .withoutResponse))
        else { return }
        peripheral.writeValue(Data(chunk), for: rx, type: .withResponse)
    }

    private func reset() {
        timer?.invalidate()
        timer = nil
        rx = nil
        queue.removeAll()
        reader = ActiveLook.ResponseReader()
        flowPaused = false
        shown = [:]
        batteryLevel = nil
    }

    private func handle(_ response: ActiveLook.Response) {
        if let version = response.version {
            firmware = version
            DebugLog.shared.log(.glasses, "firmware \(version)")
        } else if let level = response.batteryLevel {
            batteryLevel = level
        } else if let layouts = response.configurationLayoutCount {
            DebugLog.shared.log(.glasses, "\(ActiveLook.defaultConfiguration) configuration: \(layouts) layouts")
            if layouts == 0 { problem = Self.missingLayouts }
        } else if let error = response.error {
            DebugLog.shared.log(.glasses, "error \(error.code) for command 0x\(String(error.command, radix: 16))")
            if error.command == ActiveLook.Command.configurationSet("").id
                || error.command == ActiveLook.Command.configurationRead("").id {
                problem = Self.missingLayouts
            }
        } else {
            DebugLog.shared.log(.glasses, "response 0x\(String(response.id, radix: 16)) \(DebugFormat.hex(response.data))")
        }
    }

    private static let missingLayouts =
        "These glasses don't have the built-in ActiveLook layouts. Update them in the ENGO or ActiveLook app."
}

extension GlassesService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            state = .poweredOff
            return
        }
        state = .idle
        if let id = savedPeripheralID { connect(to: id) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let manufacturer = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).map { [UInt8]($0) } ?? []
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Glasses"
        // Skipped devices that do advertise ActiveLook's firmware-update
        // service are logged once, in case new glasses advertise differently.
        guard ActiveLook.isActiveLook(manufacturerData: manufacturer, name: name) else {
            let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            if services.contains(CBUUID(string: ActiveLook.advertisedService)),
               ignored.insert(peripheral.identifier).inserted {
                DebugLog.shared.log(.glasses, "skipped \(name): manufacturer data [\(DebugFormat.hex(manufacturer))]")
            }
            return
        }
        if seen[peripheral.identifier] == nil {
            DebugLog.shared.log(.glasses, "discovered \(name) \(peripheral.identifier.uuidString.prefix(8)) rssi \(RSSI.intValue)")
        }
        seen[peripheral.identifier] = peripheral
        let entry = Discovered(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if let index = discovered.firstIndex(where: { $0.id == entry.id }) {
            discovered[index] = entry
        } else {
            discovered.append(entry)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        DebugLog.shared.log(.glasses, "connected \(peripheral.name ?? "unnamed")")
        state = .connected
        connectedName = peripheral.name
        problem = nil
        peripheral.discoverServices([commandService, batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        DebugLog.shared.log(.glasses, "failed to connect: \(error?.localizedDescription ?? "no error"); retrying")
        state = .connecting
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DebugLog.shared.log(.glasses, "disconnected: \(error?.localizedDescription ?? "no error")")
        reset()
        // Wait for the glasses to come back (switched on, back in range),
        // unless the user chose "Forget".
        guard savedPeripheralID == peripheral.identifier else { return }
        state = .connecting
        central.connect(peripheral)
    }
}

extension GlassesService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let uuids = (peripheral.services ?? []).map(\.uuid.uuidString).joined(separator: ", ")
        DebugLog.shared.log(.glasses, "services [\(uuids)]\(error.map { " error: \($0.localizedDescription)" } ?? "")")
        for service in peripheral.services ?? [] {
            switch service.uuid {
            case commandService:
                peripheral.discoverCharacteristics([rxUUID, txUUID, controlUUID, touchUUID], for: service)
            case batteryService:
                peripheral.discoverCharacteristics([batteryLevelUUID], for: service)
            default: break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case rxUUID:
                rx = characteristic
            case txUUID, controlUUID, touchUUID:
                peripheral.setNotifyValue(true, for: characteristic)
            case batteryLevelUUID:
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            default: break
            }
        }
        if service.uuid == commandService {
            if rx == nil {
                DebugLog.shared.log(.glasses, "no command characteristic found\(error.map { ": \($0.localizedDescription)" } ?? "")")
            } else if timer == nil {
                start()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            DebugLog.shared.log(.glasses, "write failed: \(error.localizedDescription)")
        }
        queue.acknowledged()
        send()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        switch characteristic.uuid {
        case txUUID:
            reader.append(bytes).forEach(handle)
        case controlUUID:
            switch ActiveLook.ControlSignal(bytes) {
            case .pause:
                flowPaused = true
                DebugLog.shared.log(.glasses, "flow control: pause")
            case .resume:
                if flowPaused { DebugLog.shared.log(.glasses, "flow control: resume") }
                flowPaused = false
                send()
            case let .error(code):
                DebugLog.shared.log(.glasses, "control error 0x\(String(code, radix: 16))")
            case nil:
                break
            }
        case touchUUID:
            DebugLog.shared.log(.glasses, "tap")
        case batteryLevelUUID:
            batteryLevel = parseBatteryLevel(bytes)
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            DebugLog.shared.log(.glasses, "notify failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
        }
    }
}
