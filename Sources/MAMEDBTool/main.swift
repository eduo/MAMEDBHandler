import Foundation
import MAMEDBHandler

enum Command: String {
    case selftest  // Run  demo behavior
    case version   // Display DB version
    case game      // Get info for a specific game
    case set       // Get rom sets for a game
    case crc       // Find games matching CRCs
    case help      // Show help
    case xml       // Create database from XML file
}

func printUsage() {
    print("\n\u{001B}[1mMAMEDBHandler Command Line Tool\u{001B}[0m")
    print("=" * 35)
    print()
    print("\u{001B}[1mUSAGE:\u{001B}[0m")
    print("  \u{001B}[36mMAMEDBTool --db [path] [options]\u{001B}[0m")
    print("  \u{001B}[36mMAMEDBTool --xml [path] --dbout [path] [options]\u{001B}[0m")
    print()
    print("\u{001B}[1mREQUIRED (choose one):\u{001B}[0m")
    print("  \u{001B}[32m--db\u{001B}[0m [path]               Path to the MAME database file")
    print("  \u{001B}[32m--xml\u{001B}[0m [path]             Path to the MAME XML file to parse")
    print()
    print("\u{001B}[1mXML OPTIONS:\u{001B}[0m")
    print("  \u{001B}[32m--dbout\u{001B}[0m [path]            Path for the output database file (required with --xml)")
    print("  \u{001B}[32m--force\u{001B}[0m                   Force overwrite of existing database file")
    print()
    print("\u{001B}[1mOTHER OPTIONS:\u{001B}[0m")
    print("  \u{001B}[32m--version\u{001B}[0m                 Display the MAME database version")
    print("  \u{001B}[32m--game\u{001B}[0m [name]             Get information about a specific game")
    print("  \u{001B}[32m--set\u{001B}[0m [type]              Get ROM set for the specified game (requires --game)")
    print("                         Valid types: split, merged, nonmerged, mergedplus, mergedfull, nonmergedplus, nonmergedfull")
    print("  \u{001B}[32m--crc\u{001B}[0m [crc1,crc2,...]     Find games matching CRC32 values")
    print("  \u{001B}[32m--selftest\u{001B}[0m                Run a simple test with pacman")
    print("  \u{001B}[32m--help\u{001B}[0m                    Show this help")
    print()
    print("\u{001B}[1mEXAMPLES:\u{001B}[0m")
    print("  MAMEDBTool --db /path/to/MameMachine.sqlite --game pacman")
    print("  MAMEDBTool --db /path/to/MameMachine.sqlite --game pacman --set merged")
    print("  MAMEDBTool --db /path/to/MameMachine.sqlite --crc C1E6AB10,1A6FB2D4")
    print("  MAMEDBTool --xml /path/to/mame.xml --dbout /path/to/output.sqlite --force")
    print()
}

func printSectionHeader(_ title: String) {
    print("\n\u{001B}[1m\u{001B}[34m" + title + "\u{001B}[0m")
    print("-" * title.count)
}

func *(string: String, count: Int) -> String {
    return String(repeating: string, count: count)
}

