import Foundation

/// Manager for handling the master list of MAME games
public actor MasterListManager {
    /// Shared instance
    public static let shared = MasterListManager()

    /// Cache of master lists by version
    private var masterLists: [String: [MameGame]] = [:]


    /// Initializes a new MasterListManager
    private init() {}
    
    /// Gets or loads the master list for a specific database version
    /// - Parameter version: The database version
    /// - Returns: Array of MameGame objects
    /// - Throws: Error if the master list cannot be loaded
    public func getMasterList(for version: String, databasePath: String? = nil) async throws -> [MameGame] {
        // Check if we already have the master list cached
        if let cached = masterLists[version] {
            return cached
        }
        
        // Load the master list
        let dbManager: MameDBManager
        if let path = databasePath {
            // This should be an await
            guard let manager = await MameDBManager.forDatabase(at: path) else {
                throw DBError.databaseNotInitialized
            }
            dbManager = manager
        } else {
            // Try to use an already initialized manager
            guard let manager = await MameDBManager.getInstanceCacheFirstValue() else {
                throw DBError.databaseNotInitialized
            }
            dbManager = manager
        }

        let machineData = try await dbManager.loadAllMachines()

        // Convert to MameGame objects
        let baseGames = machineData.map { machine in
            MameGame(
                name: machine.name,
                description: machine.description,
                year: machine.year,
                manufacturer: machine.manufacturer,
                roms: [],  // Will be populated later when needed
                languages: [],
                parent: machine.cloneof,
                source: .noFile
            )
        }

        // Enrich with metadata
        let enrichedGames = try await enrichWithMetadata(baseGames)
        
        // Cache and return
        masterLists[version] = enrichedGames
        
        return enrichedGames
    }
    
    /// Enriches games with metadata
    /// - Parameter games: Base games to enrich
    /// - Returns: Enriched games
    /// - Throws: Error if enrichment fails
    private func enrichWithMetadata(_ games: [MameGame]) async throws -> [MameGame] {
        // Load metadata files
        let languages = try ResourceLoader.loadResource(name: "languages", extension: "ini")
        let categories = try ResourceLoader.loadResource(name: "catlist", extension: "ini")
        let bestgames = try ResourceLoader.loadResource(name: "bestgames", extension: "ini")
        
        // Parse metadata
        let gameLanguages = MameLanguageParser.parse(languages)
        let gameCategories = CategoryParser.parse(categories)
        
        // Apply metadata
        var gamesWithMetadata = games
        
        for (index, game) in games.enumerated() {
            // Add languages
            if let langs = gameLanguages[game.name] {
                gamesWithMetadata[index] = MameGame(
                    name: game.name,
                    description: game.description,
                    year: game.year,
                    manufacturer: game.manufacturer,
                    roms: game.roms,
                    languages: langs,
                    parent: game.parent,
                    source: game.source
                )
            }
            
            // Add category
            if let category = gameCategories[game.name] {
                gamesWithMetadata[index] = MameGame(
                    name: game.name,
                    description: game.description,
                    year: game.year,
                    manufacturer: game.manufacturer,
                    roms: game.roms,
                    languages: gamesWithMetadata[index].languages,
                    machineType: category.machineType,
                    category: category.category,
                    subcategory: category.subcategory,
                    isMature: category.isMature,
                    parent: game.parent,
                    source: game.source
                )
            }
        }
        
        // Apply ratings
        var parser = MAMEIniParser(content: bestgames)
        try parser.parse()
        
        var ratedGames = gamesWithMetadata
        
        for (index, game) in gamesWithMetadata.enumerated() {
            if let section = parser.supportedGames[game.name] {
                ratedGames[index] = MameGame(
                    name: game.name,
                    description: game.description,
                    year: game.year,
                    manufacturer: game.manufacturer,
                    roms: game.roms,
                    gameRating: MameGame.GameRating(
                        score: section.starRating,
                        section: section.name
                    ),
                    languages: game.languages,
                    machineType: game.machineType,
                    category: game.category,
                    subcategory: game.subcategory,
                    isMature: game.isMature,
                    parent: game.parent,
                    source: game.source
                )
            }
        }
        
        return ratedGames
    }
}
