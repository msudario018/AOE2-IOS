import Foundation
import UIKit

/// Status of the Age of Empires II game data in the iOS sandbox.
public enum GameDataStatus {
    case ready(gameDir: URL, exePath: URL, diskImagePath: URL?)
    case missingFiles(expected: [String], foundPath: URL)
    case uninitialized
}

/// GameFileManager
///
/// Manages the sandbox `Documents/` folder shared with iTunes / Apple Finder (`UIFileSharingEnabled`).
/// Inspired directly by `fallout1-ce`'s iOS storage coordinator.
public class GameFileManager {
    
    public static let shared = GameFileManager()
    
    // Key game executables and data archives for Age of Empires II (1999) & The Conquerors Expansion (2000)
    public static let candidateExecutables = [
        "EMPIRES2.EXE",
        "empires2.exe",
        "AGE2_X1.EXE",
        "age2_x1.exe",
        "AoE2.exe"
    ]
    
    public static let criticalDataFiles = [
        "data/empires2.dat",
        "data/age2_x1.dat"
    ]
    
    public static let diskImageNames = [
        "win98se.img",
        "win98.img",
        "dosbox_win98.img",
        "win95.img"
    ]
    
    private let fileManager = FileManager.default
    
    /// Path to user-accessible Documents directory
    public var documentsDirectory: URL {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    /// Dedicated subfolder where AoE2 game data resides
    public var gameDataDirectory: URL {
        return documentsDirectory.appendingPathComponent("Age of Empires II", isDirectory: true)
    }
    
    private init() {
        createDefaultDirectoriesIfNeeded()
    }
    
    private func createDefaultDirectoriesIfNeeded() {
        let gameDir = gameDataDirectory
        if !fileManager.fileExists(atPath: gameDir.path) {
            do {
                try fileManager.createDirectory(at: gameDir, withIntermediateDirectories: true, attributes: nil)
                Log.info(.fileSystem, "Created game data directory: \(gameDir.path)")
            } catch {
                Log.error(.fileSystem, "Failed to create game directory: \(error.localizedDescription)")
            }
        }
        
        let logsDir = documentsDirectory.appendingPathComponent("Logs", isDirectory: true)
        if !fileManager.fileExists(atPath: logsDir.path) {
            try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    /// Verifies if valid game files exist in either `Documents/` or `Documents/Age of Empires II/`.
    public func verifyGameInstallation() -> GameDataStatus {
        Log.info(.fileSystem, "Verifying game installation in sandbox Documents...")
        
        // Log all files currently visible in Documents/
        if let docsContents = try? fileManager.contentsOfDirectory(atPath: documentsDirectory.path) {
            Log.info(.fileSystem, "Documents/ contents count: \(docsContents.count) items -> [\(docsContents.joined(separator: ", "))]")
        }
        
        // 1. Check inside "Documents/Age of Empires II"
        var checkURL = gameDataDirectory
        if let exeURL = findExecutable(in: checkURL) {
            let diskImage = findDiskImage()
            Log.info(.fileSystem, "Found executable at '\(exeURL.path)'. DiskImage: \(diskImage?.path ?? "(none)")")
            verifyCriticalAssets(in: checkURL)
            return .ready(gameDir: checkURL, exePath: exeURL, diskImagePath: diskImage)
        }
        
        // 2. Check root of "Documents/"
        checkURL = documentsDirectory
        if let exeURL = findExecutable(in: checkURL) {
            let diskImage = findDiskImage()
            Log.info(.fileSystem, "Found executable directly in Documents root: '\(exeURL.path)'. DiskImage: \(diskImage?.path ?? "(none)")")
            verifyCriticalAssets(in: checkURL)
            return .ready(gameDir: checkURL, exePath: exeURL, diskImagePath: diskImage)
        }
        
        // 3. Check any subfolder in Documents/
        if let subdirs = try? fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
            for dir in subdirs {
                if let exeURL = findExecutable(in: dir) {
                    let diskImage = findDiskImage()
                    Log.info(.fileSystem, "Found executable in subfolder: '\(exeURL.path)'. DiskImage: \(diskImage?.path ?? "(none)")")
                    verifyCriticalAssets(in: dir)
                    return .ready(gameDir: dir, exePath: exeURL, diskImagePath: diskImage)
                }
            }
        }
        
        Log.warn(.fileSystem, "No valid Age of Empires II executable (EMPIRES2.EXE) found in Documents.")
        return .missingFiles(expected: ["EMPIRES2.EXE", "data/empires2.dat", "win98se.img"], foundPath: documentsDirectory)
    }
    
    private func verifyCriticalAssets(in directory: URL) {
        for asset in GameFileManager.criticalDataFiles {
            let fullPath = directory.appendingPathComponent(asset)
            if fileManager.fileExists(atPath: fullPath.path) {
                Log.info(.fileSystem, "Verified critical asset: \(asset)")
            } else {
                Log.warn(.fileSystem, "Critical asset missing: \(asset) (Game may experience missing graphics/campaign data)")
            }
        }
    }
    
    private func findExecutable(in directory: URL) -> URL? {
        for exeName in GameFileManager.candidateExecutables {
            let direct = directory.appendingPathComponent(exeName)
            if fileManager.fileExists(atPath: direct.path) {
                return direct
            }
            // Case-insensitive fallback
            if let resolved = caseInsensitiveSearch(directory: directory, targetName: exeName) {
                return resolved
            }
        }
        return nil
    }
    
    private func findDiskImage() -> URL? {
        for imgName in GameFileManager.diskImageNames {
            let direct = documentsDirectory.appendingPathComponent(imgName)
            if fileManager.fileExists(atPath: direct.path) {
                return direct
            }
            let sub = gameDataDirectory.appendingPathComponent(imgName)
            if fileManager.fileExists(atPath: sub.path) {
                return sub
            }
        }
        return nil
    }
    
    /// Case-insensitive file path resolver for case-sensitive iOS APFS filesystem.
    public func caseInsensitiveSearch(directory: URL, targetName: String) -> URL? {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return nil }
        for item in contents {
            if item.caseInsensitiveCompare(targetName) == .orderedSame {
                return directory.appendingPathComponent(item)
            }
        }
        return nil
    }
    
    /// Imports a folder or file selected via UIDocumentPickerViewController
    public func importFromURL(_ sourceURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        Log.info(.fileSystem, "Starting import from external URL: \(sourceURL.path)")
        
        let isSecurityScoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDir)
        
        let destinationURL = gameDataDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                Log.info(.fileSystem, "Destination '\(destinationURL.lastPathComponent)' exists. Overwriting...")
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            Log.info(.fileSystem, "Successfully copied '\(sourceURL.lastPathComponent)' to \(destinationURL.path)")
            completion(.success(destinationURL))
        } catch {
            Log.error(.fileSystem, "Failed to import file: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
}
