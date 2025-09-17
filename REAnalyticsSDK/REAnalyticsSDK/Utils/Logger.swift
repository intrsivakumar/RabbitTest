
import Foundation
import os.log

internal class Logger {
    
    private static let subsystem = "com.analytics.sdk"
    private static let category = "Analytics"
    
    private static var logLevel: AnalyticsLogLevel = .info
    private static var isFileLoggingEnabled = false
    private static var logFileURL: URL?
    
    private static let logger = OSLog(subsystem: subsystem, category: category)
    private static let logQueue = DispatchQueue(label: "com.analytics.logger", qos: .utility)
    
    // MARK: - Configuration
    
    static func configure(logLevel: AnalyticsLogLevel, enableFileLogging: Bool = false) {
        self.logLevel = logLevel
        self.isFileLoggingEnabled = enableFileLogging
        
        if enableFileLogging {
            setupFileLogging()
        }
    }
    
    // MARK: - Logging Methods
    
    static func verbose(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .verbose, message: message, file: file, function: function, line: line)
    }
    
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }
    
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }
    
    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }
    
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }
    
    // MARK: - Private Methods
    
    private static func log(level: AnalyticsLogLevel, message: String, file: String, function: String, line: Int) {
        guard level.rawValue <= logLevel.rawValue else { return }
        
        logQueue.async {
            let fileName = URL(fileURLWithPath: file).lastPathComponent
            let formattedMessage = "[\(level.emoji)] [\(fileName):\(line)] \(function) - \(message)"
            
            // System logging
            logToSystem(level: level, message: formattedMessage)
            
            // File logging
            if isFileLoggingEnabled {
                logToFile(level: level, message: formattedMessage)
            }
            
            // Console logging for debug builds
            #if DEBUG
            print(formattedMessage)
            #endif
        }
    }
    
    private static func logToSystem(level: AnalyticsLogLevel, message: String) {
        switch level {
        case .none:
            break
        case .error:
            os_log("%{public}@", log: logger, type: .error, message)
        case .warning:
            os_log("%{public}@", log: logger, type: .default, message)
        case .info:
            os_log("%{public}@", log: logger, type: .info, message)
        case .debug:
            os_log("%{public}@", log: logger, type: .debug, message)
        case .verbose:
            os_log("%{public}@", log: logger, type: .debug, message)
        }
    }
    
    private static func logToFile(level: AnalyticsLogLevel, message: String) {
        guard let logFileURL = logFileURL else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "\(timestamp) \(message)\n"
        
        if let data = logEntry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                // Append to existing file
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                // Create new file
                try? data.write(to: logFileURL)
            }
        }
        
        // Rotate log file if it gets too large
        rotateLogFileIfNeeded()
    }
    
    private static func setupFileLogging() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        logFileURL = documentsDirectory.appendingPathComponent("analytics_sdk.log")
    }
    
    private static func rotateLogFileIfNeeded() {
        guard let logFileURL = logFileURL else { return }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
            if let fileSize = attributes[.size] as? NSNumber,
               fileSize.intValue > 5 * 1024 * 1024 { // 5MB
                
                // Create backup
                let backupURL = logFileURL.appendingPathExtension("bak")
                try? FileManager.default.removeItem(at: backupURL)
                try FileManager.default.moveItem(at: logFileURL, to: backupURL)
            }
        } catch {
            // Ignore rotation errors
        }
    }
    
    // MARK: - Log Export
    
    static func exportLogs() -> URL? {
        guard let logFileURL = logFileURL,
              FileManager.default.fileExists(atPath: logFileURL.path) else {
            return nil
        }
        
        return logFileURL
    }
    
    static func clearLogs() {
        guard let logFileURL = logFileURL else { return }
        
        try? FileManager.default.removeItem(at: logFileURL)
        
        // Also clear backup
        let backupURL = logFileURL.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backupURL)
    }
}

// MARK: - Extensions

extension AnalyticsLogLevel {
    var emoji: String {
        switch self {
        case .none: return ""
        case .error: return "❌"
        case .warning: return "⚠️"
        case .info: return "ℹ️"
        case .debug: return "🐛"
        case .verbose: return "🔍"
        }
    }
}
