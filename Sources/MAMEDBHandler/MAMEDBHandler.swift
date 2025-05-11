import Foundation


// Private class just for bundle identification
private class BundleIdentifierClass {}
/// MAMEDBHandler provides functionality for working with MAME databases
public enum MAMEDBHandler {
    /// The version of the package
    public static let version = "1.0.0"
    
    /// Initializes the package with default resources
    public static func initialize() {
        print("MAMEDBHandler initialized")
    }
    
    /// Gets the master list for a specific database version
    /// - Parameter version: The database version
    /// - Returns: Array of MameGame objects
    /// - Throws: Error if the master list cannot be loaded
    public static func getMasterList(for version: String) async throws -> [MameGame] {
        return try await MasterListManager.shared.getMasterList(for: version)
    }
}
