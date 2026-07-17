//
//  ContentView.swift
//  Rooms
//
//  Created by Mohammad Azam on 7/15/26.
//

import SwiftUI
import SwiftData

struct Constants {

    struct URLs {
        static let base = URL(string: "http://localhost:8080/api/")!
        static let rooms = base.appending(path: "rooms")
    }
}

enum HTTPMethod {
    case get
    case post(Data)
    case delete
    case put
    
    var rawValue: String {
        switch self {
        case .get:
            "GET"
        case .post:
            "POST"
        case .delete:
            "DELETE"
        case .put:
            "PUT"
        }
    }
    
    var body: Data? {
        switch self {
        case .post(let data):
            data
        default:
            nil
        }
    }
}

struct Resource<T: Decodable> {
    let url: URL
    var method: HTTPMethod = .get
    let responseType: T.Type
}

enum NetworkError: Error {
    case badRequest(Data)
    case unauthorized
    case invalidResponse
    case decodingFailed(Error)
}

struct HTTPClient {
    
    private let session: URLSession
    private let defaultHeaders: [String: String]
    
    init(session: URLSession = .shared, defaultHeaders: [String : String] = ["Content-Type": "application/json"]) {
        self.session = session
        self.defaultHeaders = defaultHeaders
    }
    
    func fetch<T>(resource: Resource<T>) async throws -> T {
        
        var request = URLRequest(url: resource.url)
        request.httpMethod = resource.method.rawValue
        request.allHTTPHeaderFields = defaultHeaders
        request.httpBody = resource.method.body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw NetworkError.decodingFailed(error)
            }
        case 401:
            throw NetworkError.unauthorized
        case 400...499:
            throw NetworkError.badRequest(data)
        default:
            throw NetworkError.invalidResponse
        }
    }
}

@Model
class Room {
    @Attribute(.unique) var syncId: UUID = UUID()
    var name: String
    var area: Double
    var isDeleted: Bool = false
    
    init(syncId: UUID = UUID(), name: String, area: Double) {
        self.syncId = syncId
        self.name = name
        self.area = area
    }
}

enum SyncAction: String, Codable {
    case insert
    case delete
    case update
}

struct RoomPayload: Codable {
    let id: UUID
    let name: String?
    let area: Double?
    let action: SyncAction
}

struct RoomResponse: Codable {
    let success: Bool
}

struct RoomSyncService {
    
    let httpClient: HTTPClient
    
    func uploadRooms(payloads: [RoomPayload]) async throws {
        let body = try JSONEncoder().encode(payloads)
        let resource = Resource(url: Constants.URLs.rooms, method: .post(body), responseType: RoomResponse.self)
        let response = try await httpClient.fetch(resource: resource)
        print(response.success)
    }
    
}

@Observable
class RoomSyncManager {
    
    private var observer: HistoryObserver?
    private let syncService: RoomSyncService
    
    init(syncService: RoomSyncService = RoomSyncService(httpClient: HTTPClient())) {
        self.syncService = syncService
    }
    
    @ObservationIgnored private var token: ObservationTracking.Token?
    @ObservationIgnored private var isSyncing = false
    
    @ObservationIgnored private var lastToken: DefaultHistoryToken? {
        get {
            // get the value from user defaults
            guard let data = UserDefaults.standard.data(forKey: "RoomSyncManager_LastToken") else { return nil }
            return try? JSONDecoder().decode(DefaultHistoryToken.self, from: data)
            
        }
        set {
            
            if let newValue = newValue {
                guard let data = try? JSONEncoder().encode(newValue) else { return }
                UserDefaults.standard.set(data, forKey: "RoomSyncManager_LastToken")
            }
        }
    }
    
    
    func start(container: ModelContainer) throws {
        observer = try HistoryObserver(observedModels: [Room.self], modelContainer: container)
        
        token = withContinuousObservation(options: .didSet) { [weak self] event in
            print("Observation Fired...")
            _ = self?.observer?.eventCounter
            self?.processChanges(context: container.mainContext)
        }
    }
    
    private func processChanges(context: ModelContext) {
        
        guard !isSyncing else { return }
        isSyncing = true
        
        let descriptor: HistoryDescriptor<DefaultHistoryTransaction>
        
        if let lastToken = lastToken {
            descriptor = HistoryDescriptor<DefaultHistoryTransaction>(predicate: #Predicate {
                transaction in transaction.token > lastToken
            })
        } else {
            descriptor = HistoryDescriptor()
        }
        
        do {
            
            let history = try context.fetchHistory(descriptor)
            var payloadsToSync: [RoomPayload] = []
            
            // transactions in the history
            for transaction in history {
                print("Transaction Changes Count: \(transaction.changes.count)")
                
                for change in transaction.changes {
                    switch change {
                        case .insert(let insert as DefaultHistoryInsert<Room>):
                            print("Inserted...")
                            if let room = context.model(for: insert.changedPersistentIdentifier) as? Room {
                                let payload = RoomPayload(id: room.syncId, name: room.name, area: room.area, action: .insert)
                                payloadsToSync.append(payload)
                            }
                        
                        case .update(let update as DefaultHistoryUpdate<Room>):
                            if let room = context.model(for: update.changedPersistentIdentifier) as? Room {
                                
                                if room.isDeleted {
                                    let payload = RoomPayload(id: room.syncId, name: nil, area: nil, action: .delete)
                                    payloadsToSync.append(payload)
                                } else {
                                    let payload = RoomPayload(id: room.syncId, name: room.name, area: room.area, action: .update)
                                    payloadsToSync.append(payload)
                                }
                                
                            }
                        
                        case .delete:
                                break
                            
                        default:
                            break
                    }
                }
            }
            
            // call the syncService.uploadRooms
            if !payloadsToSync.isEmpty {
                
                Task {
                    do {
                        print("syncService.uploadRooms")
                        try await syncService.uploadRooms(payloads: payloadsToSync)
                        
                        if let latestToken = history.last?.token {
                            self.lastToken = latestToken
                        }
                        
                        // clean up the deleted Ids
                        let deletedIds = payloadsToSync.filter { $0.action == .delete }.map { $0.id }
                        
                        if !deletedIds.isEmpty {
                            do {
                                try context.delete(model: Room.self, where: #Predicate { room in
                                    deletedIds.contains(room.syncId)
                                })
                                try context.save()
                            } catch {
                                print(error.localizedDescription)
                            }
                        }
                        
                        isSyncing = false
                        
                    } catch {
                        print(error.localizedDescription)
                        isSyncing = false
                    }
                }
                
            } else {
                
                if let latestToken = history.last?.token {
                    lastToken = latestToken
                }
                
                isSyncing = false
            }
            
            print("History Count: \(history.count)")
            
        } catch {
            print(error.localizedDescription)
            isSyncing = false
        }
    }
    
}


struct RoomListScreen: View {
    
    @State private var name: String = ""
    @State private var area: Double?
    
    @Environment(\.modelContext) private var context
    
    @Query(filter: #Predicate<Room> { room in
        room.isDeleted == false
    }) private var rooms: [Room]
    
    var body: some View {
        VStack {
            Form {
                TextField("Name", text: $name)
                TextField("Area", value: $area, format: .number)
                Button("Add") {
                    let room = Room(name: name, area: area ?? 0)
                    context.insert(room)
                }
            }
            
            List {
                ForEach(rooms) { room in
                    Text(room.name)
                }.onDelete { indexSet in
                    indexSet.forEach { index in
                        let room = rooms[index]
                        room.isDeleted = true
                    }
                }
            }
        }
    }
}

