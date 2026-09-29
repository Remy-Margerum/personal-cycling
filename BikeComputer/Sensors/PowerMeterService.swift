import CoreBluetooth
import Foundation
import Observation
import RideKit

/// Connects to a Bluetooth Cycling Power meter (Favero Assioma) and publishes
/// power, cadence (from crank revolution data), L/R balance and battery.
///
/// Assioma pedals only advertise while awake: spin the cranks before scanning.
/// The chosen meter is remembered and reconnected automatically, including
/// after it drops out mid-ride (CoreBluetooth connect requests never time out).
@Observable
final class PowerMeterService: NSObject {
    enum ConnectionState: Equatable { case poweredOff, idle, scanning, connecting, connected }

    struct Discovered: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    private(set) var state: ConnectionState = .poweredOff
    private(set) var discovered: [Discovered] = []
    private(set) var connectedName: String?

    private(set) var power: Int?
    private(set) var cadence: Double?
    /// Percentage from the reference pedal (left on Assioma Duo).
    private(set) var balance: Double?
    private(set) var batteryLevel: Int?
    private(set) var lastMeasurementAt: Date?

    /// 3-second average power, the usual dashboard number.
    var power3s: Double? { powerAverage.average }

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var seen: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var cadenceCalculator = CadenceCalculator()
    private var powerAverage = RollingAverage(window: 3)

    private static let savedPeripheralKey = "PowerMeterService.peripheralID"
    private let powerService = CBUUID(string: BluetoothUUIDs.cyclingPowerService)
    private let powerMeasurement = CBUUID(string: BluetoothUUIDs.cyclingPowerMeasurement)
    private let batteryService = CBUUID(string: BluetoothUUIDs.batteryService)
    private let batteryLevelChar = CBUUID(string: BluetoothUUIDs.batteryLevel)