func runSelfTest(dbPath: String) async {
    print("\u{001B}[1mMAMEDBHandler Command Line Tool\u{001B}[0m")
    print("=" * 35)
    
    do {
        // Open the database
        guard let manager = await MameDBManager.forDatabase(at: dbPath) else {
            print("\u{001B}[31mError: Unable to open database at \(dbPath)\u{001B}[0m")
            return
        }
        
        // Get version
        let version = try await manager.getMameVersion()
        print("MAME version: \(version)")
        
        // Get master list
        print("Loading master list...")
        let masterList = try await MasterListManager.shared.getMasterList(for: "default", databasePath: dbPath)
        print("Loaded \(masterList.count) games")
        
        // Print some sample games
        printSectionHeader("Sample games")
        for game in masterList.prefix(5) {
            print("- \u{001B}[36m\(game.name)\u{001B}[0m: \(game.description) (\(game.year))")
        }
        
        // Load details for a specific game
        let gameId = "18wheelr"
        printSectionHeader("Loading details for \(gameId)")
        
        // Load comprehensive machine data
        let data = try await manager.loadGameDetails(for: gameId)
        let machine = data.machine
        let directRoms = data.directRoms.map { $0.rom }
        
        print("Game: \(machine.description)")
        print("Year: \(machine.year)")
        print("Manufacturer: \(machine.manufacturer)")
        if let parent = machine.cloneof {
            print("Parent: \(parent)")
        }
        print("ROMs: \(directRoms.count)")
        for rom in directRoms.prefix(3) {
            print("- \(rom.name): \(rom.size) bytes, CRC: \(rom.crc)")
        }
        if directRoms.count > 3 {
            print("- ... and \(directRoms.count - 3) more")
        }
        
        // Get different ROM sets
        printSectionHeader("ROM sets for \(gameId)")
        
        // Note: If these functions are actor-isolated, use 'await' before each call
        print("Loading split set...")
        let splitRoms = MameDBManager.getSplitSetRoms(from: data)
        print("Split set: \(splitRoms.count) ROMs")
        
        print("Loading merged set...")
        let mergedRoms = MameDBManager.getMergedSetRoms(from: data)
        print("Merged set: \(mergedRoms.count) ROMs")
        
        print("Loading merged plus set...")
        let mergedPlus = MameDBManager.getMergedPlusSetRoms(from: data)
        print("Merged plus set: \(mergedPlus.count) ROMs")

        print("Loading merged full set...")
        let mergedFull = MameDBManager.getMergedFullSetRoms(from: data)
        print("Merged full set: \(mergedFull.count) ROMs")

        print("Loading non-merged set...")
        let nonMergedRoms = MameDBManager.getNonMergedSetRoms(from: data)
        print("Non-merged set: \(nonMergedRoms.count) ROMs")
        
        print("Loading non-merged plus set...")
        let nonMergedPlus = MameDBManager.getNonMergedPlusSetRoms(from: data)
        print("Non-merged plus set: \(nonMergedPlus.count) ROMs")

        print("Loading non-merged full set...")
        let nonMergedFull = MameDBManager.getNonMergedFullSetRoms(from: data)
        print("Non-merged full set: \(nonMergedFull.count) ROMs")
        
    } catch {
        print("\u{001B}[31mError: \(error.localizedDescription)\u{001B}[0m")
    }
}

func showVersion(dbPath: String) async {
    printSectionHeader("MAME Database Version")
    
    do {
        // Open the database
        guard let manager = await MameDBManager.forDatabase(at: dbPath) else {
            print("\u{001B}[31mError: Unable to open database at \(dbPath)\u{001B}[0m")
            return
        }
        
        let version = try await manager.getMameVersion()
        print("Version: \u{001B}[32m\(version)\u{001B}[0m")
    } catch {
        print("\u{001B}[31mError: \(error.localizedDescription)\u{001B}[0m")
    }
}

func showGameInfo(name: String, dbPath: String) async {
    printSectionHeader("Game Information: \(name)")
    
    do {
        // Open the database
        guard let manager = await MameDBManager.forDatabase(at: dbPath) else {
            print("\u{001B}[31mError: Unable to open database at \(dbPath)\u{001B}[0m")
            return
        }
        
        // 1. Load comprehensive machine data
        let data = try await manager.loadGameDetails(for: name)
        let machine = data.machine
        
        print("\u{001B}[1mBasic Information\u{001B}[0m")
        print("  Name: \u{001B}[36m\(machine.name)\u{001B}[0m")
        print("  Description: \(machine.description)")
        print("  Year: \(machine.year)")
        print("  Manufacturer: \(machine.manufacturer)")
        
        if let parent = machine.cloneof {
            print("  Parent: \(parent)")
            if let parentName = machine.parent_name {
                print("  Parent Title: \(parentName)")
            }
            if let parentYear = machine.parent_year {
                print("  Parent Year: \(parentYear)")
            }
        }
        
        // 2. Load enriched information from master list
        let masterList = try await MasterListManager.shared.getMasterList(for: "default", databasePath: dbPath)
        
        if let enrichedGame = masterList.first(where: { $0.name == name }) {
            printSectionHeader("Enriched Information")
            
            // Display languages
            if !enrichedGame.languages.isEmpty {
                print("  Languages: \(enrichedGame.languages.joined(separator: ", "))")
            }
            
            // Display category info
            if let machineType = enrichedGame.machineType {
                print("  Machine Type: \(machineType)")
            }
            if let category = enrichedGame.category {
                print("  Category: \(category)")
            }
            if let subcategory = enrichedGame.subcategory {
                print("  Subcategory: \(subcategory)")
            }
            if enrichedGame.isMature {
                print("  \u{001B}[31mMature Content\u{001B}[0m")
            }
            
            // Display rating info
            if let rating = enrichedGame.gameRating {
                print("  Rating: \(String(format: "%.1f", rating.score)) stars")
                print("  Rating Category: \(rating.section)")
            }
        }
        
        // 3. Display ROM summary
        let romCount = data.allRoms.filter { $0.source == .machine }.count
        print("\n  ROM Count: \(romCount) direct ROMs")
        
        // 4. Suggest set command for ROM details
        print("\n\u{001B}[33mTip: Use '--set [type] --game \(name)' to view ROM details\u{001B}[0m")
        
    } catch {
        print("\u{001B}[31mError: \(error.localizedDescription)\u{001B}[0m")
    }
}

