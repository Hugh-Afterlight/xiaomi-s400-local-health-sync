import CoreBluetooth
import Foundation

struct DeviceConfig: Decodable {
    var name_keywords: [String] = ["S400", "MJTZC01YM", "Mijia Scale S400"]
    var addresses: [String] = []
    var service_uuids: [String] = []
    var manufacturer_ids: [String] = []
}

struct ScanConfig: Decodable {
    var duration_seconds: Int = 60
    var record_all: Bool = false
    var min_rssi: Int = -95
    var dedupe_window_seconds: Double = 2.0
}

struct OutputConfig: Decodable {
    var observation_dir: String = "data/ble_observations"
    var summary_dir: String = "data/ble_summaries"
}

struct AppConfig: Decodable {
    var device: DeviceConfig = DeviceConfig()
    var scan: ScanConfig = ScanConfig()
    var output: OutputConfig = OutputConfig()
}

struct RuntimeOptions {
    var configPath = "config.json"
    var duration: Int?
    var outputDir: String?
    var summaryDir: String?
    var label: String?
    var minRSSI: Int?
    var candidatesOnly = false
}

final class DeviceSummary {
    let id: String
    var names = Set<String>()
    var localNames = Set<String>()
    var serviceUUIDs = Set<String>()
    var manufacturerIDs = Set<String>()
    var matchReasons = Set<String>()
    var count = 0
    var candidateCount = 0
    var maxRSSI: Int?
    var firstSeen: String?
    var lastSeen: String?
    var samplePayloads: [[String: Any]] = []

    init(id: String) {
        self.id = id
    }

    func observe(_ event: [String: Any]) {
        count += 1
        if event["candidate"] as? Bool == true {
            candidateCount += 1
        }

        if let device = event["device"] as? [String: Any], let name = device["name"] as? String, !name.isEmpty {
            names.insert(name)
        }

        if let advertisement = event["advertisement"] as? [String: Any] {
            if let localName = advertisement["local_name"] as? String, !localName.isEmpty {
                localNames.insert(localName)
            }
            if let rssi = advertisement["rssi"] as? Int {
                maxRSSI = max(maxRSSI ?? rssi, rssi)
            }
            if let serviceUUIDs = advertisement["service_uuids"] as? [String] {
                self.serviceUUIDs.formUnion(serviceUUIDs)
            }
            if let manufacturerID = advertisement["manufacturer_id"] as? String, !manufacturerID.isEmpty {
                manufacturerIDs.insert(manufacturerID)
            }
        }

        if let reasons = event["match_reasons"] as? [String] {
            matchReasons.formUnion(reasons)
        }

        let seenAt = event["seen_at_utc"] as? String
        if firstSeen == nil {
            firstSeen = seenAt
        }
        lastSeen = seenAt

        if samplePayloads.count < 3 {
            samplePayloads.append([
                "seen_at_utc": seenAt ?? "",
                "advertisement": event["advertisement"] ?? [:],
                "match_reasons": event["match_reasons"] ?? [],
            ])
        }
    }

    func jsonObject() -> [String: Any] {
        [
            "id": id,
            "names": Array(names).sorted(),
            "local_names": Array(localNames).sorted(),
            "manufacturer_ids": Array(manufacturerIDs).sorted(),
            "service_uuids": Array(serviceUUIDs).sorted(),
            "count": count,
            "candidate_count": candidateCount,
            "max_rssi": maxRSSI as Any,
            "first_seen": firstSeen as Any,
            "last_seen": lastSeen as Any,
            "match_reasons": Array(matchReasons).sorted(),
            "sample_payloads": samplePayloads,
        ]
    }
}

final class Scanner: NSObject, CBCentralManagerDelegate {
    private let config: AppConfig
    private let options: RuntimeOptions
    private let observationPath: URL
    private let summaryPath: URL
    private let observationHandle: FileHandle
    private var manager: CBCentralManager!
    private var summaries: [String: DeviceSummary] = [:]
    private var recentFingerprints: [String: Date] = [:]
    private var counters: [String: Int] = [:]
    private let startedAt = Date()

    init(config: AppConfig, options: RuntimeOptions, observationPath: URL, summaryPath: URL) throws {
        self.config = config
        self.options = options
        self.observationPath = observationPath
        self.summaryPath = summaryPath
        FileManager.default.createFile(atPath: observationPath.path, contents: nil)
        self.observationHandle = try FileHandle(forWritingTo: observationPath)
        super.init()
    }

    deinit {
        try? observationHandle.close()
    }

