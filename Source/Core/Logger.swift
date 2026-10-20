import Foundation
import os.log

public enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case fatal = "FATAL"
    
    public var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info:  return "ℹ️"
        case .warn:  return "⚠️"
        case .error: return "❌"
        case .fatal: return "💀"
        }
    }
}

public enum LogCategory: String {
    case general    = "General"
    case emulation  = "Emulation"
    case metal      = "Metal"
    case input      = "Input"
    case fileSystem = "FileSystem"
    case audio      = "Audio"
}

public struct LogEntry: Identifiable {
    public let id = UUID()
    public let date: Date
    public let level: LogLevel
    public let category: LogCategory
    public let message: String
    
    public var formattedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return "\(formatter.string(from: date)) [\(level.rawValue)] [\(category.rawValue)] \(message)"
    }
}

/// Logger
///
/// Centralized diagnostic logging engine that streams log entries to:
/// 1. Console / os_log
/// 2. Persistent file `Documents/Logs/aoe2_runtime.log` (accessible via iTunes/Files)
/// 3. In-memory buffer for real-time in-app HUD inspection
public class Logger {
    public static let shared = Logger()
    
    public private(set) var entries: [LogEntry] = []
    private let maxEntries = 600
    private let lock = NSLock()
    
    public var onNewEntry: ((LogEntry) -> Void)?
    
    private init() {
        // Log startup system info
        logSystemDiagnostics()
    }
    
    public func log(_ level: LogLevel, _ category: LogCategory, _ message: String) {
        let entry = LogEntry(date: Date(), level: level, category: category, message: message)
        
        lock.lock()
        if entries.count >= maxEntries {
            entries.removeFirst(entries.count - maxEntries + 1)
        }
        entries.append(entry)
        lock.unlock()
        
        // Forward to native C crash reporter / file writer
        AoE2_Log(level.rawValue, category.rawValue, "%s", message)
        
        DispatchQueue.main.async { [weak self] in
            self?.onNewEntry?(entry)
        }
    }
    
    private func logSystemDiagnostics() {
        let device = UIDevice.current
        log(.info, .general, "--- AGE OF EMPIRES II iOS RUNTIME INITIALIZING ---")
        log(.info, .general, "Device: \(device.model), System: \(device.systemName) \(device.systemVersion)")
        
        // Log ProMotion display capabilities
        let maxFPS = UIScreen.main.maximumFramesPerSecond
        log(.info, .metal, "Hardware Display Maximum Refresh Rate: \(maxFPS)Hz (ProMotion: \(maxFPS >= 120 ? "ENABLED" : "Standard 60Hz"))")
        
        // Log available storage & memory
        let processInfo = ProcessInfo.processInfo
        let ramMB = processInfo.physicalMemory / (1024 * 1024)
        log(.info, .general, "Physical Memory: \(ramMB) MB, Processor Count: \(processInfo.processorCount)")
    }
    
    /// Reads full persistent runtime log from disk
    public func readFullRuntimeLog() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logFile = docs.appendingPathComponent("Logs/aoe2_runtime.log")
        return (try? String(contentsOf: logFile, encoding: .utf8)) ?? "No runtime log found on disk."
    }
    
    /// Returns path to the runtime log file for exporting via UIActivityViewController
    public var runtimeLogURL: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logFile = docs.appendingPathComponent("Logs/aoe2_runtime.log")
        return FileManager.default.fileExists(atPath: logFile.path) ? logFile : nil
    }
    
    public func clearRuntimeLog() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        
        if let url = runtimeLogURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// Global convenience functions
public enum Log {
    public static func debug(_ category: LogCategory = .general, _ msg: String) {
        Logger.shared.log(.debug, category, msg)
    }
    public static func info(_ category: LogCategory = .general, _ msg: String) {
        Logger.shared.log(.info, category, msg)
    }
    public static func warn(_ category: LogCategory = .general, _ msg: String) {
        Logger.shared.log(.warn, category, msg)
    }
    public static func error(_ category: LogCategory = .general, _ msg: String) {
        Logger.shared.log(.error, category, msg)
    }
    public static func fatal(_ category: LogCategory = .general, _ msg: String) {
        Logger.shared.log(.fatal, category, msg)
    }
}
