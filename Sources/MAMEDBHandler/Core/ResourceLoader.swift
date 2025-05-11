import Foundation

/// Helper for loading resource files from the package
public class ResourceLoader {
    /// Load a resource file as string
    /// - Parameter name: Name of the resource file (without extension)
    /// - Parameter extension: Extension of the resource file
    /// - Returns: Content of the resource file as string
    /// - Throws: Error if the file cannot be loaded
    public static func loadResource(name: String, extension ext: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw ResourceError.fileNotFound(name: name, extension: ext)
        }
        
        return try String(contentsOf: url, encoding: .utf8)
    }
    
    /// Errors related to resource loading
    public enum ResourceError: LocalizedError {
        /// Resource file not found
        case fileNotFound(name: String, extension: String)
        
        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let name, let ext):
                return "Resource file not found: \(name).\(ext)"
            }
        }
    }
}
