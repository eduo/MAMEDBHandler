import Foundation
import SQLite3

public actor DatabaseActor {
    /// The SQLite database connection
    private var db: OpaquePointer?
    
    /// Initializes a new DatabaseActor
    public init() {}
    
    /// Sets the database connection
    /// - Parameter db: The SQLite database connection pointer
    public func setDB(_ db: OpaquePointer?) {
        self.db = db
    }
    
    /// Closes the database connection
    public func closeDB() {
        if let db = db {
            sqlite3_close(db)
        }
        self.db = nil
    }
    
    /// Performs an operation with the database connection
    /// - Parameter block: The block to execute with the database connection
    /// - Returns: The result of the block
    /// - Throws: Any error thrown by the block
    public func perform<T: Sendable>(_ block: @Sendable (OpaquePointer?) throws -> T) async throws -> T {
        guard let db = db else {
            throw DBError.databaseNotInitialized
        }
        return try block(db)
    }
}