    override init() {
        super.init()
        // Main queue: delegate callbacks update UI-observed state directly.
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var savedPeripheralID: UUID? {
        UserDefaults.standard.string(forKey: Self.savedPeripheralKey).flatMap(UUID.init(uuidString:))
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        discovered = []
        state = .scanning
        DebugLog.shared.log(.power, "scan started")
        central.scanForPeripherals(withServices: [powerService])
    }

    func stopScan() {
        central.stopScan()
        if state == .scanning {
            state = .idle
            DebugLog.shared.log(.power, "scan stopped")
        }
    }

    func connect(to id: UUID) {
        guard let target = seen[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else {
            DebugLog.shared.log(.power, "connect: peripheral \(id.uuidString.prefix(8)) not known to CoreBluetooth")
            return
        }
        DebugLog.shared.log(.power, "connecting to \(target.name ?? "unnamed") \(id.uuidString.prefix(8))")
        central.stopScan()
        UserDefaults.standard.set(id.uuidString, forKey: Self.savedPeripheralKey)
        peripheral = target
        target.delegate = self
        state = .connecting
        central.connect(target)
    }

    func forget() {
        DebugLog.shared.log(.power, "forget power meter")
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        UserDefaults.standard.removeObject(forKey: Self.savedPeripheralKey)
        connectedName = nil
        state = .idle
        clearReadings()
    }

    /// Called by the recorder once a second: readings older than a few
    /// seconds mean the pedals stopped sending (coasting or dropout).
    func expireStaleReadings(now: Date) {
        cadenceCalculator.expireIfStale(now: now)
        cadence = cadenceCalculator.cadence
        if let last = lastMeasurementAt, now.timeIntervalSince(last) > 3 {
            let stalePower: Int? = state == .connected ? 0 : nil
            if power != stalePower {
                DebugLog.shared.log(.power, "no packets for \(Int(now.timeIntervalSince(last))) s, power → \(stalePower.map(String.init) ?? "none")")
            }
            power = stalePower
            if state == .connected { powerAverage.add(0, at: now) }
        }
    }

    private func clearReadings() {
        power = nil
        cadence = nil
        balance = nil
        batteryLevel = nil
        lastMeasurementAt = nil
        cadenceCalculator.reset()
        powerAverage = RollingAverage(window: 3)
    }

    private func handle(_ measurement: CyclingPowerMeasurement, at date: Date) {
        lastMeasurementAt = date
        power = max(0, measurement.instantaneousPower)
        powerAverage.add(Double(power ?? 0), at: date)
        balance = measurement.pedalPowerBalance
        if let crank = measurement.crank {
            cadence = cadenceCalculator.update(crank, receivedAt: date)
        }
    }
}

extension PowerMeterService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DebugLog.shared.log(.power, "bluetooth \(central.state.debugName), permission \(CBManager.authorization.debugName)")
        guard central.state == .poweredOn else {
            state = .poweredOff
            return
        }
        state = .idle
        if let id = savedPeripheralID { connect(to: id) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Power meter"
        if seen[peripheral.identifier] == nil {
            DebugLog.shared.log(.power, "discovered \(name) \(peripheral.identifier.uuidString.prefix(8)) rssi \(RSSI.intValue)")
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
        DebugLog.shared.log(.power, "connected \(peripheral.name ?? "unnamed")")
        state = .connected
        connectedName = peripheral.name
        peripheral.discoverServices([powerService, batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        DebugLog.shared.log(.power, "failed to connect: \(error?.localizedDescription ?? "no error"); retrying")
        state = .connecting
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DebugLog.shared.log(.power, "disconnected: \(error?.localizedDescription ?? "no error")")
        clearReadings()
        // Keep a pending connection open so the meter reattaches when it
        // wakes or comes back into range, unless the user chose "Forget".
        guard savedPeripheralID == peripheral.identifier else { return }
        state = .connecting
        central.connect(peripheral)
    }
}

extension PowerMeterService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let uuids = (peripheral.services ?? []).map(\.uuid.uuidString).joined(separator: ", ")
        DebugLog.shared.log(.power, "services [\(uuids)]\(error.map { " error: \($0.localizedDescription)" } ?? "")")
        for service in peripheral.services ?? [] {
            switch service.uuid {
            case powerService: peripheral.discoverCharacteristics([powerMeasurement], for: service)
            case batteryService: peripheral.discoverCharacteristics([batteryLevelChar], for: service)
            default: break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let found = (service.characteristics ?? [])
            .map { "\($0.uuid.uuidString) props=0x\(String($0.properties.rawValue, radix: 16))" }
            .joined(separator: ", ")
        DebugLog.shared.log(.power, "service \(service.uuid.uuidString) characteristics [\(found)]\(error.map { " error: \($0.localizedDescription)" } ?? "")")
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case powerMeasurement:
                peripheral.setNotifyValue(true, for: characteristic)
            case batteryLevelChar:
                peripheral.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            default: break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            DebugLog.shared.log(.power, "value error for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
        }
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        switch characteristic.uuid {
        case powerMeasurement:
            if let measurement = CyclingPowerMeasurement(data: bytes) {
                handle(measurement, at: Date())
                DebugLog.shared.log(.power, "\(DebugFormat.hex(bytes)) → \(DebugFormat.describe(measurement)) cadence=\(DebugFormat.fixed(cadence, 1))")
            } else {
                DebugLog.shared.log(.power, "\(DebugFormat.hex(bytes)) → unparseable (shorter than its flags declare)")
            }
        case batteryLevelChar:
            batteryLevel = parseBatteryLevel(bytes)
            DebugLog.shared.log(.power, "battery \(DebugFormat.hex(bytes)) → \(batteryLevel.map { "\($0)%" } ?? "invalid")")
        default: break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        DebugLog.shared.log(.power, "notify \(characteristic.isNotifying ? "on" : "off") for \(characteristic.uuid.uuidString)\(error.map { " error: \($0.localizedDescription)" } ?? "")")
    }
}

private extension CBManagerState {
    var debugName: String {
        switch self {
        case .poweredOn: "on"
        case .poweredOff: "off"
        case .unauthorized: "unauthorized"
        case .unsupported: "unsupported"
        case .resetting: "resetting"
        case .unknown: "unknown"
        @unknown default: "state \(rawValue)"
        }
    }
}

private extension CBManagerAuthorization {
    var debugName: String {
        switch self {
        case .allowedAlways: "allowed"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not asked yet"
        @unknown default: "authorization \(rawValue)"
        }
    }
}
