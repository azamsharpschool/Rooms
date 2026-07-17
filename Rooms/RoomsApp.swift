//
//  RoomsApp.swift
//  Rooms
//
//  Created by Mohammad Azam on 7/15/26.
//

import SwiftUI
import SwiftData

@main
struct RoomsApp: App {
    
    private let container: ModelContainer
    @State private var roomSyncManager: RoomSyncManager
    
    init() {
        container = try! ModelContainer(for: Room.self, configurations: ModelConfiguration(isStoredInMemoryOnly: false))
        roomSyncManager = RoomSyncManager()
        startRoomSync()
    }
    
    private func startRoomSync() {
        do {
            try roomSyncManager.start(container: container)
        } catch {
            print(error.localizedDescription)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            RoomListScreen()
                .modelContainer(container)
                .task {
                    container.mainContext.author = "App"
                }
            
        }
    }
}
