import Foundation

/// Parser for MAME INI files with sections and ratings
public struct MAMEIniParser {
    /// Represents a section in a MAME INI file with rating information
    public struct Section {
        /// Original section name, e.g. "90 to 100 (Best)"
        public let name: String
        
        /// Maximum score value (e.g., 100)
        public let maxScore: Int
        
        /// Converts max score to a star rating scale
        /// - Returns: Rating on a scale from 0.0 to 5.0
        public var starRating: Double {
            // Convert max score to rating scale:
            // 100 -> 5.0, 90 -> 4.5, 80 -> 4.0, etc.
            Double(maxScore) / 20.0
        }
    }
    
    /// The content of the INI file
    private let content: String
    
    /// Sections found in the INI file
    private var sections: [Section] = []
    
    /// Mapping of game IDs to their sections
    public var supportedGames: [String: Section] = [:]
    
    /// Creates a new INI parser
    /// - Parameter content: The content of the INI file to parse
    public init(content: String) {
        self.content = content
    }
    
    /// Parses the INI content
    /// - Throws: Error if parsing fails
    public mutating func parse() throws {
        sections.removeAll()
        supportedGames.removeAll()
        
        var currentSection: String?
        var currentGames: Set<String> = []
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            guard !trimmed.isEmpty, !trimmed.hasPrefix(";") else { continue }
            
            // Check if this is a section header
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                // If we were processing a section, save it
                if let section = currentSection,
                   let parsedSection = try? parseSection(name: section, games: currentGames) {
                    sections.append(parsedSection)
                    // Add games to supported games map
                    for game in currentGames {
                        supportedGames[game] = parsedSection
                    }
                }
                
                // Start new section
                let sectionName = String(trimmed.dropFirst().dropLast())
                if sectionName != "FOLDER_SETTINGS" && sectionName != "ROOT_FOLDER" {
                    currentSection = sectionName
                    currentGames = []
                } else {
                    currentSection = nil
                }
                
            } else if let _ = currentSection {
                // Add game to current section
                currentGames.insert(trimmed)
            }
        }
        
        // Don't forget to save the last section
        if let section = currentSection,
           let parsedSection = try? parseSection(name: section, games: currentGames) {
            sections.append(parsedSection)
            for game in currentGames {
                supportedGames[game] = parsedSection
            }
        }
    }
    
    /// Parses a section from the INI file
    /// - Parameters:
    ///   - name: The name of the section
    ///   - games: Set of game IDs in this section
    /// - Returns: A parsed Section object or nil if parsing failed
    private func parseSection(name: String, games: Set<String>) throws -> Section? {
        guard let maxScore = extractMaxScore(from: name) else {
            return nil
        }
        
        return Section(
            name: name,
            maxScore: maxScore
        )
    }
    
    /// Extracts the maximum score from a section name
    /// - Parameter name: The section name (e.g. "90 to 100 (Best)")
    /// - Returns: The maximum score as an integer, or nil if not found
    private func extractMaxScore(from name: String) -> Int? {
        let pattern = #"^(\d+)\s+to\s+(\d+)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: name,
                range: NSRange(name.startIndex..., in: name)
              ) else {
            return nil
        }
        
        guard let maxRange = Range(match.range(at: 2), in: name),
              let max = Int(name[maxRange]) else {
            return nil
        }
        
        return max
    }
}
