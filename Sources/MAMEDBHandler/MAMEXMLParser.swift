// MAMEXMLParser.swift
import Foundation
import SQLite3

/// Actor responsible for parsing MAME XML files and converting them to SQLite databases
public actor MAMEXMLParser {
    // MARK: - Types
    
    /// Errors that can occur during XML parsing and database creation
    public enum ParserError: Error, LocalizedError {
        case xmlParsingFailed(String)
        case fileNotFound(URL)
        case databaseCreationFailed(String)
        case tableCreationFailed(String)
        case dataInsertionFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .xmlParsingFailed(let reason):
                return "XML parsing failed: \(reason)"
            case .fileNotFound(let url):
                return "File not found at \(url.path)"
            case .databaseCreationFailed(let reason):
                return "Database creation failed: \(reason)"
            case .tableCreationFailed(let reason):
                return "Table creation failed: \(reason)"
            case .dataInsertionFailed(let reason):
                return "Data insertion failed: \(reason)"
            }
        }
    }
    
    // MARK: - Properties
    
    /// Shared instance for convenience
    public static let shared = MAMEXMLParser()
    
    // MARK: - Public Methods
    
    /// Parses a MAME XML file and creates a SQLite database
    /// - Parameters:
    ///   - xmlURL: URL of the XML file to parse
    ///   - outputURL: URL where the SQLite database should be saved
    ///   - overwrite: Whether to overwrite an existing database file
    /// - Throws: ParserError if any step of the process fails
    public func createDatabase(from xmlURL: URL, savingTo outputURL: URL, overwrite: Bool = false) async throws {
        // Check if output file exists and handle overwrite option
        if FileManager.default.fileExists(atPath: outputURL.path) {
            if overwrite {
                do {
                    try FileManager.default.removeItem(at: outputURL)
                } catch {
                    throw ParserError.databaseCreationFailed("Unable to overwrite existing file: \(error.localizedDescription)")
                }
            } else {
                throw ParserError.databaseCreationFailed("Output file already exists. Set overwrite to true to replace it.")
            }
        }
        
        // Parse the XML file
        let (mameInfo, machines) = try await parseXML(fileURL: xmlURL)
        
        // Create the database
        try await createDatabase(outputURL: outputURL, mameInfo: mameInfo, machines: machines)
    }
    
    // MARK: - Private Methods
    
    private func parseXML(fileURL: URL) async throws -> (mameInfo: (String, String, String)?, machines: [[String: Any]]) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ParserError.fileNotFound(fileURL)
        }
        
        do {
            // Read the XML file into a Data object
            let xmlData = try Data(contentsOf: fileURL)
            
            print("📄 Loading XML file: \(fileURL.path)")
            print("📁 File size: \(xmlData.count) bytes")
            
            // Create an XMLParser instance with the data
            let parser = XMLParser(data: xmlData)
            
            // Instantiate the delegate
            let delegate = MameXMLParserDelegate()
            parser.delegate = delegate
            
            // Parse the XML synchronously
            if parser.parse() {
                // Check if required mame attributes were found
                let mameInfo: (String, String, String)?
                if let build = delegate.build, let debug = delegate.debug, let mameconfig = delegate.mameconfig {
                    mameInfo = (build, debug, mameconfig)
                    print("✅ MAME attributes parsed successfully")
                } else {
                    mameInfo = nil
                    print("⚠️ MAME attributes not found")
                }
                
                // Report on machines found
                print("✅ Found \(delegate.machines.count) machine entries")
                
                // Count total ROMs
                var totalRoms = 0
                for machine in delegate.machines {
                    if let roms = machine["roms"] as? [[String: String]] {
                        totalRoms += roms.count
                    }
                }
                print("✅ Found \(totalRoms) ROM entries across all machines")
                
                return (mameInfo, delegate.machines)
            } else {
                let error = parser.parserError
                throw ParserError.xmlParsingFailed(error?.localizedDescription ?? "Unknown error")
            }
        } catch let error as ParserError {
            throw error
        } catch {
            throw ParserError.xmlParsingFailed(error.localizedDescription)
        }
    }
    
    private func createDatabase(outputURL: URL, mameInfo: (String, String, String)?, machines: [[String: Any]]) async throws {
        var db: OpaquePointer?
        
        if sqlite3_open(":memory:", &db) != SQLITE_OK {
            throw ParserError.databaseCreationFailed("Unable to create in-memory database: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        guard let db = db else {
            throw ParserError.databaseCreationFailed("SQLite pointer is nil")
        }
        
        // First identify all ROMs from BIOS and device machines
        var biosRoms = Set<String>()
        var deviceRoms = Set<String>()
        
        print("Identifying BIOS and device ROMs...")
        for machine in machines {
            guard let machineName = machine["name"] as? String else { continue }
            
            let isBiosMachine = (machine["isbios"] as? String) == "1"
            let isDeviceMachine = (machine["isdevice"] as? String) == "1"
            
            // If this is a BIOS or device machine, collect its ROMs
            if isBiosMachine || isDeviceMachine {
                if let roms = machine["roms"] as? [[String: String]] {
                    for rom in roms {
                        if let romName = rom["name"] {
                            if isBiosMachine {
                                biosRoms.insert(romName)
                            }
                            if isDeviceMachine {
                                deviceRoms.insert(romName)
                            }
                        }
                    }
                }
            }
        }
        
        print("Found \(biosRoms.count) BIOS ROMs and \(deviceRoms.count) device ROMs")
        
        // Main transaction for schema setup
        if sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) != SQLITE_OK {
            print("Warning: Failed to begin transaction: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        // Create the mame table
        try createMameTable(db: db)
        
        // Insert mame record if info available
        if let (build, debug, mameconfig) = mameInfo {
            try insertMameInfo(db: db, build: build, debug: debug, mameconfig: mameconfig)
        }
        
        // Create and populate the machine table
        try createMachineTable(db: db)
        
        // Insert machines and get their IDs
        print("Will insert \(machines.count) machines")
        let (machineIds, machineIdsByName) = try insertMachines(db: db, machines: machines)
        print("Have inserted \(machineIds.count) machines")
        
        // Create the ROM table and relationship table
        try createRomTable(db: db)
        try createMachineRomTable(db: db)
        
        // Insert ROMs and create relationships using the ROM categorization
        try insertRoms(db: db, machines: machines, machineIds: machineIds,
                     biosRoms: biosRoms, deviceRoms: deviceRoms)
        
        // Commit the schema and data insertion transaction
        if sqlite3_exec(db, "COMMIT;", nil, nil, nil) != SQLITE_OK {
            print("Warning: Failed to commit transaction: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
        }
        
        // Backup the in-memory database to a file
        var backupDb: OpaquePointer?
        if sqlite3_open(outputURL.path, &backupDb) == SQLITE_OK {
            print("Writing in-memory database to disk...")
            let backup = sqlite3_backup_init(backupDb, "main", db, "main")
            if backup != nil {
                let result = sqlite3_backup_step(backup, -1)
                if result != SQLITE_DONE {
                    print("Warning: Backup step returned \(result)")
                }
                sqlite3_backup_finish(backup)
                print("✅ Database backup completed")
            } else {
                throw ParserError.databaseCreationFailed("Failed to initialize backup: \(String(cString: sqlite3_errmsg(backupDb)))")
            }
            sqlite3_close(backupDb)
        } else {
            throw ParserError.databaseCreationFailed("Unable to open output file for backup: \(String(cString: sqlite3_errmsg(backupDb)))")
        }
        
        print("Database created at: \(outputURL.path)")
        
        sqlite3_close(db)
    }
    
    private func createMameTable(db: OpaquePointer) throws {
        let createTableQuery = """
        CREATE TABLE mame (
        mame_Id INTEGER PRIMARY KEY,
        build TEXT NULL,
        debug TEXT NULL,
        mameconfig TEXT NULL
        );
        """
        
        if sqlite3_exec(db, createTableQuery, nil, nil, nil) != SQLITE_OK {
            throw ParserError.tableCreationFailed("Failed to create mame table: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        print("✅ MAME table created successfully")
    }
    
    private func createMachineTable(db: OpaquePointer) throws {
        let createTableQuery = """
        CREATE TABLE machine (
            machine_Id INTEGER PRIMARY KEY,
            name TEXT NULL,
            description TEXT NULL,
            year TEXT NULL,
            manufacturer TEXT NULL,
            romof TEXT NULL,
            cloneof TEXT NULL,
            machine_type CHAR(1) NULL  -- 'b' for BIOS, 'd' for device, NULL for regular
        );
        """
        
        print("Creating machine table with query: \(createTableQuery)")
        
        let result = sqlite3_exec(db, createTableQuery, nil, nil, nil)
        if result != SQLITE_OK {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw ParserError.tableCreationFailed("Failed to create machine table: \(errorMsg)")
        }
        
        print("✅ Machine table created successfully")
    }
    
    private func createRomTable(db: OpaquePointer) throws {
        let createTableQuery = """
        CREATE TABLE rom (
            rom_Id INTEGER PRIMARY KEY,
            name TEXT NULL,
            size TEXT NULL,
            crc TEXT NULL,
            rom_type CHAR(1) NULL,  -- 'b' for BIOS, 'd' for device, NULL for regular
            UNIQUE(name, size, crc)
        );
        """
        
        // Enable foreign keys in SQLite
        if sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil) != SQLITE_OK {
            print("Warning: Failed to enable foreign keys: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        if sqlite3_exec(db, createTableQuery, nil, nil, nil) != SQLITE_OK {
            throw ParserError.tableCreationFailed("Failed to create rom table: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        print("✅ ROM table created successfully")
    }
    
    private func createMachineRomTable(db: OpaquePointer) throws {
        let createTableQuery = """
        CREATE TABLE machine_rom (
            machine_rom_id INTEGER PRIMARY KEY,
            machine_id INTEGER NOT NULL,
            rom_id INTEGER NOT NULL,
            merge TEXT NULL,
            CONSTRAINT FK_machine_rom_machine FOREIGN KEY (machine_id) REFERENCES machine (machine_Id),
            CONSTRAINT FK_machine_rom_rom FOREIGN KEY (rom_id) REFERENCES rom (rom_Id),
            CONSTRAINT UQ_machine_rom UNIQUE (machine_id, rom_id)
        );
        """
        
        if sqlite3_exec(db, createTableQuery, nil, nil, nil) != SQLITE_OK {
            throw ParserError.tableCreationFailed("Failed to create machine_rom table: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        print("✅ Machine-ROM relationship table created successfully")
    }
    
    private func insertMameInfo(db: OpaquePointer, build: String, debug: String, mameconfig: String) throws {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let insertQuery = "INSERT INTO mame (build, debug, mameconfig) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }
        
        if sqlite3_prepare_v2(db, insertQuery, -1, &stmt, nil) != SQLITE_OK {
            throw ParserError.dataInsertionFailed("Failed to prepare mame insert statement")
        }
        
        sqlite3_bind_text(stmt, 1, build, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, debug, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, mameconfig, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw ParserError.dataInsertionFailed("Failed to insert mame data: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        print("✅ MAME info inserted successfully")
    }
    
    private func insertMachines(db: OpaquePointer, machines: [[String: Any]]) throws -> ([Int: Int64], [String: Int64]) {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        // Updated query with machine_type
        let insertQuery = """
        INSERT INTO machine (name, description, year, manufacturer, romof, cloneof, machine_type)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        
        print("Preparing machine insert statement with query: \(insertQuery)")
        
        var stmt: OpaquePointer?
        var machineIds: [Int: Int64] = [:] // Maps index in original array to DB ID
        var machineIdsByName: [String: Int64] = [:] // Maps machine name to DB ID
        var successCount = 0
        
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }
        
        // Add detailed error logging for statement preparation
        let prepResult = sqlite3_prepare_v2(db, insertQuery, -1, &stmt, nil)
        if prepResult != SQLITE_OK {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            let errorCode = sqlite3_errcode(db)
            throw ParserError.dataInsertionFailed("Failed to prepare machine insert statement: Error \(errorCode) - \(errorMsg)")
        }
        
        // Begin a transaction for better performance
        if sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) != SQLITE_OK {
            print("Warning: Failed to begin transaction for machine inserts")
        }
        
        for (index, machine) in machines.enumerated() {
            // Skip machines that don't have any ROMs
            guard let roms = machine["roms"] as? [[String: String]], !roms.isEmpty else {
                continue
            }
            
            // Reset the statement for reuse
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            
            // Bind each parameter, handling nulls appropriately
            let bindText = { (index: Int32, key: String) -> Bool in
                if let value = machine[key] as? String {
                    let result = sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
                    if result != SQLITE_OK {
                        print("⚠️ Error binding \(key): \(String(cString: sqlite3_errmsg(db)))")
                        return false
                    }
                } else {
                    let result = sqlite3_bind_null(stmt, index)
                    if result != SQLITE_OK {
                        print("⚠️ Error binding NULL for \(key): \(String(cString: sqlite3_errmsg(db)))")
                        return false
                    }
                }
                return true
            }
            
            // Bind values
            guard bindText(1, "name") &&
                    bindText(2, "description") &&
                    bindText(3, "year") &&
                    bindText(4, "manufacturer") &&
                    bindText(5, "romof") &&
                    bindText(6, "cloneof") else {
                if let name = machine["name"] as? String {
                    print("  Skipping machine with binding error: \(name)")
                } else {
                    print("  Skipping machine with binding error (unnamed)")
                }
                continue
            }
            
            // Determine machine_type
            let isDevice = (machine["isdevice"] as? String) == "1"
            let isBios = (machine["isbios"] as? String) == "1"
            
            if isDevice {
                sqlite3_bind_text(stmt, 7, "d", -1, SQLITE_TRANSIENT)
            } else if isBios {
                sqlite3_bind_text(stmt, 7, "b", -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            
            if sqlite3_step(stmt) == SQLITE_DONE {
                // Store the machine's ID for ROM relationships
                let machineId = sqlite3_last_insert_rowid(db)
                machineIds[index] = machineId
                
                // Also store by name for device reference lookups
                if let name = machine["name"] as? String {
                    machineIdsByName[name] = machineId
                }
                
                successCount += 1
            } else {
                print("⚠️ Error inserting machine: \(String(cString: sqlite3_errmsg(db)))")
                if let name = machine["name"] as? String {
                    print("  Failed machine: \(name)")
                }
            }
        }
        
        // Commit the transaction
        if sqlite3_exec(db, "COMMIT;", nil, nil, nil) != SQLITE_OK {
            print("Warning: Failed to commit transaction for machine inserts")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
        }
        
        print("✅ Inserted \(successCount) of \(machines.count) machines")
        return (machineIds, machineIdsByName)
    }
    
    private func insertRoms(db: OpaquePointer, machines: [[String: Any]], machineIds: [Int: Int64],
                          biosRoms: Set<String>, deviceRoms: Set<String>) throws {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        // Preprocess all ROM data
        let (preprocessedRoms, relationships) = preprocessMachineData(machines)
        
        // Rom insert statement with type
        let insertRomQuery = """
        INSERT OR IGNORE INTO rom (rom_Id, name, size, crc, rom_type)
        VALUES (?, ?, ?, ?, ?);
        """
        
        // Machine-ROM relationship insert statement
        let insertMachineRomQuery = """
        INSERT OR IGNORE INTO machine_rom (machine_id, rom_id, merge)
        VALUES (?, ?, ?);
        """
        
        var romStmt: OpaquePointer?
        var machineRomStmt: OpaquePointer?
        
        defer {
            if romStmt != nil { sqlite3_finalize(romStmt) }
            if machineRomStmt != nil { sqlite3_finalize(machineRomStmt) }
        }
        
        // Prepare statements
        if sqlite3_prepare_v2(db, insertRomQuery, -1, &romStmt, nil) != SQLITE_OK {
            throw ParserError.dataInsertionFailed("Failed to prepare ROM insert statement")
        }
        
        if sqlite3_prepare_v2(db, insertMachineRomQuery, -1, &machineRomStmt, nil) != SQLITE_OK {
            throw ParserError.dataInsertionFailed("Failed to prepare machine_rom insert statement")
        }
        
        // Start a transaction for ROM inserts
        if sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) != SQLITE_OK {
            print("Warning: Failed to begin transaction for ROM inserts")
        }
        
        // Insert all unique ROMs
        print("Inserting \(preprocessedRoms.count) unique ROMs...")
        var romCount = 0
        
        for (key, (romId, romType)) in preprocessedRoms {
            let components = key.components(separatedBy: ":")
            guard components.count == 3 else { continue }
            
            let name = components[0]
            let size = components[1]
            let crc = components[2]
            
            sqlite3_reset(romStmt)
            sqlite3_clear_bindings(romStmt)
            
            sqlite3_bind_int64(romStmt, 1, romId)
            sqlite3_bind_text(romStmt, 2, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(romStmt, 3, size, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(romStmt, 4, crc, -1, SQLITE_TRANSIENT)
            
            if let type = romType {
                sqlite3_bind_text(romStmt, 5, type, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(romStmt, 5)
            }
            
            if sqlite3_step(romStmt) == SQLITE_DONE {
                romCount += 1
            }
            
            if romCount % 1000 == 0 {
                // print("  Inserted \(romCount) ROMs...")
            }
        }
        
        // Commit ROM transaction
        if sqlite3_exec(db, "COMMIT;", nil, nil, nil) != SQLITE_OK {
            print("Warning: Failed to commit ROM transaction")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
        }
        
        print("✅ Inserted \(romCount) unique ROMs")
        
        // Start transaction for relationships
        if sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) != SQLITE_OK {
            print("Warning: Failed to begin transaction for ROM relationships")
        }
        
        // Insert all machine-ROM relationships
        print("Inserting \(relationships.count) machine-ROM relationships...")
        var relationshipCount = 0
        
        // Create reverse mapping from indices to machineIds
        var indexToMachineId: [Int64: Int64] = [:]
        for (index, machineId) in machineIds {
            indexToMachineId[Int64(index)] = machineId
        }
        
        for (machineIndex, romId, merge) in relationships {
            // Convert preprocessed machine index to real machine ID
            guard let machineId = indexToMachineId[machineIndex] else { continue }
            
            sqlite3_reset(machineRomStmt)
            sqlite3_clear_bindings(machineRomStmt)
            
            sqlite3_bind_int64(machineRomStmt, 1, machineId)
            sqlite3_bind_int64(machineRomStmt, 2, romId)
            
            if let merge = merge {
                sqlite3_bind_text(machineRomStmt, 3, merge, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(machineRomStmt, 3)
            }
            
            if sqlite3_step(machineRomStmt) == SQLITE_DONE {
                relationshipCount += 1
            }
            
            if relationshipCount % 5000 == 0 {
                // print("  Inserted \(relationshipCount) relationships...")
            }
        }
        
        // Commit relationships transaction
        if sqlite3_exec(db, "COMMIT;", nil, nil, nil) != SQLITE_OK {
            print("Warning: Failed to commit relationships transaction")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
        }
        
        print("✅ Inserted \(relationshipCount) machine-ROM relationships")
    }
    
    private func preprocessMachineData(_ machines: [[String: Any]]) -> (
        romInfo: [String: (id: Int64, type: String?)],
        machineRomRelationships: [(machineIndex: Int64, romId: Int64, merge: String?)]
    ) {
        print("Preprocessing machine and ROM data...")
        
        // Build maps for faster lookups
        var machinesByName: [String: (index: Int, machine: [String: Any])] = [:]
        var deviceRelationships: [String: [String]] = [:]
        var machineRomInfo: [String: [(name: String, size: String, crc: String, merge: String?, bios: Bool)]] = [:]
        var biosRomNames: Set<String> = []
        var deviceRomNames: Set<String> = []
        
        // First pass: collect machine info and direct relationships
        for (index, machine) in machines.enumerated() {
            guard let name = machine["name"] as? String else { continue }
            
            machinesByName[name] = (index, machine)
            
            // Collect device references
            if let deviceRefs = machine["device_refs"] as? [String], !deviceRefs.isEmpty {
                deviceRelationships[name] = deviceRefs
            }
            
            // Collect ROMs for this machine
            if let roms = machine["roms"] as? [[String: String]], !roms.isEmpty {
                var machineRoms: [(name: String, size: String, crc: String, merge: String?, bios: Bool)] = []
                
                for rom in roms {
                    guard let romName = rom["name"],
                          let size = rom["size"],
                          let crc = rom["crc"] else { continue }
                    
                    let merge = rom["merge"]
                    let isBios = rom["bios"] != nil && !rom["bios"]!.isEmpty
                    
                    machineRoms.append((romName, size, crc, merge, isBios))
                    
                    // Track BIOS ROMs
                    if isBios {
                        biosRomNames.insert(romName)
                    }
                }
                
                // Only store if we have ROMs
                if !machineRoms.isEmpty {
                    machineRomInfo[name] = machineRoms
                }
            }
            
            // Mark all ROMs from device machines
            let isDevice = (machine["isdevice"] as? String) == "1"
            if isDevice, let roms = machine["roms"] as? [[String: String]] {
                for rom in roms {
                    if let romName = rom["name"] {
                        deviceRomNames.insert(romName)
                    }
                }
            }
        }
        
        // Build complete dependency graph (device closure)
        var allDeviceDependencies: [String: Set<String>] = [:]
        
        func collectDeviceDependencies(for machineName: String, visited: inout Set<String>) -> Set<String> {
            // Prevent cycles
            if visited.contains(machineName) {
                return []
            }
            visited.insert(machineName)
            
            // Return cached result if available
            if let existing = allDeviceDependencies[machineName] {
                return existing
            }
            
            var dependencies = Set<String>()
            
            // Add direct dependencies
            if let directDeps = deviceRelationships[machineName] {
                dependencies.formUnion(directDeps)
                
                // Add transitive dependencies
                for device in directDeps {
                    let deviceDeps = collectDeviceDependencies(for: device, visited: &visited)
                    dependencies.formUnion(deviceDeps)
                }
            }
            
            // Cache the result
            allDeviceDependencies[machineName] = dependencies
            return dependencies
        }
        
        // Compute all device dependencies
        for machineName in machinesByName.keys {
            var visited = Set<String>()
            _ = collectDeviceDependencies(for: machineName, visited: &visited)
        }
        
        print("Found \(allDeviceDependencies.count) machines with device dependencies")
        
        // Create unique ROM mapping
        var nextRomId: Int64 = 1
        var romInfo: [String: (id: Int64, type: String?)] = [:]  // Key: "name:size:crc"
        
        // Helper to get ROM key
        func romKey(_ name: String, _ size: String, _ crc: String) -> String {
            return "\(name):\(size):\(crc)"
        }
        
        // Helper to get ROM type
        func getRomType(name: String, isBios: Bool) -> String? {
            if isBios || biosRomNames.contains(name) {
                return "b"
            } else if deviceRomNames.contains(name) {
                return "d"
            }
            return nil
        }
        
        // Collect all unique ROMs
        for (_, roms) in machineRomInfo {
            for rom in roms {
                let key = romKey(rom.name, rom.size, rom.crc)
                if romInfo[key] == nil {
                    let type = getRomType(name: rom.name, isBios: rom.bios)
                    romInfo[key] = (nextRomId, type)
                    nextRomId += 1
                }
            }
        }
        
        print("Found \(romInfo.count) unique ROMs")
        
        // Generate machine-ROM relationships
        var machineRomRelationships: [(machineIndex: Int64, romId: Int64, merge: String?)] = []
        
        for (machineName, (index, _)) in machinesByName {
            // Use the index as machineIndex
            let machineIndex = Int64(index)
            
            // Skip if no ROMs for this machine
            guard let roms = machineRomInfo[machineName] else { continue }
            
            // Add direct ROMs
            for rom in roms {
                let key = romKey(rom.name, rom.size, rom.crc)
                if let (romId, _) = romInfo[key] {
                    machineRomRelationships.append((machineIndex, romId, rom.merge))
                }
            }
            
            // Add device ROMs from dependencies
            if let deviceDeps = allDeviceDependencies[machineName] {
                for deviceName in deviceDeps {
                    if let deviceRoms = machineRomInfo[deviceName] {
                        for rom in deviceRoms {
                            let key = romKey(rom.name, rom.size, rom.crc)
                            if let (romId, _) = romInfo[key] {
                                // No merge for device ROMs
                                machineRomRelationships.append((machineIndex, romId, nil))
                            }
                        }
                    }
                }
            }
        }
        
        print("Generated \(machineRomRelationships.count) machine-ROM relationships")
        
        return (romInfo, machineRomRelationships)
    }
    
}

// MARK: - XML Parser Delegate

/// Delegate for parsing MAME XML data
private class MameXMLParserDelegate: NSObject, XMLParserDelegate {
    var build: String?
    var debug: String?
    var mameconfig: String?
    
    // For machine elements
    var machines: [[String: Any]] = []
    var currentMachine: [String: Any]?
    var currentElement: String?
    var currentElementContent: String?
    var currentRoms: [[String: String]] = []
    var currentDeviceRefs: [String] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
        if elementName == "mame" {
            build = attributeDict["build"]
            debug = attributeDict["debug"]
            mameconfig = attributeDict["mameconfig"]
        } else if elementName == "machine" {
            // Start collecting a new machine
            currentMachine = [:]
            currentRoms = []
            currentDeviceRefs = []
            
            // Extract attributes
            if let name = attributeDict["name"] {
                currentMachine?["name"] = name
            }
            if let cloneof = attributeDict["cloneof"] {
                currentMachine?["cloneof"] = cloneof
            }
            if let romof = attributeDict["romof"] {
                currentMachine?["romof"] = romof
            }
            // Capture isDevice attribute
            if let isDevice = attributeDict["isdevice"] {
                currentMachine?["isdevice"] = (isDevice.lowercased() == "yes") ? "1" : "0"
            } else {
                currentMachine?["isdevice"] = "0"  // Default value
            }
            // Capture isBios attribute
            if let isBios = attributeDict["isbios"] {
                currentMachine?["isbios"] = (isBios.lowercased() == "yes") ? "1" : "0"
            } else {
                currentMachine?["isbios"] = "0"  // Default value
            }
        } else if elementName == "rom" && currentMachine != nil {
            // Collect ROM information
            var romInfo: [String: String] = [:]
            
            if let name = attributeDict["name"] {
                romInfo["name"] = name
            }
            if let merge = attributeDict["merge"] {
                romInfo["merge"] = merge
            }
            if let size = attributeDict["size"] {
                romInfo["size"] = size
            }
            if let crc = attributeDict["crc"] {
                romInfo["crc"] = crc
            }
            // Capture bios attribute
            if let bios = attributeDict["bios"] {
                romInfo["bios"] = bios
            }
            
            if !romInfo.isEmpty {
                currentRoms.append(romInfo)
            }
        } else if elementName == "device_ref" && currentMachine != nil {
            // Capture device references
            if let name = attributeDict["name"] {
                currentDeviceRefs.append(name)
            }
        } else if currentMachine != nil {
            // We're within a machine element, keep track of the current element
            currentElement = elementName
            currentElementContent = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // Append content for the current element within a machine
        if currentMachine != nil && currentElement != nil {
            currentElementContent? += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "machine" {
            // Add the ROM collection to the machine
            if !currentRoms.isEmpty {
                currentMachine?["roms"] = currentRoms
            }
            
            // Add device references to the machine
            if !currentDeviceRefs.isEmpty {
                currentMachine?["device_refs"] = currentDeviceRefs
            }
            
            // Add the completed machine to our collection
            if let machine = currentMachine {
                machines.append(machine)
            }
            currentMachine = nil
            currentRoms = []
            currentDeviceRefs = []
        } else if currentMachine != nil && elementName == currentElement {
            // Save the element's content to the current machine
            if let content = currentElementContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty,
               let element = currentElement {
                currentMachine?[element] = content
            }
            currentElement = nil
            currentElementContent = nil
        }
    }
}

/// Extension to MameDBManager to add XML parsing functionality
extension MameDBManager {
    /// Creates a new database from a MAME XML file
    /// - Parameters:
    ///   - xmlURL: URL of the XML file to parse
    ///   - outputURL: URL where the SQLite database should be saved
    ///   - overwrite: Whether to overwrite an existing database file
    /// - Returns: A new MameDBManager instance initialized with the created database
    public static func createDatabase(from xmlURL: URL, savingTo outputURL: URL, overwrite: Bool = false) async throws -> MameDBManager {
        // Parse and create the database
        try await MAMEXMLParser.shared.createDatabase(from: xmlURL, savingTo: outputURL, overwrite: overwrite)
        
        // Create and initialize a new MameDBManager with the new database
        let manager = MameDBManager()
        let success = await manager.initialize(databasePath: outputURL.path)
        
        if success {
            return manager
        } else {
            throw MAMEXMLParser.ParserError.databaseCreationFailed("Failed to initialize MameDBManager with the new database")
        }
    }
}