func showRomSet(type: SetType, game: String, dbPath: String) async {
    printSectionHeader("\(type.rawValue.capitalized) ROM Set: \(game)")
    
    do {
        // Open the database
        guard let manager = await MameDBManager.forDatabase(at: dbPath) else {
            print("\u{001B}[31mError: Unable to open database at \(dbPath)\u{001B}[0m")
            return
        }
        
        // Load machine data once
        let data = try await manager.loadGameDetails(for: game)
        
        // Get specific ROM set based on type
        let roms: [RomInfo]
        
        switch type {
        case .split:
            roms = MameDBManager.getSplitSetRoms(from: data)
        case .merged:
            roms = MameDBManager.getMergedSetRoms(from: data)
        case .nonmerged:
            roms = MameDBManager.getNonMergedSetRoms(from: data)
        case .mergedplus:
            roms = MameDBManager.getMergedPlusSetRoms(from: data)
        case .mergedfull:
            roms = MameDBManager.getMergedFullSetRoms(from: data)
        case .nonmergedplus:
            roms = MameDBManager.getNonMergedPlusSetRoms(from: data)
        case .nonmergedfull:
            roms = MameDBManager.getNonMergedFullSetRoms(from: data)
        }
        
        print("Total ROMs: \(roms.count)")
        
        if roms.isEmpty {
            print("\u{001B}[33mNo ROMs found for this set type\u{001B}[0m")
            return
        }
        
        // Display ROM information in an ASCII table format
        print("")
        printTableHeader()
        
        // Process and display ROMs based on set type
        for rom in roms {
            // Determine source and ROM type
            var source = data.machine.name
            var romType = "Game ROM"
            
            // Use ROM type directly from the ROM object combined with machine data
            switch rom.type {
            case .deviceRom:
                romType = "Device ROM"
                // Find the device name where this ROM comes from
                if let deviceRomInfo = data.allRoms.first(where: { $0.rom.name == rom.name && $0.source == .device }) {
                    source = deviceRomInfo.machineName
                }
            case .biosRom:
                romType = "BIOS ROM"
            case .cloneRom:
                romType = "Clone ROM"
                if data.machine.cloneof != nil {
                    source = data.machine.name
                }
            case .gameRom:
                if data.machine.cloneof != nil {
                    // If this is a parent ROM in a clone
                    if let parentRomInfo = data.allRoms.first(where: { $0.rom.name == rom.name && $0.source == .parent }) {
                        source = parentRomInfo.machineName
                        romType = "Parent ROM"
                    }
                } else {
                    romType = "Game ROM"
                }
            }
            
            printRomRow(rom: rom, source: source, romType: romType, replaces: rom.merge)
        }
        
        printTableFooter()
    } catch {
        print("\u{001B}[31mError: \(error.localizedDescription)\u{001B}[0m")
    }
}


func printTableHeader() {
    print("┌────────────────────────────┬───────────┬───────────────┬──────────────────────┬────────────────┬────────────────┐")
    print("│ ROM Name                   │ Size      │ CRC32         │ Source               │ Type           │ Replaces       │")
    print("├────────────────────────────┼───────────┼───────────────┼──────────────────────┼────────────────┼────────────────┤")
}

func printTableFooter() {
    print("└────────────────────────────┴───────────┴───────────────┴──────────────────────┴────────────────┴────────────────┘")
}

func printRomRow(rom: RomInfo, source: String, romType: String, replaces: String? = nil) {
    let nameFormatted = rom.name.padding(toLength: 27, withPad: " ", startingAt: 0)
    let sizeFormatted = formatFileSize(rom.size).padding(toLength: 10, withPad: " ", startingAt: 0)
    let crcFormatted = rom.crc.padding(toLength: 14, withPad: " ", startingAt: 0)
    let sourceFormatted = source.padding(toLength: 21, withPad: " ", startingAt: 0)
    
    // Use the provided ROM type string
    let typeFormatted = romType.padding(toLength: 15, withPad: " ", startingAt: 0)
    
    let replacesFormatted = (replaces ?? "").padding(toLength: 15, withPad: " ", startingAt: 0)
    
    print("│ \(nameFormatted)│ \(sizeFormatted)│ \(crcFormatted)│ \(sourceFormatted)│ \(typeFormatted)│ \(replacesFormatted)│")
}

