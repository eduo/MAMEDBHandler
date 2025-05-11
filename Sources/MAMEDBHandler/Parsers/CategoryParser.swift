import Foundation

/// Parses MAME category information from INI files
public struct CategoryParser {
    /// Regular expression pattern for mature content
    private static let maturePattern = " \\* Mature \\*"
    
    /// Parses category information from an INI file content
    /// - Parameter content: The content of the category INI file
    /// - Returns: Dictionary mapping game IDs to their category information
    public static func parse(_ content: String) -> [String: GameCategory] {
        var gameCategories: [String: GameCategory] = [:]
        var currentCategory: GameCategory?
        var currentGames: Set<String> = []
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            guard !trimmed.isEmpty, !trimmed.hasPrefix(";") else { continue }
            
            // Check if this is a section header
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                // Save previous section if exists
                if let category = currentCategory {
                    for gameId in currentGames {
                        gameCategories[gameId] = category
                    }
                }
                
                // Parse new section header
                let header = String(trimmed.dropFirst().dropLast())
                currentCategory = parseHeader(header)
                currentGames.removeAll()
                
            } else if let _ = currentCategory {
                currentGames.insert(trimmed)
            }
        }
        
        // Don't forget to save the last section
        if let category = currentCategory {
            for gameId in currentGames {
                gameCategories[gameId] = category
            }
        }
        
        return gameCategories
    }

    /// Parses a category header into a GameCategory object
    /// - Parameter header: The header string from the INI file
    /// - Returns: A GameCategory object representing the parsed information
    static func parseHeader(_ header: String) -> GameCategory {
        let isMature = header.contains(" * Mature *")
        let cleanHeader = header.replacingOccurrences(
            of: maturePattern,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
        
        // First replace colon with slash if present
        let normalized = cleanHeader.replacingOccurrences(of: ":", with: "/")
        
        // Split by slash and clean each component
        let parts = normalized.components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        
        switch parts.count {
        case 2:
            return GameCategory(
                machineType: parts[0],
                category: parts[1],
                subcategory: nil,
                isMature: isMature
            )
        case 3:
            return GameCategory(
                machineType: parts[0],
                category: parts[1],
                subcategory: parts[2],
                isMature: isMature
            )
        default:
            // If we can't parse it properly, use the whole string as category
            return GameCategory(
                machineType: parts[0],
                category: parts.joined(separator: "/"),
                subcategory: nil,
                isMature: isMature
            )
        }
    }
}
