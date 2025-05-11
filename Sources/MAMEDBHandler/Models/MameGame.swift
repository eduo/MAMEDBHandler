import Foundation

/// Type of ROM set
public enum SetType: String, Sendable {
    /// Just this game's ROMs
    case split
    
    /// This game plus parent/clone ROMs
    case merged
    
    /// This game's ROMs'
    case nonmerged
    
    /// This game plus parent/clone ROMs plus device ROMs
    case mergedplus

    /// This game plus parent/clone ROMs plus device ROMs plus BIOS ROMs
    case mergedfull

    /// This game plus device ROMs
    case nonmergedplus

    /// This game plus device ROMs plus BIOS ROMs
    case nonmergedfull
}

/// Represents a MAME game with its metadata and ROM information
public struct MameGame: Identifiable, Hashable, Codable, Sendable {
    public var id: String { name }
    
    /// Name/ID of the game
    public let name: String
    
    /// Description of the game
    public let description: String
    
    /// Year the game was released
    public let year: String
    
    /// Manufacturer of the game
    public let manufacturer: String
    
    /// ROMs associated with this game
    public var roms: [RomInfo]
    
    /// Optional rating information
    public let gameRating: GameRating?
    
    /// Languages supported by the game
    public let languages: [String]
    
    /// Type of machine (e.g. "Arcade")
    public let machineType: String?
    
    /// Primary category of the game
    public let category: String?
    
    /// Subcategory for more specific classification
    public let subcategory: String?
    
    /// Whether the game contains mature content
    public let isMature: Bool
    
    /// Short title of the game
    public let shortTitle: String?
    
    /// Source information about how the game was matched
    public var source: GameSource
    
    /// Parent game ID if this is a clone
    public var parent: String?
    
    /// Special lists this game belongs to
    public let specialLists: Set<String>
    
    /// ID of a matching game if this game's name doesn't match but contents do
    public let matchedGameId: String?
    
    /// Verification status of the game's ROM files
    public var verificationStatus: VerificationResult?
    
    /// The type of ROM set
    public var setType: SetType?
    
    /// Rating information for a game
    public struct GameRating: Hashable, Codable, Sendable {
        /// Score on a scale from 1.0 to 5.0
        public let score: Double
        
        /// Original section name from the rating file
        public let section: String
        
        enum CodingKeys: String, CodingKey {
            case score
            case section
        }
        
        /// Creates a new game rating
        /// - Parameters:
        ///   - score: Score on a scale from 1.0 to 5.0
        ///   - section: Original section name from the rating file
        public init(score: Double, section: String) {
            self.score = score
            self.section = section
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            score = try container.decode(Double.self, forKey: .score)
            section = try container.decode(String.self, forKey: .section)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(score, forKey: .score)
            try container.encode(section, forKey: .section)
        }
    }
    
    /// Source of the game information
    public enum GameSource: String, Codable, Sendable {
        /// Game matched by both name and content with database
        case matchedWithDB
        
        /// Game matched by content but with a different name
        case contentMatch
        
        /// Game matched by name only, content doesn't match
        case nameOnly
        
        /// Game matched by ZIP filename
        case zipName
        
        /// ZIP file exists but doesn't match any known game
        case zipOnly
        
        /// No match found
        case noMatch
        
        /// Game exists in database but no file found
        case noFile
    }
    
    /// Result of ROM verification
    public enum VerificationResult: Codable, Equatable, Sendable {
        /// Perfect match with expected ROMs
        case verified
        
        /// Contents match a different game
        case verifiedDifferentName(String)
        
        /// Verification failed, no match found
        case verificationFailed
        
        // Codable conformance
        enum CodingKeys: String, CodingKey {
            case type
            case associatedValue
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            
            switch type {
            case "verified":
                self = .verified
            case "verifiedDifferentName":
                let value = try container.decode(String.self, forKey: .associatedValue)
                self = .verifiedDifferentName(value)
            case "verificationFailed":
                self = .verificationFailed
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Invalid type value: \(type)"
                )
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            switch self {
            case .verified:
                try container.encode("verified", forKey: .type)
            case .verifiedDifferentName(let value):
                try container.encode("verifiedDifferentName", forKey: .type)
                try container.encode(value, forKey: .associatedValue)
            case .verificationFailed:
                try container.encode("verificationFailed", forKey: .type)
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case description
        case year
        case manufacturer
        case roms = "rom"
        case gameRating
        case languages
        case machineType
        case category
        case subcategory
        case isMature
        case shortTitle
        case source
        case parent
        case fileSize
        case fileModificationDate
        case zipModificationDate
        case specialLists
        case matchedGameId
        case verificationStatus
    }
    