func formatFileSize(_ size: Int64) -> String {
    let kb = Double(size) / 1024.0
    if kb < 1.0 {
        return "\(size) B"
    } else if kb < 1024.0 {
        return String(format: "%.1f KB", kb)
    } else {
        return String(format: "%.1f MB", kb / 1024.0)
    }
}

func findGamesByCRC(crcs: [String], dbPath: String) async {
    printSectionHeader("Finding Games by CRC32 Values")
    
    do {
        // Open the database
        guard let manager = await MameDBManager.forDatabase(at: dbPath) else {
            print("\u{001B}[31mError: Unable to open database at \(dbPath)\u{001B}[0m")
            return
        }
        
        print("Searching for CRCs: \(crcs.joined(separator: ", "))")
        
        if let machineId = try await manager.findMachineWithCRCs(crcs) {
            if let gameName = try await manager.getGameNameForMachine(machineId) {
                print("\n\u{001B}[32mFound matching game: \(gameName)\u{001B}[0m")
                
                // Show additional game details
                await showGameInfo(name: gameName, dbPath: dbPath)
            } else {
                print("\u{001B}[33mFound machine ID \(machineId) but couldn't retrieve game name\u{001B}[0m")
            }
        } else {
            print("\u{001B}[33mNo matching game found for the provided CRCs\u{001B}[0m")
        }
    } catch {
        print("\u{001B}[31mError: \(error.localizedDescription)\u{001B}[0m")
    }
}

func createDatabaseFromXML(xmlPath: String, dboutPath: String, force: Bool) async {
    printSectionHeader("Creating Database from XML")
    
    do {
        let xmlURL = URL(fileURLWithPath: xmlPath)
        let dboutURL = URL(fileURLWithPath: dboutPath)
        
        // Check if XML file exists
        guard FileManager.default.fileExists(atPath: xmlPath) else {
            print("\u{001B}[31mError: XML file not found at \(xmlPath)\u{001B}[0m")
            return
        }
        
        // Check if output directory exists
        let outputDirectory = dboutURL.deletingLastPathComponent()
        
        if !FileManager.default.fileExists(atPath: outputDirectory.path) {
            print("\u{001B}[33mOutput directory doesn't exist. Attempting to create it...\u{001B}[0m")
            do {
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                print("\u{001B}[32mCreated output directory: \(outputDirectory.path)\u{001B}[0m")
            } catch {
                print("\u{001B}[31mError: Failed to create output directory: \(error.localizedDescription)\u{001B}[0m")
                return
            }
        }
        
        // Check if output file exists and handle force flag
        if FileManager.default.fileExists(atPath: dboutURL.path) {
            if force {
                print("\u{001B}[33mOutput file already exists. Overwriting due to --force flag.\u{001B}[0m")
            } else {
                print("\u{001B}[31mError: Output file already exists at \(dboutURL.path). Use --force to overwrite.\u{001B}[0m")
                return
            }
        }
        
        print("Parsing XML file: \(xmlURL.path)")
        print("Creating database at: \(dboutURL.path)")
        
        // Create the database manager
        let manager = try await MameDBManager.createDatabase(
            from: xmlURL,
            savingTo: dboutURL,
            overwrite: force
        )
        
        // Verify the database by getting the version
        let version = try await manager.getMameVersion()
        print("\u{001B}[32mDatabase created successfully!\u{001B}[0m")
        print("MAME version: \(version)")
        
    } catch let error as MAMEXMLParser.ParserError {
        print("\u{001B}[31mError: \(error.localizedDescription)\u{001B}[0m")
    } catch {
        print("\u{001B}[31mError: \(error.localizedDescription)\u{001B}[0m")
    }
}

