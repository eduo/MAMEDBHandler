import Foundation

/// Parser for MAME language information from INI files
public struct MameLanguageParser {
    
    /// Parses language information from a languages.ini file
    /// - Parameter content: The content of the languages.ini file
    /// - Returns: Dictionary mapping game IDs to arrays of language codes
    public static func parse(_ content: String) -> [String: [String]] {
        var gameLanguages: [String: [String]] = [:]
        var currentLanguage: String?
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            guard !trimmed.isEmpty, !trimmed.hasPrefix(";") else { continue }
            
            // Check if this is a section header
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                // Start new section
                currentLanguage = String(trimmed.dropFirst().dropLast())
            } else if let language = currentLanguage {
                let gameId = trimmed
                if gameLanguages[gameId] == nil {
                    gameLanguages[gameId] = []
                }
                gameLanguages[gameId]?.append(language)
            }
        }
        
        return gameLanguages
    }
}
