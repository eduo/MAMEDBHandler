import Foundation

/// Represents information about a ROM file associated with a MAME game
public struct RomInfo: Codable, Hashable, Sendable {
    /// The type of ROM
    public enum RomType: String, Codable, Hashable, Sendable {
        case gameRom = "game"
        case cloneRom = "clone"
        case biosRom = "bios"
        case deviceRom = "device"
    }

    /// The name of the ROM file
    public let name: String
    
    /// The size of the ROM file in bytes
    public let size: Int64
    
    /// The CRC32 checksum of the ROM file (in hexadecimal string format)
    public let crc: String
    
    /// Optional status information about the ROM (e.g. "baddump")
    public let status: String?
    
    /// The name of the ROM this merges with in the parent
    public let merge: String?
    
    /// The type of the ROM (game, clone, bios, device)
    public let type: RomType

    /// Creates a new ROM information instance
    /// - Parameters:
    ///   - name: The name of the ROM file
    ///   - size: The size of the ROM file in bytes
    ///   - crc: The CRC32 checksum of the ROM file
    ///   - status: Optional status information about the ROM
    ///   - merge: The name of the ROM this merges with in the parent
    ///   - type: The type of the ROM (game, clone, bios, device)
    public init(name: String, size: Int64, crc: String, status: String? = nil, merge: String? = nil, type: RomType = .gameRom) {
        self.name = name
        self.size = size
        self.crc = crc
        self.status = status
        self.merge = merge
        self.type = type
    }
}