    func start() {
        manager = CBCentralManager(delegate: self, queue: .main)
        print("Scanning BLE advertisements for \(durationSeconds()) seconds...")
        print("Writing raw observations to: \(observationPath.path)")
        print("Tip: step on the S400 during this window.")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            Timer.scheduledTimer(withTimeInterval: TimeInterval(durationSeconds()), repeats: false) { [weak self] _ in
                self?.finish(exitCode: 0)
            }
        case .unauthorized:
            fputs("Bluetooth permission is not authorized. Allow this scanner in System Settings > Privacy & Security > Bluetooth.\n", stderr)
            finish(exitCode: 3)
        case .unsupported:
            fputs("Bluetooth is not supported on this Mac.\n", stderr)
            finish(exitCode: 4)
        case .poweredOff:
            fputs("Bluetooth is powered off. Turn Bluetooth on and retry.\n", stderr)
            finish(exitCode: 5)
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        increment("seen")
        let event = buildEvent(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI.intValue)

        if let minRSSI = options.minRSSI ?? Optional(config.scan.min_rssi), RSSI.intValue < minRSSI {
            increment("ignored_low_rssi")
            return
        }

        let recordAll = options.candidatesOnly ? false : config.scan.record_all
        if !recordAll && (event["candidate"] as? Bool != true) {
            increment("ignored_non_candidate")
            return
        }

        let fingerprint = eventFingerprint(event)
        if let previous = recentFingerprints[fingerprint], Date().timeIntervalSince(previous) < config.scan.dedupe_window_seconds {
            increment("ignored_duplicate")
            return
        }
        recentFingerprints[fingerprint] = Date()

        writeJSONLine(event)
        let id = (event["device"] as? [String: Any])?["id"] as? String ?? "unknown"
        let summary = summaries[id] ?? DeviceSummary(id: id)
        summary.observe(event)
        summaries[id] = summary

        increment("recorded")
        if event["candidate"] as? Bool == true {
            increment("candidates")
        }
    }

    private func buildEvent(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: Int) -> [String: Any] {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map { $0.uuidString.lowercased() }
            .sorted()
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
        let serviceDataJSON = Dictionary(
            uniqueKeysWithValues: serviceData.map { ($0.key.uuidString.lowercased(), $0.value.hexString) }
        )
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let manufacturerHex = manufacturerData?.hexString ?? ""
        let manufacturerID = manufacturerData.flatMap { parseManufacturerID(from: $0) }

        var matchReasons: [String] = []
        let searchableName = [peripheral.name, localName].compactMap { $0 }.joined(separator: " ").lowercased()
        for keyword in config.device.name_keywords where searchableName.contains(keyword.lowercased()) {
            matchReasons.append("name contains \(keyword.lowercased())")
        }
        if config.device.addresses.map({ $0.lowercased() }).contains(peripheral.identifier.uuidString.lowercased()) {
            matchReasons.append("identifier configured")
        }
        if !Set(config.device.service_uuids.map { $0.lowercased() }).intersection(serviceUUIDs).isEmpty {
            matchReasons.append("service uuid configured")
        }
        if let manufacturerID, config.device.manufacturer_ids.map({ $0.lowercased() }).contains(manufacturerID.lowercased()) {
            matchReasons.append("manufacturer id configured")
        }

        let now = Date()
        return [
            "seen_at_utc": ISO8601DateFormatter.utc.string(from: now),
            "seen_at_local": ISO8601DateFormatter.local.string(from: now),
            "candidate": !matchReasons.isEmpty,
            "match_reasons": matchReasons,
            "device": [
                "id": peripheral.identifier.uuidString,
                "name": peripheral.name as Any,
            ],
            "advertisement": [
                "local_name": localName as Any,
                "rssi": rssi,
                "service_uuids": serviceUUIDs,
                "service_data": serviceDataJSON,
                "manufacturer_id": manufacturerID as Any,
                "manufacturer_data": manufacturerHex,
                "tx_power": advertisementData[CBAdvertisementDataTxPowerLevelKey] as Any,
                "is_connectable": advertisementData[CBAdvertisementDataIsConnectable] as Any,
            ],
        ]
    }

    private func writeJSONLine(_ event: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(event),
              let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
              let newline = "\n".data(using: .utf8)
        else {
            increment("write_errors")
            return
        }
        observationHandle.write(data)
        observationHandle.write(newline)
    }