    /// Creates a new MAME game
    /// - Parameters:
    ///   - name: Name/ID of the game
    ///   - description: Description of the game
    ///   - year: Year the game was released
    ///   - manufacturer: Manufacturer of the game
    ///   - roms: ROMs associated with this game
    ///   - gameRating: Optional rating information
    ///   - languages: Languages supported by the game
    ///   - machineType: Type of machine
    ///   - category: Primary category of the game
    ///   - subcategory: Subcategory for more specific classification
    ///   - isMature: Whether the game contains mature content
    ///   - shortTitle: Short title of the game
    ///   - parent: Parent game ID if this is a clone
    ///   - source: Source information about how the game was matched
    ///   - specialLists: Special lists this game belongs to
    ///   - matchedGameId: ID of a matching game if this game's name doesn't match but contents do
    ///   - verificationStatus: Verification status of the game's ROM files
    public init(
        name: String,
        description: String,
        year: String,
        manufacturer: String,
        roms: [RomInfo],
        gameRating: GameRating? = nil,
        languages: [String] = [],
        machineType: String? = nil,
        category: String? = nil,
        subcategory: String? = nil,
        isMature: Bool = false,
        shortTitle: String? = nil,
        parent: String? = nil,
        source: GameSource,
        specialLists: Set<String> = [],
        matchedGameId: String? = nil,
        verificationStatus: VerificationResult? = nil
    ) {
        self.name = name
        self.description = description
        self.year = year
        self.manufacturer = manufacturer
        self.roms = roms
        self.gameRating = gameRating
        self.languages = languages
        self.machineType = machineType
        self.category = category
        self.subcategory = subcategory
        self.isMature = isMature
        self.shortTitle = shortTitle
        self.parent = parent
        self.source = source
        self.specialLists = specialLists
        self.matchedGameId = matchedGameId
        self.verificationStatus = verificationStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        year = try container.decode(String.self, forKey: .year)
        manufacturer = try container.decode(String.self, forKey: .manufacturer)
        roms = try container.decode([RomInfo].self, forKey: .roms)
        gameRating = try? container.decodeIfPresent(GameRating.self, forKey: .gameRating)
        languages = try container.decodeIfPresent([String].self, forKey: .languages) ?? []
        machineType = try container.decodeIfPresent(String.self, forKey: .machineType)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory)
        isMature = try container.decodeIfPresent(Bool.self, forKey: .isMature) ?? false
        shortTitle = try container.decodeIfPresent(String.self, forKey: .shortTitle)
        source = try container.decode(GameSource.self, forKey: .source)
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        specialLists = try container.decodeIfPresent(Set<String>.self, forKey: .specialLists) ?? []
        matchedGameId = try container.decodeIfPresent(String.self, forKey: .matchedGameId)
        verificationStatus = try container.decodeIfPresent(VerificationResult.self, forKey: .verificationStatus)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(year, forKey: .year)
        try container.encode(manufacturer, forKey: .manufacturer)
        try container.encode(roms, forKey: .roms)
        if let rating = gameRating {
            try container.encode(rating, forKey: .gameRating)
        }
        try container.encode(languages, forKey: .languages)
        try container.encodeIfPresent(machineType, forKey: .machineType)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(subcategory, forKey: .subcategory)
        try container.encode(isMature, forKey: .isMature)
        try container.encodeIfPresent(shortTitle, forKey: .shortTitle)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(parent, forKey: .parent)
        try container.encode(specialLists, forKey: .specialLists)
        try container.encodeIfPresent(matchedGameId, forKey: .matchedGameId)
        try container.encodeIfPresent(verificationStatus, forKey: .verificationStatus)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    public static func == (lhs: MameGame, rhs: MameGame) -> Bool {
        lhs.name == rhs.name
    }
    
    /// A computed property that returns the display title for the game
    public var displayTitle: String {
        return description
    }
}