// Main function with proper Task management
func main() async {
    let args = CommandLine.arguments
    
    // Default behavior shows help if no arguments provided
    if args.count == 1 {
        printUsage()
        return
    }
    
    // Process arguments
    var i = 1
    var command: Command = .help
    var gameName: String?
    var setType: SetType?
    var dbPath: String?
    var crcValues: [String] = []
    var xmlPath: String?
    var dboutPath: String?
    var force: Bool = false
    
    while i < args.count {
        switch args[i] {
        case "--selftest":
            command = .selftest
            
        case "--version":
            command = .version
            
            
        case "--game":
            command = .game
            if i+1 < args.count && !args[i+1].hasPrefix("--") {
                gameName = args[i+1]
                i += 1
            } else {
                print("\u{001B}[31mError: --game requires a game name\u{001B}[0m")
                printUsage()
                return
            }
            
        case "--set":
            command = .set
            if i+1 < args.count && !args[i+1].hasPrefix("--") {
                if let type = SetType(rawValue: args[i+1].lowercased()) {
                    setType = type
                    i += 1
                } else {
                    print("\u{001B}[31mError: Invalid set type: \(args[i+1])\u{001B}[0m")
                    printUsage()
                    return
                }
            } else {
                print("\u{001B}[31mError: --set requires a set type\u{001B}[0m")
                printUsage()
                return
            }

        case "--crc":
            command = .crc
            if i+1 < args.count && !args[i+1].hasPrefix("--") {
                crcValues = args[i+1].split(separator: ",").map { String($0).uppercased() }
                i += 1
            } else {
                print("\u{001B}[31mError: --crc requires comma-separated CRC values\u{001B}[0m")
                printUsage()
                return
            }
            
        case "--db":
            if i+1 < args.count && !args[i+1].hasPrefix("--") {
                dbPath = args[i+1]
                i += 1
            } else {
                print("\u{001B}[31mError: --db requires a database path\u{001B}[0m")
                printUsage()
                return
            }
            
        case "--xml":
            command = .xml
            if i+1 < args.count && !args[i+1].hasPrefix("--") {
                xmlPath = args[i+1]
                i += 1
            } else {
                print("\u{001B}[31mError: --xml requires a file path\u{001B}[0m")
                printUsage()
                return
            }
            
        case "--dbout":
            if i+1 < args.count && !args[i+1].hasPrefix("--") {
                dboutPath = args[i+1]
                i += 1
            } else {
                print("\u{001B}[31mError: --dbout requires a database path\u{001B}[0m")
                printUsage()
                return
            }
            
        case "--force":
            force = true
            
        case "--help":
            command = .help
            
        default:
            print("\u{001B}[31mUnknown option: \(args[i])\u{001B}[0m")
            printUsage()
            return
        }
        
        i += 1
    }
    
    // Validate command-specific requirements
    if command == .xml {
        // For XML command, we need both XML path and output path
        if xmlPath == nil {
            print("\u{001B}[31mError: XML path is required (--xml parameter)\u{001B}[0m")
            printUsage()
            return
        }
        
        if dboutPath == nil {
            print("\u{001B}[31mError: Output database path is required (--dbout parameter)\u{001B}[0m")
            printUsage()
            return
        }
    } else if command != .help && dbPath == nil {
        // For all other commands except help, database path is required
        print("\u{001B}[31mError: Database path is required (--db parameter)\u{001B}[0m")
        printUsage()
        return
    }
    
    // Execute the appropriate command
    switch command {
    case .selftest:
        await runSelfTest(dbPath: dbPath!)
        
    case .version:
        await showVersion(dbPath: dbPath!)
        
    case .game:
        if let gameName = gameName {
            await showGameInfo(name: gameName, dbPath: dbPath!)
        } else {
            print("\u{001B}[31mError: No game name provided\u{001B}[0m")
            printUsage()
        }
        
    case .set:
        if let gameName = gameName, let setType = setType {
            await showRomSet(type: setType, game: gameName, dbPath: dbPath!)
        } else {
            print("\u{001B}[31mError: Missing game name or set type\u{001B}[0m")
            printUsage()
        }

        if let gameName = gameName, let setType = setType {
            await showRomSet(type: setType, game: gameName, dbPath: dbPath!)
        } else {
            print("\u{001B}[31mError: Missing game name or set type\u{001B}[0m")
            printUsage()
        }
        
    case .crc:
        if !crcValues.isEmpty {
            await findGamesByCRC(crcs: crcValues, dbPath: dbPath!)
        } else {
            print("\u{001B}[31mError: No CRC values provided\u{001B}[0m")
            printUsage()
        }
        
    case .xml:
        if let xmlPath = xmlPath, let dboutPath = dboutPath {
            await createDatabaseFromXML(xmlPath: xmlPath, dboutPath: dboutPath, force: force)
        }
        
    case .help:
        printUsage()
    }
}

// Proper Task construction
Task {
    await main()
    exit(0)
}

RunLoop.main.run()


