// In MAMEDBHandler/Sources/MAMEDBHandler/Models/MachineInfo.swift

import Foundation

/// Represents basic information about a MAME machine
public struct MachineInfo: Sendable {
    /// Description of the machine
    public let description: String
    
    /// Name/ID of the machine
    public let name: String
    
    /// Year the machine was released
    public let year: String
    
    /// Manufacturer of the machine
    public let manufacturer: String
    
    /// ID of the parent machine if this is a clone
    public let cloneof: String?
    
    /// Parent machine name (if available)
    public let parent_name: String?
    
    /// Parent machine year (if available)
    public let parent_year: String?
    
    /// Creates a new machine info instance
    /// - Parameters:
    ///   - description: Description of the machine
    ///   - name: Name/ID of the machine
    ///   - year: Year the machine was released
    ///   - manufacturer: Manufacturer of the machine
    ///   - cloneof: ID of the parent machine if this is a clone
    ///   - parent_name: Parent machine name (if available)
    ///   - parent_year: Parent machine year (if available)
    public init(
        description: String,
        name: String,
        year: String,
        manufacturer: String,
        cloneof: String? = nil,
        parent_name: String? = nil,
        parent_year: String? = nil
    ) {
        self.description = description
        self.name = name
        self.year = year
        self.manufacturer = manufacturer
        self.cloneof = cloneof
        self.parent_name = parent_name
        self.parent_year = parent_year
    }
}
