/// Manager for MAME database operations with actor-based concurrency
import Foundation
import SQLite3

public actor MameDBManager {
    @MainActor static var instanceCache: [String: MameDBManager] = [:]
    
    @MainActor
    public static func getInstanceCacheFirstValue() async -> MameDBManager? {
        return instanceCache.values.first
    }
    
    @MainActor
    public static func forDatabase(at path: String) async -> MameDBManager? {
        // Create a new instance and initialize it
        let manager = MameDBManager()
        let success = await manager.initialize(databasePath: path)
        
        if success {
            // Cache and return the new instance
            instanceCache[path] = manager
            return manager
        } else {
            return nil
        }
    }
    
    /// Initialize the database manager with a specific database file path
    /// - Parameter databasePath: Path to the SQLite database file
    /// - Returns: Whether the initialization was successful
    @discardableResult
    public func initialize(databasePath: String) async -> Bool {
        print("🔄 Initializing MameDBManager with database: \(databasePath)")
        
        await dbActor.closeDB()
        
        guard FileManager.default.fileExists(atPath: databasePath) else {
            print("⚠️ Database file not found at path: \(databasePath)")
            return false
        }
        
        var db: OpaquePointer?
        if sqlite3_open(databasePath, &db) == SQLITE_OK {
            await dbActor.setDB(db)
            print("📀 Opened MAME database from: \(databasePath)")
            
            // Extract version from database after successful open
            do {
                self.version = try await getMameVersion()
                print("📊 Database version: \(self.version ?? "unknown")")
            } catch {
                print("⚠️ Unable to determine database version: \(error.localizedDescription)")
            }
            
            return true
        } else {
            print("⚠️ Failed to open database at path: \(databasePath)")
            return false
        }
    }
    
    // Use DatabaseActor instead of direct database access
    private let dbActor = DatabaseActor()
    private var version: String?
    
    public init() {}
    
    deinit {
        let actorRef = dbActor
        Task {
            await actorRef.closeDB()
        }
    }
    
    public func getMameVersion() async throws -> String {
        return try await dbActor.perform { db in
            let queryString = "SELECT build FROM mame LIMIT 0,1"
            
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }
            
            guard sqlite3_prepare_v2(db, queryString, -1, &stmt, nil) == SQLITE_OK else {
                throw DBError.queryPreparationFailed
            }
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return String(cString: sqlite3_column_text(stmt, 0))
            }
            
            return "unknown"
        }
    }
    
    /// ROM source type for tracking provenance
    public enum RomSource: String, Codable, Sendable {
        case machine        // From the requested machine
        case parent         // From the parent machine
        case clone          // From a clone of the parent
        case device         // From a device
        case bios           // BIOS ROM
    }

    /// A ROM with full metadata for set processing
    public struct RomWithMetadata : Sendable{
        public let rom: RomInfo
        public let source: RomSource
        public let machineId: Int64
        public let machineName: String
        public let replaces: String?     // ROM name this replaces (if merge attribute exists)
        public let replacedBy: [String]  // ROMs that replace this one (computed)
    }
    
    // Core data structure to hold all machine and ROM information
    public struct MachineData: Sendable {
        public let machine: MachineInfo
        public let parent: MachineInfo?
        public let allRoms: [RomWithMetadata]
        
        // Derived properties
        public var directRoms: [RomWithMetadata] {
            allRoms.filter { $0.source == .machine }
        }
        
        public var parentRoms: [RomWithMetadata] {
            allRoms.filter { $0.source == .parent }
        }
        
       public  var deviceRoms: [RomWithMetadata] {
            allRoms.filter { $0.source == .device }
        }
        
        public var biosRoms: [RomWithMetadata] {
            allRoms.filter { $0.source == .bios }
        }
    }
    
    // Refactored ROM set functions
    public static func getRomSet(type: SetType, from data: MachineData) -> [RomInfo] {
        switch type {
        case .split:
            return getSplitSetRoms(from: data)
        case .merged:
            return getMergedSetRoms(from: data)
        case .nonmerged:
            return getNonMergedSetRoms(from: data)
        case .mergedplus:
            return getMergedPlusSetRoms(from: data)
        case .mergedfull:
            return getMergedFullSetRoms(from: data)
        case .nonmergedplus:
            return getNonMergedPlusSetRoms(from: data)
        case .nonmergedfull:
            return getNonMergedFullSetRoms(from: data)
        }
    }

    private static func deduplicateRoms(_ roms: [RomWithMetadata], allowedSources: [RomSource], includeReplaced: Bool = false) -> [RomInfo] {
        // Keep track of ROMs we've already added
        var seenRoms = Set<String>()
        var result: [RomInfo] = []
        
        for romWithMeta in roms {
            // Skip if not the right type or if replaced (when configured)
            guard allowedSources.contains(romWithMeta.source) &&
                  (includeReplaced || romWithMeta.replacedBy.isEmpty) else {
                continue
            }
            
            // Create a unique key for each ROM
            let uniqueKey = "\(romWithMeta.rom.name)_\(romWithMeta.rom.crc)"
            
            // Only add if we haven't seen this ROM before
            if !seenRoms.contains(uniqueKey) {
                seenRoms.insert(uniqueKey)
                result.append(romWithMeta.rom)
            }
        }
        
        return result
    }

    public static func getSplitSetRoms(from data: MachineData) -> [RomInfo] {
        let isClone = data.machine.cloneof != nil
        
        if isClone {
            // For clone split sets, exclude ROMs that appear in the parent
            let parentRomNames = Set(data.parentRoms.map { $0.rom.name })
            
            return data.directRoms
                .filter { !parentRomNames.contains($0.rom.name) }
                .map { $0.rom }
        } else {
            // For parent split sets, only include direct ROMs
            return data.directRoms.map { $0.rom }
        }
    }

    public static func getMergedSetRoms(from data: MachineData) -> [RomInfo] {
        return deduplicateRoms(
            data.allRoms,
            allowedSources: [.machine, .parent, .clone]
        )
    }

    public static func getMergedPlusSetRoms(from data: MachineData) -> [RomInfo] {
        return deduplicateRoms(
            data.allRoms,
            allowedSources: [.machine, .parent, .clone, .device]
        )
    }

    public static func getMergedFullSetRoms(from data: MachineData) -> [RomInfo] {
        return deduplicateRoms(
            data.allRoms,
            allowedSources: [.machine, .parent, .clone, .device, .bios]
        )
    }

    public static func getNonMergedSetRoms(from data: MachineData) -> [RomInfo] {
        let isClone = data.machine.cloneof != nil
        
        // Start with all machine ROMs
        var result = data.directRoms.map { $0.rom }
        
        if isClone {
            // For clones, add parent ROMs not replaced by the clone
            let replacedParentRoms = data.directRoms
                .filter { $0.replaces != nil }
                .compactMap { $0.replaces }
            
            let parentRoms = data.parentRoms
                .filter {
                    !replacedParentRoms.contains($0.rom.name) &&
                    $0.replacedBy.isEmpty
                }
                .map { $0.rom }
            
            result.append(contentsOf: parentRoms)
        }
        
        return result
    }

    public static func getNonMergedPlusSetRoms(from data: MachineData) -> [RomInfo] {
        // Start with non-merged set
        var result = getNonMergedSetRoms(from: data)
        
        // Add device ROMs
        let deviceRoms = deduplicateRoms(
            data.deviceRoms,
            allowedSources: [.device]
        )
        
        result.append(contentsOf: deviceRoms)
        return result
    }

    public static func getNonMergedFullSetRoms(from data: MachineData) -> [RomInfo] {
        // Start with non-merged plus devices
        var result = getNonMergedPlusSetRoms(from: data)
        
        // Add BIOS ROMs
        let biosRoms = deduplicateRoms(
            data.biosRoms,
            allowedSources: [.bios]
        )
        
        result.append(contentsOf: biosRoms)
        return result
    }
    
    public func loadAllMachines() async throws -> [MachineInfo] {
        return try await dbActor.perform { db in
            let queryString = """
                SELECT m.description, m.name, m.year, m.manufacturer, 
                       m.cloneof, m.romof,
                       p.name as parent_name, p.year as parent_year
                FROM machine m
                LEFT JOIN machine p ON m.cloneof = p.name
                """
            
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }
            
            guard sqlite3_prepare_v2(db, queryString, -1, &stmt, nil) == SQLITE_OK else {
                throw DBError.queryPreparationFailed
            }
            
            var machines: [MachineInfo] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let machine = MachineInfo(
                    description: String(cString: sqlite3_column_text(stmt, 0)),
                    name: String(cString: sqlite3_column_text(stmt, 1)),
                    year: sqlite3_column_type(stmt, 2) != SQLITE_NULL ?
                    String(cString: sqlite3_column_text(stmt, 2)) : "",
                    manufacturer: sqlite3_column_type(stmt, 3) != SQLITE_NULL ?
                    String(cString: sqlite3_column_text(stmt, 3)) : "",
                    cloneof: sqlite3_column_type(stmt, 4) != SQLITE_NULL ?
                    String(cString: sqlite3_column_text(stmt, 4)) : nil,
                    parent_name: sqlite3_column_type(stmt, 6) != SQLITE_NULL ?
                    String(cString: sqlite3_column_text(stmt, 6)) : nil,
                    parent_year: sqlite3_column_type(stmt, 7) != SQLITE_NULL ?
                    String(cString: sqlite3_column_text(stmt, 7)) : nil
                )
                machines.append(machine)
            }
            
            print("📊 Loaded \(machines.count) machines from database")
            return machines
        }
    }

    // Single comprehensive data loading function
    public func loadGameDetails(for gameId: String) async throws -> MachineData {
        return try await dbActor.perform { db in
            // Get target machine, parent, and related machine IDs in one query
            let machineQuery = """
            SELECT 
                m.machine_id, m.name, m.description, m.year, m.manufacturer, m.cloneof, m.machine_type,
                p.machine_id as parent_id, p.name as parent_name, p.description as parent_desc, 
                p.year as parent_year, p.manufacturer as parent_manuf,
                GROUP_CONCAT(c.machine_id) as child_ids,
                GROUP_CONCAT(s.machine_id) as sibling_ids
            FROM machine m
            LEFT JOIN machine p ON m.cloneof = p.name
            LEFT JOIN machine c ON c.cloneof = m.name
            LEFT JOIN (
                SELECT * FROM machine 
                WHERE cloneof IN (SELECT cloneof FROM machine WHERE name = ?)
                AND name != ?
            ) s ON 1=1
            WHERE m.name = ?
            GROUP BY m.machine_id
            """
            
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }
            
            guard sqlite3_prepare_v2(db, machineQuery, -1, &stmt, nil) == SQLITE_OK else {
                throw DBError.queryPreparationFailed
            }
            
            // Bind the game ID to parameters
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for i in 1...3 {
                if sqlite3_bind_text(stmt, Int32(i), gameId, -1, SQLITE_TRANSIENT) != SQLITE_OK {
                    throw DBError.queryPreparationFailed
                }
            }
            
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                throw DBError.recordNotFound
            }
            
            // Extract machine info
            let machineId = sqlite3_column_int64(stmt, 0)
            let machine = MachineInfo(
                description: String(cString: sqlite3_column_text(stmt, 2)),
                name: String(cString: sqlite3_column_text(stmt, 1)),
                year: sqlite3_column_type(stmt, 3) != SQLITE_NULL ?
                    String(cString: sqlite3_column_text(stmt, 3)) : "",
                manufacturer: sqlite3_column_type(stmt, 4) != SQLITE_NULL ?
                    String(cString: sqlite3_column_text(stmt, 4)) : "",
                cloneof: sqlite3_column_type(stmt, 5) != SQLITE_NULL ?
                    String(cString: sqlite3_column_text(stmt, 5)) : nil,
                parent_name: sqlite3_column_type(stmt, 8) != SQLITE_NULL ?
                    String(cString: sqlite3_column_text(stmt, 8)) : nil,
                parent_year: sqlite3_column_type(stmt, 10) != SQLITE_NULL ?
                    String(cString: sqlite3_column_text(stmt, 10)) : nil
            )
            
            // Extract parent info if available
            var parent: MachineInfo? = nil
            var parentId: Int64? = nil
            
            if sqlite3_column_type(stmt, 7) != SQLITE_NULL {
                parentId = sqlite3_column_int64(stmt, 7)
                parent = MachineInfo(
                    description: sqlite3_column_type(stmt, 9) != SQLITE_NULL ?
                        String(cString: sqlite3_column_text(stmt, 9)) : "",
                    name: String(cString: sqlite3_column_text(stmt, 8)),
                    year: sqlite3_column_type(stmt, 10) != SQLITE_NULL ?
                        String(cString: sqlite3_column_text(stmt, 10)) : "",
                    manufacturer: sqlite3_column_type(stmt, 11) != SQLITE_NULL ?
                        String(cString: sqlite3_column_text(stmt, 11)) : "",
                    cloneof: nil,
                    parent_name: nil,
                    parent_year: nil
                )
            }
            
            // Collect all machine IDs to query ROMs
            var machineIds = [machineId]
            if let parentId = parentId {
                machineIds.append(parentId)
            }
            
            // Add child IDs
            if sqlite3_column_type(stmt, 12) != SQLITE_NULL {
                let childIds = String(cString: sqlite3_column_text(stmt, 12)).split(separator: ",")
                for childId in childIds {
                    if let id = Int64(childId) {
                        machineIds.append(id)
                    }
                }
            }
            
            // Add sibling IDs
            if sqlite3_column_type(stmt, 13) != SQLITE_NULL {
                let siblingIds = String(cString: sqlite3_column_text(stmt, 13)).split(separator: ",")
                for siblingId in siblingIds {
                    if let id = Int64(siblingId) {
                        machineIds.append(id)
                    }
                }
            }
            
            // Now get all ROMs for all machines in a single query
            let machineIdsString = machineIds.map { String($0) }.joined(separator: ",")
            
            let romQuery = """
            SELECT 
                case r.rom_type
                when 'd' then 'DEV'
                when 'b' then 'BIOS'
                else 'ROM' 
                END romtype,
                m.machine_id,
                m.name as machine_name,
                r.rom_id,
                r.name as rom_name,
                r.size,
                r.crc,
                mr.merge as replaces
            ,MIN(m.machine_id) as machine_id, MIN(m.name) as machine_name
            FROM machine m
            JOIN machine_rom mr ON m.machine_id = mr.machine_id
            JOIN rom r ON mr.rom_id = r.rom_id
            WHERE m.machine_id IN (\(machineIdsString))
            GROUP BY r.rom_id
            """
            
            var romStmt: OpaquePointer?
            defer { if romStmt != nil { sqlite3_finalize(romStmt) } }
            
            guard sqlite3_prepare_v2(db, romQuery, -1, &romStmt, nil) == SQLITE_OK else {
                throw DBError.queryPreparationFailed
            }
            
            // Process ROM results
            var romResults: [RomWithMetadata] = []
            
            while sqlite3_step(romStmt) == SQLITE_ROW {
                let romTypeStr = String(cString: sqlite3_column_text(romStmt, 0))
                let romMachineId = sqlite3_column_int64(romStmt, 1)
                let machineName = String(cString: sqlite3_column_text(romStmt, 2))
                let romName = String(cString: sqlite3_column_text(romStmt, 4))
                let size = sqlite3_column_int64(romStmt, 5)
                let crc = String(cString: sqlite3_column_text(romStmt, 6))
                let replaces = sqlite3_column_type(romStmt, 7) != SQLITE_NULL ?
                    String(cString: sqlite3_column_text(romStmt, 7)) : nil
                
                // Determine ROM type and source
                let romType: RomInfo.RomType
                let source: RomSource
                
                switch romTypeStr {
                case "BIOS":
                    source = .bios
                    romType = .biosRom
                case "DEV":
                    source = .device
                    romType = .deviceRom
                case "ROM":
                    if romMachineId == machineId {
                        source = .machine
                        romType = parent != nil ? .cloneRom : .gameRom
                    } else if parent != nil && romMachineId == sqlite3_column_int64(stmt, 7) {
                        source = .parent
                        romType = .gameRom
                    } else {
                        source = .clone
                        romType = .cloneRom
                    }
                default:
                    source = .machine
                    romType = .gameRom
                }
                
                // Create ROM info
                let rom = RomInfo(
                    name: romName,
                    size: size,
                    crc: crc,
                    status: nil,
                    merge: replaces,
                    type: romType
                )
                
                // Add to results
                romResults.append(RomWithMetadata(
                    rom: rom,
                    source: source,
                    machineId: romMachineId,
                    machineName: machineName,
                    replaces: replaces,
                    replacedBy: []
                ))
            }
            
            // Compute replacement relationships
            romResults = MameDBManager.computeReplacementRelationships(romResults)
            
            return MachineData(
                machine: machine,
                parent: parent,
                allRoms: romResults
            )
        }
    }
    
    private static func computeReplacementRelationships(_ roms: [RomWithMetadata]) -> [RomWithMetadata] {
        var romsByName: [String: Int] = [:]
        var result = roms
        
        // First index ROMs by name
        for (index, rom) in roms.enumerated() {
            romsByName[rom.rom.name] = index
        }
        
        // Now identify ROMs that are replaced
        for (index, rom) in roms.enumerated() {
            if let replaces = rom.replaces, let replacedIndex = romsByName[replaces] {
                var replacedBy = result[replacedIndex].replacedBy
                replacedBy.append(rom.rom.name)
                result[replacedIndex] = RomWithMetadata(
                    rom: result[replacedIndex].rom,
                    source: result[replacedIndex].source,
                    machineId: result[replacedIndex].machineId,
                    machineName: result[replacedIndex].machineName,
                    replaces: result[replacedIndex].replaces,
                    replacedBy: replacedBy
                )
            }
        }
        
        return result
    }
    // Helper function to compute which ROMs replace others

    public func findMachineWithCRCs(_ crcs: [String]) async throws -> Int? {
        return try await dbActor.perform { db in
            // Control query to verify database connection
            do {
                var controlStmt: OpaquePointer?
                defer { if controlStmt != nil { sqlite3_finalize(controlStmt) } }
                
                let controlQuery = "SELECT COUNT(*) FROM rom LIMIT 1"
                
                guard sqlite3_prepare_v2(db, controlQuery, -1, &controlStmt, nil) == SQLITE_OK else {
                    print("❌ Control query preparation failed")
                    throw DBError.queryPreparationFailed
                }
                
                let controlStep = sqlite3_step(controlStmt)
                print("📊 Control query status:")
                print("   Step result: \(controlStep)")
                if controlStep == SQLITE_ROW {
                    let count = sqlite3_column_int64(controlStmt, 0)
                    print("   ROM table has \(count) total rows")
                } else {
                    print("❌ Control query failed to return data")
                    print("   SQLite error: \(String(cString: sqlite3_errmsg(db)))")
                    throw DBError.queryPreparationFailed
                }
            }
            
            let placeholders = String(repeating: "?,", count: crcs.count).dropLast()
            
            // Updated query to work with the new schema
            let queryString = """
                SELECT mr.machine_id, COUNT(*) as match_count
                FROM machine_rom mr
                JOIN rom r ON mr.rom_id = r.rom_Id
                WHERE UPPER(r.crc) IN (\(placeholders))
                GROUP BY mr.machine_id
                HAVING match_count = ?
                """
            
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }
            
            guard sqlite3_prepare_v2(db, queryString, -1, &stmt, nil) == SQLITE_OK else {
                print("❌ Failed to prepare query")
                throw DBError.queryPreparationFailed
            }
            
            // Bind with explicit UTF8 conversion
            for (index, crc) in crcs.enumerated() {
                guard let cString = crc.cString(using: .utf8) else {
                    print("❌ Failed to convert CRC to UTF8: \(crc)")
                    throw DBError.queryPreparationFailed
                }
                
                let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                
                let bindResult = sqlite3_bind_text(
                    stmt,
                    Int32(index + 1),
                    cString,
                    -1,
                    SQLITE_TRANSIENT
                )
                
                if bindResult != SQLITE_OK {
                    throw DBError.queryPreparationFailed
                }
            }
            
            // Calculate the parameter index for count (after all CRCs)
            let countParamIndex = Int32(crcs.count + 1)
            let expectedCount = Int32(crcs.count)
            
            let bindResult = sqlite3_bind_int(stmt, countParamIndex, expectedCount)
            if bindResult != SQLITE_OK {
                throw DBError.queryPreparationFailed
            }
            
            // Execute and log result
            var rowCount = 0
            var firstMatch: Int? = nil
            while true {
                let stepResult = sqlite3_step(stmt)
                
                if stepResult == SQLITE_ROW {
                    let machineId = sqlite3_column_int(stmt, 0)
                    _ = sqlite3_column_int(stmt, 1)
                    rowCount += 1
                    
                    // Store first match (we expect only one anyway)
                    if rowCount == 1 {
                        firstMatch = Int(machineId)
                    }
                } else if stepResult == SQLITE_DONE {
                    break
                } else {
                    break
                }
            }
            
            // Return first match if found
            if rowCount > 0 {
                return firstMatch
            } else {
                // No match found
                return nil
            }
        }
    }
    
    public func getGameNameForMachine(_ machineId: Int) async throws -> String? {
        return try await dbActor.perform { db in
            let queryString = """
                SELECT name
                FROM machine 
                WHERE machine_id = ?
            """
            
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }
            
            guard sqlite3_prepare_v2(db, queryString, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_bind_int(stmt, 1, Int32(machineId)) == SQLITE_OK else {
                throw DBError.queryPreparationFailed
            }
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return String(cString: sqlite3_column_text(stmt, 0))
            }
            
            return nil
        }
    }
    
}

/// Error types for database operations
public enum DBError: LocalizedError, Sendable {
    /// Failed to prepare a database query
    case queryPreparationFailed
    
    /// Record not found in database
    case recordNotFound
    
    /// Reached the recursion limit for device loading
    case deviceRecursionLimit
    
    /// Database not initialized or connection failed
    case databaseNotInitialized
    
    /// Failed database operation
    case operationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .queryPreparationFailed:
            return "Failed to prepare database query"
        case .recordNotFound:
            return "Record not found in database"
        case .deviceRecursionLimit:
            return "Device recursion limit reached"
        case .databaseNotInitialized:
            return "Database not initialized"
        case .operationFailed(let message):
            return "Database operation failed: \(message)"
        }
    }
}
