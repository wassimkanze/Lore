import Foundation
import SwiftData

public enum LoreDatabase {
    public static let schema = Schema([Project.self, AISession.self, GitCommit.self, ActivityBlock.self])
    public static func make(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let storeURL = try url ?? defaultURL()
            configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
    public static func defaultURL() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Lore", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Lore.store")
    }
}