    private func finish(exitCode: Int32) {
        manager?.stopScan()
        let summary: [String: Any] = [
            "run": [
                "started_at_utc": ISO8601DateFormatter.utc.string(from: startedAt),
                "finished_at_utc": ISO8601DateFormatter.utc.string(from: Date()),
                "duration_seconds": durationSeconds(),
                "platform": [
                    "system": "macOS",
                    "scanner": "Swift CoreBluetooth",
                ],
            ],
            "config": [
                "record_all": options.candidatesOnly ? false : config.scan.record_all,
                "min_rssi": options.minRSSI ?? config.scan.min_rssi,
                "dedupe_window_seconds": config.scan.dedupe_window_seconds,
            ],
            "counters": counters,
            "devices": summaries.values
                .sorted { $0.count > $1.count }
                .map { $0.jsonObject() },
        ]

        if JSONSerialization.isValidJSONObject(summary),
           let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: summaryPath)
        }

        print("Scan complete. Recorded \(counters["recorded"] ?? 0) observations from \(summaries.count) devices.")
        print("Summary saved to: \(summaryPath.path)")
        if counters["candidates", default: 0] == 0 {
            print("No configured S400 candidate was detected yet. This is normal before we know the exact BLE identifier.")
        }
        Foundation.exit(exitCode)
    }

    private func durationSeconds() -> Int {
        options.duration ?? config.scan.duration_seconds
    }

    private func increment(_ key: String) {
        counters[key, default: 0] += 1
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension ISO8601DateFormatter {
    static let utc: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let local: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

func parseManufacturerID(from data: Data) -> String? {
    guard data.count >= 2 else { return nil }
    let value = UInt16(data[0]) | (UInt16(data[1]) << 8)
    return String(format: "0x%04x", value)
}

func eventFingerprint(_ event: [String: Any]) -> String {
    let device = event["device"] as? [String: Any] ?? [:]
    let advertisement = event["advertisement"] as? [String: Any] ?? [:]
    return [
        device["id"] as? String ?? "",
        advertisement["local_name"] as? String ?? "",
        advertisement["manufacturer_data"] as? String ?? "",
        String(describing: advertisement["service_data"] ?? ""),
    ].joined(separator: "|")
}

func loadConfig(path: String) -> AppConfig {
    guard FileManager.default.fileExists(atPath: path) else {
        return AppConfig()
    }

    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(AppConfig.self, from: data)
    } catch {
        fputs("Invalid config file at \(path): \(error)\n", stderr)
        Foundation.exit(2)
    }
}

func parseArgs() -> RuntimeOptions {
    var options = RuntimeOptions()
    var index = 1
    let args = CommandLine.arguments
    while index < args.count {
        let arg = args[index]
        func nextValue() -> String? {
            guard index + 1 < args.count else { return nil }
            index += 1
            return args[index]
        }

        switch arg {
        case "--config":
            options.configPath = nextValue() ?? options.configPath
        case "--duration":
            options.duration = Int(nextValue() ?? "")
        case "--output-dir":
            options.outputDir = nextValue()
        case "--summary-dir":
            options.summaryDir = nextValue()
        case "--label":
            options.label = nextValue()
        case "--min-rssi":
            options.minRSSI = Int(nextValue() ?? "")
        case "--candidates-only":
            options.candidatesOnly = true
        case "--help", "-h":
            printUsageAndExit()
        default:
            fputs("Unknown argument: \(arg)\n", stderr)
            printUsageAndExit(code: 2)
        }
        index += 1
    }
    return options
}

func printUsageAndExit(code: Int32 = 0) -> Never {
    print("""
    Usage: s400-ble-scan [options]

    Options:
      --config PATH          Config file path, defaults to config.json
      --duration SECONDS     Scan duration
      --output-dir DIR       Raw JSONL output directory
      --summary-dir DIR      Summary JSON output directory
      --label TEXT           Add a label to output filenames
      --min-rssi RSSI        Ignore weak signals below this value
      --candidates-only      Only save configured candidate devices
    """)
    Foundation.exit(code)
}

func makeOutputPaths(config: AppConfig, options: RuntimeOptions) throws -> (URL, URL) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let runID = formatter.string(from: Date())
    let label = options.label.map { "-\($0)" } ?? ""
    let observationDir = URL(fileURLWithPath: options.outputDir ?? config.output.observation_dir)
    let summaryDir = URL(fileURLWithPath: options.summaryDir ?? config.output.summary_dir)
    try FileManager.default.createDirectory(at: observationDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: summaryDir, withIntermediateDirectories: true)
    return (
        observationDir.appendingPathComponent("ble_scan_\(runID)\(label).jsonl"),
        summaryDir.appendingPathComponent("ble_scan_\(runID)\(label).summary.json")
    )
}

let options = parseArgs()
let config = loadConfig(path: options.configPath)
do {
    let paths = try makeOutputPaths(config: config, options: options)
    let scanner = try Scanner(config: config, options: options, observationPath: paths.0, summaryPath: paths.1)
    scanner.start()
    RunLoop.main.run()
} catch {
    fputs("Failed to start scanner: \(error)\n", stderr)
    Foundation.exit(1)
}
