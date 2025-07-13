import Foundation
import Supabase

class RealtimeManager {
    static let shared = RealtimeManager()
    private init() {}

    private var roomStatusChannel: RealtimeChannelV2?
    private var participantsChannel: RealtimeChannelV2?
    private var roomStatusTask: Task<Void, Never>?
    private var participantsTask: Task<Void, Never>?

    // Subscribe to room status changes
    func subscribeToRoomStatus(roomId: String, onUpdate: @escaping (Room) -> Void) {
        unsubscribeRoomStatus()
        let channel = SupabaseManager.shared.client.realtimeV2.channel("public:rooms")
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "rooms")
        roomStatusChannel = channel
        roomStatusTask = Task {
            await channel.subscribe()
            let decoder = JSONDecoder()
            for await update in updates {
                if let room = try? update.decodeRecord(as: Room.self, decoder: decoder), room.id == roomId {
                    onUpdate(room)
                }
            }
        }
    }

    func unsubscribeRoomStatus() {
        roomStatusTask?.cancel()
        roomStatusTask = nil
        if let channel = roomStatusChannel {
            Task { await channel.unsubscribe() }
        }
        roomStatusChannel = nil
    }

    // Subscribe to participant changes
    func subscribeToParticipants(roomId: String, onUpdate: @escaping ([RoomParticipant]) -> Void) {
        unsubscribeParticipants()
        let channel = SupabaseManager.shared.client.realtimeV2.channel("public:room_participants")
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "room_participants")
        let deletes = channel.postgresChange(DeleteAction.self, schema: "public", table: "room_participants")
        participantsChannel = channel
        participantsTask = Task {
            await channel.subscribe()
            for await _ in inserts {
                await fetchAndUpdate(roomId: roomId, onUpdate: onUpdate)
            }
            for await _ in deletes {
                await fetchAndUpdate(roomId: roomId, onUpdate: onUpdate)
            }
        }
    }

    func unsubscribeParticipants() {
        participantsTask?.cancel()
        participantsTask = nil
        if let channel = participantsChannel {
            Task { await channel.unsubscribe() }
        }
        participantsChannel = nil
    }

    private func fetchAndUpdate(roomId: String, onUpdate: @escaping ([RoomParticipant]) -> Void) async {
        do {
            let response = try await SupabaseManager.shared.client
                .from("room_participants")
                .select()
                .eq("room_id", value: roomId)
                .execute()
            let allParticipants = try JSONDecoder().decode([RoomParticipant].self, from: response.data)
            await MainActor.run {
                onUpdate(allParticipants)
            }
        } catch {
            // Handle error if needed
        }
    }
} 