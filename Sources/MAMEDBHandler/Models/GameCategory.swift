import Foundation

/// Represents category information for a MAME game
public struct GameCategory: Codable, Hashable, Sendable {
    /// Type of machine (e.g. "Arcade")
    public let machineType: String
    
    /// Primary category of the game
    public let category: String
    
    /// Optional subcategory for more specific classification
    public let subcategory: String?
    
    /// Whether the game contains mature content
    public let isMature: Bool
    
    /// Creates a new game category instance
    /// - Parameters:
    ///   - machineType: Type of machine
    ///   - category: Primary category of the game
    ///   - subcategory: Optional subcategory
    ///   - isMature: Whether the game contains mature content
    public init(
        machineType: String,
        category: String,
        subcategory: String? = nil,
        isMature: Bool = false
    ) {
        self.machineType = machineType
        self.category = category
        self.subcategory = subcategory
        self.isMature = isMature
    }
}
