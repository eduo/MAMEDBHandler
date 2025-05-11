# MAMEDBHandler

A Swift package for managing MAME arcade game emulator databases that provides functionality to query and retrieve information about arcade games, their ROM sets, and perform compliance checking.

## Features

- Create SQLite databases from MAME XML files
- Query for game and ROM information
- Support for multiple ROM set formats (split, merged, non-merged, etc.)
- Efficient memory usage with actor-based concurrency
- Game categorization and metadata support

Please note this library expects to read information from the SQLite databases it creates itself and not from other conversions from MAME's XML into SQLite. This library's SQLite Mame Databases are optimized only towards size by focusing only on machine details and ROM/bios/devices details.

## Requirements

- macOS 12.0+
- Swift 5.5+

## Installation

### Swift Package Manager

Add MAMEDBHandler to your Package.swift:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/MAMEDBHandler.git", from: "1.0.0")
]
```

## Quick Start

```swift
import MAMEDBHandler

// Initialize with an existing database
let dbPath = "/path/to/mame.sqlite"
if let manager = await MameDBManager.forDatabase(at: dbPath) {
    // Get information about a game
    let gameData = try await manager.loadGameDetails(for: "pacman")
    
    // Get merged ROM set
    let mergedRoms = MameDBManager.getMergedSetRoms(from: gameData)
    
    // Print ROM information
    for rom in mergedRoms {
        print("\(rom.name): \(rom.size) bytes, CRC: \(rom.crc)")
    }
}

// Create a database from XML
let xmlPath = "/path/to/mame.xml"
let outputPath = "/path/to/output.sqlite"
let manager = try await MameDBManager.createDatabase(
    from: URL(fileURLWithPath: xmlPath),
    savingTo: URL(fileURLWithPath: outputPath),
    overwrite: true
)
```

## ROM Set Types

The package supports several ROM set formats:

- **Split**: Only ROMs specific to a game
- **Merged**: ROMs from a game and its parent/clones
- **Non-merged**: Game ROMs plus parent ROMs
- **MergedPlus**: Merged set plus device ROMs
- **MergedFull**: Merged set plus device and BIOS ROMs
- **NonMergedPlus**: Non-merged set plus device ROMs
- **NonMergedFull**: Non-merged set plus device and BIOS ROMs

# MAMEDBHandler API Documentation

## Core Components

### MameDBManager

The primary interface for interacting with MAME databases.

#### Initialization

```swift
// Initialize with an existing database
public static func forDatabase(at path: String) async -> MameDBManager?

// Create a new database from MAME XML
public static func createDatabase(
    from xmlURL: URL, 
    savingTo outputURL: URL, 
    overwrite: Bool = false
) async throws -> MameDBManager
```

#### Game Information

```swift
// Get MAME version from database
public func getMameVersion() async throws -> String

// Load detailed information about a specific game
public func loadGameDetails(for gameId: String) async throws -> MachineData

// Get list of all machines/games
public func loadAllMachines() async throws -> [MachineInfo]

// Find a machine by ROM CRCs
public func findMachineWithCRCs(_ crcs: [String]) async throws -> Int?

// Get game name for a machine ID
public func getGameNameForMachine(_ machineId: Int) async throws -> String?
```

#### ROM Set Processing

```swift
// Get split set (game-specific ROMs only)
public static func getSplitSetRoms(from data: MachineData) -> [RomInfo]

// Get merged set (game + parent/clone ROMs)
public static func getMergedSetRoms(from data: MachineData) -> [RomInfo]

// Get non-merged set (game ROMs + required parent ROMs)
public static func getNonMergedSetRoms(from data: MachineData) -> [RomInfo]

// Variants with device and BIOS ROMs
public static func getMergedPlusSetRoms(from data: MachineData) -> [RomInfo]
public static func getMergedFullSetRoms(from data: MachineData) -> [RomInfo]
public static func getNonMergedPlusSetRoms(from data: MachineData) -> [RomInfo]
public static func getNonMergedFullSetRoms(from data: MachineData) -> [RomInfo]

// Generic function accepting SetType enum
public static func getRomSet(type: SetType, from data: MachineData) -> [RomInfo]
```

### MasterListManager

Manages cached lists of games to improve performance.

```swift
// Get the shared instance
public static let shared: MasterListManager

// Get or load the master list for a specific database version
public func getMasterList(
    for version: String, 
    databasePath: String? = nil
) async throws -> [MameGame]
```

## Data Models

### MachineInfo

Contains metadata about MAME machines (games).

```swift
public struct MachineInfo {
    public let description: String
    public let name: String
    public let year: String
    public let manufacturer: String
    public let cloneof: String?
    public let parent_name: String?
    public let parent_year: String?
}
```

### RomInfo

Represents information about ROM files.

```swift
public struct RomInfo {
    public enum RomType: String {
        case gameRom = "game"
        case cloneRom = "clone"
        case biosRom = "bios"
        case deviceRom = "device"
    }

    public let name: String
    public let size: Int64
    public let crc: String
    public let status: String?
    public let merge: String?
    public let type: RomType
}
```

### MameGame

Comprehensive representation of a MAME game with metadata.

```swift
public struct MameGame: Identifiable {
    public var id: String { name }
    
    public let name: String
    public let description: String
    public let year: String
    public let manufacturer: String
    public var roms: [RomInfo]
    public let gameRating: GameRating?
    public let languages: [String]
    public let machineType: String?
    public let category: String?
    public let subcategory: String?
    public let isMature: Bool
    public let shortTitle: String?
    public var source: GameSource
    public var parent: String?
    // Additional properties...
}
```

### MachineData

Comprehensive data structure for a machine and its ROMs.

```swift
public struct MachineData {
    public let machine: MachineInfo
    public let parent: MachineInfo?
    public let allRoms: [RomWithMetadata]
    
    // Derived properties
    public var directRoms: [RomWithMetadata]
    public var parentRoms: [RomWithMetadata]
    public var deviceRoms: [RomWithMetadata]
    public var biosRoms: [RomWithMetadata]
}
```

## Error Handling

```swift
public enum DBError: LocalizedError {
    case queryPreparationFailed
    case recordNotFound
    case deviceRecursionLimit
    case databaseNotInitialized
    case operationFailed(String)
}
```

## Constants and Enums

```swift
public enum SetType: String {
    case split
    case merged
    case nonmerged
    case mergedplus
    case mergedfull
    case nonmergedplus
    case nonmergedfull
}
```

## License

MIT License
