//
//  ContentView.swift
//  VibinWork
//
//  Created by Karthik  on 13/07/25.
//

import SwiftUI
import Supabase

// Helper for encoding heterogeneous values
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        _encode = value.encode
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

class AuthViewModel: ObservableObject {
    @Published var user: User?
    private var authTask: Task<Void, Never>?

    init() {
        authTask = Task {
            await self.loadCurrentUser()
            await self.listenToAuthChanges()
        }
    }

    deinit {
        authTask?.cancel()
    }

    func loadCurrentUser() async {
        if let session = try? await SupabaseManager.shared.client.auth.session {
            await MainActor.run {
                self.user = session.user
            }
        }
    }

    func listenToAuthChanges() async {
        for await (_, session) in SupabaseManager.shared.client.auth.authStateChanges {
            await MainActor.run {
                self.user = session?.user
            }
        }
    }

    func signInWithGoogle() {
        DispatchQueue.main.async {
            Task {
                do {
                    try await SupabaseManager.shared.signInWithGoogle()
                } catch {
                    print("Google sign-in failed: \(error)")
                }
            }
        }
    }
}

struct UserProfile: Decodable, Encodable, Identifiable {
    let id: String
    let email: String
    let username: String?
    let avatar_url: String?
    let focus_goal: String?
    let interests: [String]?
    let working_style: String?
    let session_pref_duration: Int?
    let timezone: String?
    let availability: String?
    let experience_level: String?
    let is_available: Bool?
    let current_session_id: String?
}

struct Session: Codable, Identifiable {
    let id: String
    let user1_id: String
    let user2_id: String
    let start_time: String? // ISO8601 string, can be nil at creation
    let end_time: String?   // ISO8601 string, can be nil at creation
    let status: String      // 'active', 'completed', 'cancelled'
    let duration_minutes: Int?
    let voice_room_id: String?
    let created_at: String? // ISO8601 string, set by Supabase
}

struct Room: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let host_id: String
    let max_participants: Int
    let status: String
    let created_at: String?
    let room_name: String?
    let timer_minutes: Int?
    let session_started_epoch: Int64?
}

struct RoomParticipant: Codable, Identifiable {
    let id: String
    let room_id: String
    let user_id: String
    let joined_at: String?
}

struct RoomListView: View {
    @State private var rooms: [Room] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var showCreateRoom = false
    @State private var selectedRoom: Room? = nil
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading rooms...")
                } else if let error = error {
                    Text(error).foregroundColor(.red)
                } else if rooms.isEmpty {
                    Text("No open rooms available.")
                        .foregroundColor(.secondary)
                } else {
                    List(rooms) { room in
                        Button(action: { selectedRoom = room }) {
                            VStack(alignment: .leading) {
                                Text("Room ID: \(room.id)")
                                    .font(.headline)
                                Text("Host: \(room.host_id)")
                                    .font(.subheadline)
                                Text("Max Participants: \(room.max_participants)")
                                    .font(.subheadline)
                                Text("Status: \(room.status)")
                                    .font(.caption)
                            }
                        }
                    }
                }
                Spacer()
                Button(action: { showCreateRoom = true }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Create Room")
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .sheet(isPresented: $showCreateRoom) {
                    CreateRoomView(isPresented: $showCreateRoom)
                        .environmentObject(authVM)
                }
                .sheet(item: $selectedRoom) { room in
                    RoomDetailsView(room: room, isPresented: $selectedRoom)
                        .environmentObject(authVM)
                }
            }
            .padding()
            .navigationTitle("Available Rooms")
            .onAppear { fetchRooms() }
        }
    }

    func fetchRooms() {
        isLoading = true
        error = nil
        Task {
            do {
                let response = try await SupabaseManager.shared.client
                    .from("rooms")
                    .select()
                    .eq("status", value: "open")
                    .order("created_at", ascending: false)
                    .execute()
                let allRooms = try JSONDecoder().decode([Room].self, from: response.data)
                // Optionally filter out full rooms (requires participant count logic)
                await MainActor.run {
                    self.rooms = allRooms
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

struct CreateRoomView: View {
    @Binding var isPresented: Bool
    @State private var roomName: String = ""
    @State private var maxParticipants: Int = 2
    @State private var timerMinutes: Int = 25
    @State private var isCreating = false
    @State private var error: String? = nil
    @State private var createdRoom: Room? = nil
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        if let room = createdRoom {
            HostWaitingRoomView(room: room)
        } else {
            VStack(spacing: 24) {
                Text("Create a Room")
                    .font(.title2)
                    .fontWeight(.bold)
                TextField("Room Name", text: $roomName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Stepper("Max Participants: \(maxParticipants)", value: $maxParticipants, in: 1...10)
                Stepper("Timer (minutes): \(timerMinutes)", value: $timerMinutes, in: 10...120, step: 5)
                if let error = error {
                    Text(error).foregroundColor(.red)
                }
                Button("Create Room") {
                    createRoom()
                }
                .disabled(isCreating || roomName.isEmpty)
                .padding()
                .background((isCreating || roomName.isEmpty) ? Color.gray : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .foregroundColor(.red)
            }
            .padding()
        }
    }

    func createRoom() {
        guard let user = authVM.user else { return }
        isCreating = true
        error = nil
        Task {
            do {
                let payload: [String: AnyEncodable] = [
                    "host_id": AnyEncodable(user.id.uuidString),
                    "max_participants": AnyEncodable(maxParticipants),
                    "status": AnyEncodable("open"),
                    "room_name": AnyEncodable(roomName),
                    "timer_minutes": AnyEncodable(timerMinutes)
                ]
                let response = try await SupabaseManager.shared.client
                    .from("rooms")
                    .insert(payload)
                    .select()
                    .single()
                    .execute()
                let room = try JSONDecoder().decode(Room.self, from: response.data)
                await MainActor.run {
                    self.createdRoom = room
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isCreating = false
                }
            }
        }
    }
}

// Add SessionView
struct SessionView: View {
    let room: Room
    let participantsCount: Int
    @State private var remainingSeconds: Int = 0
    @State private var timer: Timer? = nil
    @State private var parseError: Bool = false
    @StateObject private var voiceService = VoiceService()

    var body: some View {
        VStack(spacing: 24) {
            Text("Session in Progress").font(.largeTitle).fontWeight(.bold)
            Text("Room: \(room.room_name ?? "Unnamed Room")")
            Text("Timer: \(room.timer_minutes ?? 0) min")
            Text("Participants: \(participantsCount)/\(room.max_participants)")
            if parseError {
                Text("Timer error: could not get start time.")
                    .foregroundColor(.red)
            } else if remainingSeconds > 0 {
                Text("Time Left: \(formatTime(remainingSeconds))")
                    .font(.title2)
                    .fontWeight(.semibold)
            } else {
                Text("Session Complete!")
                    .font(.title2)
                    .foregroundColor(.green)
            }
            
            Button(action: {
                voiceService.toggleMute()
            }) {
                Image(systemName: voiceService.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.title)
            }
            .padding()
        }
        .padding()
        .onAppear {
            startCountdown()
            voiceService.joinChannel(room: room)
        }
        .onDisappear {
            timer?.invalidate()
            voiceService.leaveChannel()
        }
    }

    private func startCountdown() {
        guard let startEpoch = room.session_started_epoch, let duration = room.timer_minutes else {
            parseError = true
            print("[Timer] session_started_epoch or duration missing")
            return
        }
        let endEpoch = startEpoch + Int64(duration * 60)
        updateRemaining(endEpoch: endEpoch)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            updateRemaining(endEpoch: endEpoch)
        }
    }

    private func updateRemaining(endEpoch: Int64) {
        let nowEpoch = Int64(Date().timeIntervalSince1970)
        let remaining = Int(endEpoch - nowEpoch)
        if remaining > 0 {
            remainingSeconds = remaining
        } else {
            remainingSeconds = 0
            timer?.invalidate()
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct HostWaitingRoomView: View {
    let room: Room
    @State private var participants: [UserProfile] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var isStarting = false
    @State private var sessionStarted = false
    @State private var autoStartTimer: Timer? = nil
    @State private var secondsLeft: Int = 180
    @State private var roomStatus: String = "open"
    @State private var sessionRoom: Room?
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        if roomStatus == "in_session", let startedRoom = sessionRoom {
            SessionView(room: startedRoom, participantsCount: participants.count)
        } else {
            VStack(spacing: 20) {
                Text("Room: \(room.room_name ?? "")")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Participants (") + Text("\(participants.count)/\(room.max_participants)") + Text(")")
                if isLoading {
                    ProgressView("Waiting for partners…")
                } else if let error = error {
                    Text(error).foregroundColor(.red)
                } else {
                    ForEach(participants) { profile in
                        ParticipantRow(profile: profile)
                    }
                }
                if !sessionStarted {
                    if participants.count > 0 {
                        Text("Session will auto-start in \(secondsLeft) seconds if not started manually.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("Waiting for participants to join…")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Button("Start Session") {
                        startSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStarting || (room.max_participants == 1 ? false : participants.isEmpty))
                    .padding()
                    .background(isStarting ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    Button("End Session") {
                        endSession()
                    }
                    .padding(.top, 8)
                    .foregroundColor(.red)
                } else {
                    Text("Session started!").foregroundColor(.green)
                }
                if room.max_participants == 1 {
                    Text("You can start a solo session immediately.")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .onAppear {
                subscribeToRoomStatus()
                subscribeToParticipants()
            }
            .onDisappear {
                unsubscribeFromRoomStatus()
                unsubscribeFromParticipants()
            }
        }
    }

    func startSession() {
        isStarting = true
        error = nil
        autoStartTimer?.invalidate()
        autoStartTimer = nil
        Task {
            do {
                let nowEpoch = Int64(Date().timeIntervalSince1970)
                let updatePayload: [String: AnyEncodable] = [
                    "status": AnyEncodable("in_session"),
                    "session_started_epoch": AnyEncodable(nowEpoch)
                ]
                print("[DEBUG] Updating room \(room.id) with payload: \(updatePayload)")
                let response = try await SupabaseManager.shared.client
                    .from("rooms")
                    .update(updatePayload)
                    .eq("id", value: room.id)
                    .select()
                    .single()
                    .execute()
                let decodedRoom = try JSONDecoder().decode(Room.self, from: response.data)
                print("[DEBUG] Supabase update response: \(response)")
                await MainActor.run {
                    self.sessionRoom = decodedRoom
                    self.isStarting = false
                    self.roomStatus = "in_session"
                }
            } catch {
                print("[DEBUG] Error updating room: \(error)")
                await MainActor.run {
                    self.error = "Failed to start session: \(error.localizedDescription)"
                    self.isStarting = false
                }
            }
        }
    }

    func startAutoStartTimer() {
        secondsLeft = 180
        autoStartTimer?.invalidate()
        autoStartTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if sessionStarted { timer.invalidate(); return }
            if secondsLeft > 0 {
                secondsLeft -= 1
            } else {
                timer.invalidate()
                startSession()
            }
        }
    }

    func endSession() {
        autoStartTimer?.invalidate()
        autoStartTimer = nil
        Task {
            do {
                _ = try await SupabaseManager.shared.client
                    .from("rooms")
                    .delete()
                    .eq("id", value: room.id)
                    .execute()
                await MainActor.run {
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func subscribeToRoomStatus() {
        RealtimeManager.shared.subscribeToRoomStatus(roomId: room.id) { updatedRoom in
            DispatchQueue.main.async {
                self.roomStatus = updatedRoom.status
                self.sessionRoom = updatedRoom
            }
        }
    }
    private func unsubscribeFromRoomStatus() {
        RealtimeManager.shared.unsubscribeRoomStatus()
    }

    private func subscribeToParticipants() {
        RealtimeManager.shared.subscribeToParticipants(roomId: room.id) { updatedParticipants in
            print("[Host] Real-time participants update: \(updatedParticipants.map { $0.user_id })")
            Task {
                var profiles: [UserProfile] = []
                for p in updatedParticipants {
                    do {
                        let userResp = try await SupabaseManager.shared.client
                            .from("users")
                            .select()
                            .eq("id", value: p.user_id)
                            .single()
                            .execute()
                        if let profile = try? JSONDecoder().decode(UserProfile.self, from: userResp.data) {
                            profiles.append(profile)
                        }
                    } catch {
                        // Optionally log error
                    }
                }
                await MainActor.run {
                    self.participants = profiles
                }
            }
        }
    }
    private func unsubscribeFromParticipants() {
        RealtimeManager.shared.unsubscribeParticipants()
    }
}

struct HomeScreenView: View {
    @State private var showCreateRoom = false
    @State private var showJoinRoom = false
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            Text("VibinWork Rooms")
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            Button(action: { showCreateRoom = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Room")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .sheet(isPresented: $showCreateRoom) {
                CreateRoomView(isPresented: $showCreateRoom)
                    .environmentObject(authVM)
            }
            Button(action: { showJoinRoom = true }) {
                HStack {
                    Image(systemName: "person.3.fill")
                    Text("Join Room")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .sheet(isPresented: $showJoinRoom) {
                JoinRoomListView().environmentObject(authVM)
            }
            Spacer()
        }
        .padding()
    }
}

// In MainView, show HomeScreenView as the entry point
struct MainView: View {
    let user: User
    var body: some View {
        HomeScreenView().environmentObject(AuthViewModel())
    }
}

struct MatchLoadingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var authVM: AuthViewModel
    @State private var isSearching = false
    @State private var foundPartner: UserProfile? = nil
    @State private var error: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var partnerUnavailable = false
    @State private var partnerPollingTask: Task<Void, Never>? = nil
    @State private var session: Session? = nil

    var body: some View {
        VStack(spacing: 32) {
            ProgressView()
                .scaleEffect(2)
            if let session = session {
                Text("Session created! ID: \(session.id)")
                    .font(.title2)
                    .fontWeight(.medium)
                // Placeholder for SessionView transition
            } else if let found = foundPartner {
                Text("Found partner: \(found.username ?? "Unknown")")
                    .font(.title2)
                    .fontWeight(.medium)
                if partnerUnavailable {
                    Text("Partner left, searching again...")
                        .foregroundColor(.orange)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                foundPartner = nil
                                partnerUnavailable = false
                                isSearching = false
                                searchTask = Task { await startMatching() }
                            }
                        }
                }
            } else {
                Text("Looking for a partner...")
                    .font(.title2)
                    .fontWeight(.medium)
            }
            if let error = error {
                Text(error)
                    .foregroundColor(.red)
            }
            Button("Cancel") {
                Task {
                    if let user = authVM.user {
                        try? await SupabaseManager.shared.client
                            .from("users")
                            .update(["is_available": false])
                            .eq("id", value: user.id.uuidString)
                            .execute()
                    }
                    isPresented = false
                    searchTask?.cancel()
                    partnerPollingTask?.cancel()
                }
            }
            .foregroundColor(.red)
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(0.95))
        .ignoresSafeArea()
        .onAppear {
            if !isSearching {
                isSearching = true
                searchTask = Task { await startMatching() }
            }
        }
        .onDisappear {
            searchTask?.cancel()
            partnerPollingTask?.cancel()
        }
    }

    func startMatching() async {
        guard let user = authVM.user else { return }
        do {
            // 1. Mark current user as available
            try await SupabaseManager.shared.client
                .from("users")
                .update(["is_available": true])
                .eq("id", value: user.id.uuidString)
                .execute()
            // 2. Poll for available partners or own session assignment
            while !Task.isCancelled {
                // Check for available partners
                let response = try await SupabaseManager.shared.client
                    .from("users")
                    .select()
                    .eq("is_available", value: true)
                    .neq("id", value: user.id.uuidString)
                    .limit(1)
                    .execute()
                if let partner = try? JSONDecoder().decode([UserProfile].self, from: response.data).first {
                    await MainActor.run {
                        foundPartner = partner
                        print("Found partner: \(partner)")
                        startPollingPartnerAvailability(partnerId: partner.id)
                    }
                    // --- Atomic session creation logic ---
                    // Fetch both users' latest records
                    let myResponse = try await SupabaseManager.shared.client
                        .from("users")
                        .select()
                        .eq("id", value: user.id.uuidString)
                        .single()
                        .execute()
                    let partnerResponse = try await SupabaseManager.shared.client
                        .from("users")
                        .select()
                        .eq("id", value: partner.id)
                        .single()
                        .execute()
                    let me = try? JSONDecoder().decode(UserProfile.self, from: myResponse.data)
                    let partnerProfile = try? JSONDecoder().decode(UserProfile.self, from: partnerResponse.data)
                    if let sessionId = me?.current_session_id ?? partnerProfile?.current_session_id {
                        // Join the existing session
                        let sessionResp = try await SupabaseManager.shared.client
                            .from("sessions")
                            .select()
                            .eq("id", value: sessionId)
                            .single()
                            .execute()
                        if let session = try? JSONDecoder().decode(Session.self, from: sessionResp.data) {
                            await MainActor.run {
                                self.session = session
                            }
                        }
                    } else {
                        // Create a new session
                        let session: Session
                        do {
                            session = try await SupabaseManager.shared.createSession(
                                user1Id: user.id.uuidString,
                                user2Id: partner.id,
                                durationMinutes: partner.session_pref_duration ?? 25
                            )
                            try await SupabaseManager.shared.updateUsersForSession(
                                user1Id: user.id.uuidString,
                                user2Id: partner.id,
                                sessionId: session.id
                            )
                            await MainActor.run {
                                self.session = session
                            }
                        } catch {
                            await MainActor.run {
                                self.error = "Failed to create session: \(error.localizedDescription)"
                            }
                        }
                    }
                    break
                }
                // Check own user record for session assignment
                let myResponse = try await SupabaseManager.shared.client
                    .from("users")
                    .select()
                    .eq("id", value: user.id.uuidString)
                    .single()
                    .execute()
                if let me = try? JSONDecoder().decode(UserProfile.self, from: myResponse.data),
                   let isAvailable = me.is_available, !isAvailable,
                   let sessionId = me.current_session_id {
                    // Fetch the session and transition
                    let sessionResp = try await SupabaseManager.shared.client
                        .from("sessions")
                        .select()
                        .eq("id", value: sessionId)
                        .single()
                        .execute()
                    if let session = try? JSONDecoder().decode(Session.self, from: sessionResp.data) {
                        await MainActor.run {
                            self.session = session
                        }
                        break
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }

    func startPollingPartnerAvailability(partnerId: String) {
        partnerPollingTask?.cancel()
        partnerPollingTask = Task {
            while !Task.isCancelled {
                do {
                    let response = try await SupabaseManager.shared.client
                        .from("users")
                        .select()
                        .eq("id", value: partnerId)
                        .single()
                        .execute()
                    if let partner = try? JSONDecoder().decode(UserProfile.self, from: response.data),
                       let isAvailable = partner.is_available,
                       !isAvailable {
                        await MainActor.run {
                            partnerUnavailable = true
                        }
                        break
                    }
                } catch {
                    // Ignore errors, just retry
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
    }
}

struct OnboardingView: View {
    let user: User
    @State private var step = 0
    @State private var username: String
    @State private var avatarUrl: String
    @State private var focusGoal = ""
    @State private var interests: [String] = []
    @State private var workingStyle = "Deep Focus"
    @State private var sessionPrefDuration = 25
    // Robust timezone Picker setup
    let defaultTimezone = "Asia/Kolkata"
    let timezones: [String] = {
        var zones = TimeZone.knownTimeZoneIdentifiers
        if !zones.contains("Asia/Kolkata") {
            zones.append("Asia/Kolkata")
        }
        return zones.sorted()
    }()
    @State private var timezone = "Asia/Kolkata"
    @State private var availability = "Morning"
    @State private var experienceLevel = "Beginner"
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var onboardingState: OnboardingState

    let workingStyles = ["Deep Focus", "Pomodoro", "Chatty"]
    let experienceLevels = ["Beginner", "Intermediate", "Expert"]
    let availabilityOptions = ["Morning", "Afternoon", "Evening"]

    init(user: User) {
        self.user = user
        // Extract Google name and avatar URL from metadata
        var defaultName = ""
        var defaultAvatarUrl = ""
        if let anyJson = user.userMetadata["full_name"], case let .string(name) = anyJson {
            defaultName = name
        }
        if let anyJson = user.userMetadata["avatar_url"], case let .string(url) = anyJson {
            defaultAvatarUrl = url
        }
        _username = State(initialValue: defaultName)
        _avatarUrl = State(initialValue: defaultAvatarUrl)
    }

    func saveProfile() async {
        isSaving = true
        errorMessage = nil
        let userId = user.id.uuidString
        let email = user.email ?? ""
        let profile = UserProfile(
            id: userId,
            email: email,
            username: username,
            avatar_url: avatarUrl,
            focus_goal: focusGoal,
            interests: interests,
            working_style: workingStyle,
            session_pref_duration: sessionPrefDuration,
            timezone: timezone,
            availability: availability,
            experience_level: experienceLevel,
            is_available: nil, // This will be updated by the backend
            current_session_id: nil // This will be updated by the backend
        )
        do {
            // Upsert user profile (insert or update)
            _ = try await SupabaseManager.shared.client.from("users").upsert(profile).execute()
            await MainActor.run {
                isSaving = false
                onboardingState.showOnboarding = false
            }
        } catch {
            await MainActor.run {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }

    var body: some View {
        VStack(spacing: 32) {
            if step == 0 {
                VStack(alignment: .center, spacing: 20) {
                    // Show Gmail profile image
                    if let url = URL(string: avatarUrl), !avatarUrl.isEmpty {
                        AsyncImage(url: url) { image in
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } placeholder: {
                            ProgressView()
                                .frame(width: 80, height: 80)
                        }
                    } else {
                        Image(systemName: "person.crop.circle")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.gray)
                    }
                    Text("This is your Google profile image.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                    HStack {
                        Image(systemName: "person.text.rectangle")
                        TextField("Username", text: $username)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    Text("Pick a unique name for your profile. Defaulted to your Google name.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                    HStack {
                        Image(systemName: "target")
                        TextField("Focus Goal", text: $focusGoal)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    Text("What do you want to accomplish in your next session?")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                }
            } else if step == 1 {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "tag")
                        TextField("Interests (comma separated)", text: Binding(
                            get: { interests.joined(separator: ", ") },
                            set: { interests = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    Text("Add topics you care about (e.g., coding, design, writing).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                    HStack {
                        Image(systemName: "brain.head.profile")
                        Picker("Working Style", selection: $workingStyle) {
                            ForEach(workingStyles, id: \ .self) { style in
                                Text(style)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    Text("How do you like to work?")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                    HStack {
                        Image(systemName: "timer")
                        Stepper("Session Duration: \(sessionPrefDuration) min", value: $sessionPrefDuration, in: 15...120, step: 5)
                    }
                    Text("Choose your preferred session length.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                }
            } else if step == 2 {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "globe")
                        Picker("Timezone", selection: $timezone) {
                            ForEach(timezones, id: \ .self) { tz in
                                Text(tz)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    Text("Select your timezone for better matching.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                    HStack {
                        Image(systemName: "calendar")
                        Picker("Availability", selection: $availability) {
                            ForEach(availabilityOptions, id: \ .self) { slot in
                                Text(slot)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    Text("When are you usually available to work?")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                    HStack {
                        Image(systemName: "star")
                        Picker("Experience Level", selection: $experienceLevel) {
                            ForEach(experienceLevels, id: \ .self) { level in
                                Text(level)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    Text("How experienced are you in your field?")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                }
            }
            Spacer()
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            if isSaving {
                ProgressView("Saving...")
            }
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .padding()
                }
                Spacer()
                if step < 2 {
                    Button("Next") { step += 1 }
                        .padding()
                } else {
                    Button("Finish") {
                        Task { await saveProfile() }
                    }
                    .padding()
                    .disabled(isSaving)
                }
            }
        }
        .padding()
        .navigationTitle("Onboarding")
    }
}

class OnboardingState: ObservableObject {
    @Published var showOnboarding: Bool = true
}

struct ContentView: View {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var onboardingState = OnboardingState()

    var body: some View {
        NavigationStack {
            if let user = authVM.user {
                ProfileCheckView(user: user)
                    .environmentObject(onboardingState)
                    .environmentObject(authVM)
            } else {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    VStack(spacing: 40) {
                        Spacer()
                        Text("VibinWork")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Find your perfect co-working partner.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                        Button(action: {
                            authVM.signInWithGoogle()
                        }) {
                            HStack {
                                Image(systemName: "globe")
                                    .font(.title2)
                                Text("Sign in with Google")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                        .accessibilityLabel("Sign in with Google")
                        .padding(.horizontal, 32)
                        Spacer()
                    }
                }
            }
        }
    }
}

struct ProfileCheckView: View {
    let user: User
    @EnvironmentObject var onboardingState: OnboardingState
    @State private var isLoading = true
    @State private var error: String? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Checking profile...")
            } else if onboardingState.showOnboarding {
                OnboardingView(user: user)
                    .environmentObject(onboardingState)
            } else {
                MainView(user: user)
            }
        }
        .onAppear {
            Task {
                await checkProfile()
            }
        }
    }

    func checkProfile() async {
        guard let email = user.email else {
            await MainActor.run { onboardingState.showOnboarding = true; isLoading = false }
            return
        }
        do {
            let response = try await SupabaseManager.shared.client
                .from("users")
                .select()
                .eq("email", value: email)
                .single()
                .execute()
            if let profile = try? JSONDecoder().decode(UserProfile.self, from: response.data),
               let username = profile.username, !username.isEmpty {
                await MainActor.run { onboardingState.showOnboarding = false; isLoading = false }
            } else {
                await MainActor.run { onboardingState.showOnboarding = true; isLoading = false }
            }
        } catch {
            await MainActor.run { onboardingState.showOnboarding = true; isLoading = false }
        }
    }
}

// Session creation logic
import Supabase

extension SupabaseManager {
    func createSession(user1Id: String, user2Id: String, durationMinutes: Int?) async throws -> Session {
        let sessionPayload: [String: AnyEncodable] = [
            "user1_id": AnyEncodable(user1Id),
            "user2_id": AnyEncodable(user2Id),
            "status": AnyEncodable("active"),
            "duration_minutes": AnyEncodable(durationMinutes ?? 25)
        ]
        let response = try await client
            .from("sessions")
            .insert(sessionPayload)
            .select()
            .single()
            .execute()
        let session = try JSONDecoder().decode(Session.self, from: response.data)
        return session
    }

    func updateUsersForSession(user1Id: String, user2Id: String, sessionId: String) async throws {
        print("Updating users for session. sessionId: \(sessionId)")
        let updates: [String: AnyEncodable] = [
            "is_available": AnyEncodable(false)
            // "current_session_id": AnyEncodable(sessionId) // Uncomment after testing is_available only
        ]
        print("Update payload: \(updates)")
        // Update both users in parallel
        async let update1 = client.from("users").update(updates).eq("id", value: user1Id).execute()
        async let update2 = client.from("users").update(updates).eq("id", value: user2Id).execute()
        _ = try await (update1, update2)
    }
}

struct RoomDetailsView: View {
    let room: Room
    @Binding var isPresented: Room?
    @State private var participants: [RoomParticipant] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var isJoining = false
    @State private var isStarting = false
    @State private var sessionStarted = false
    @EnvironmentObject var authVM: AuthViewModel

    var isHost: Bool {
        authVM.user?.id.uuidString == room.host_id
    }

    var isParticipant: Bool {
        guard let userId = authVM.user?.id.uuidString else { return false }
        return participants.contains(where: { $0.user_id == userId })
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Room ID: \(room.id)").font(.headline)
            Text("Host: \(room.host_id)")
            Text("Max Participants: \(room.max_participants)")
            Text("Status: \(room.status)")
            Divider()
            if isLoading {
                ProgressView("Loading participants...")
            } else if let error = error {
                Text(error).foregroundColor(.red)
            } else if !isParticipant && !isHost {
                Text("You are not in this room. Tap Join Room to participate.")
                    .foregroundColor(.secondary)
                Button("Join Room") {
                    joinRoom()
                }
                .disabled(isJoining)
                .padding()
                .background(isJoining ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            } else {
                Text("Participants (") + Text("\(participants.count)/\(room.max_participants)") + Text(")")
                List(participants) { p in
                    Text(p.user_id)
                }
                Spacer()
                if sessionStarted {
                    Text("Session started!").foregroundColor(.green)
                } else if isHost {
                    Button("Start Session") {
                        startSession()
                    }
                    .disabled(isStarting || participants.isEmpty)
                    .padding()
                    .background(isStarting ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                } else {
                    Text("Waiting for host to start...").foregroundColor(.orange)
                }
            }
            Button("Close") { isPresented = nil }
                .foregroundColor(.red)
        }
        .padding()
        .onAppear { fetchParticipants() }
    }

    func fetchParticipants() {
        isLoading = true
        error = nil
        Task {
            do {
                let response = try await SupabaseManager.shared.client
                    .from("room_participants")
                    .select()
                    .eq("room_id", value: room.id)
                    .execute()
                let allParticipants = try JSONDecoder().decode([RoomParticipant].self, from: response.data)
                await MainActor.run {
                    self.participants = allParticipants
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func joinRoom() {
        guard let user = authVM.user else { return }
        isJoining = true
        error = nil
        Task {
            do {
                let payload: [String: AnyEncodable] = [
                    "room_id": AnyEncodable(room.id),
                    "user_id": AnyEncodable(user.id.uuidString)
                ]
                _ = try await SupabaseManager.shared.client
                    .from("room_participants")
                    .insert(payload)
                    .select()
                    .single()
                    .execute()
                await MainActor.run {
                    isJoining = false
                    fetchParticipants()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isJoining = false
                }
            }
        }
    }

    func startSession() {
        isStarting = true
        error = nil
        Task {
            do {
                let updates: [String: AnyEncodable] = [
                    "status": AnyEncodable("in_session")
                ]
                _ = try await SupabaseManager.shared.client
                    .from("rooms")
                    .update(updates)
                    .eq("id", value: room.id)
                    .execute()
                await MainActor.run {
                    sessionStarted = true
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isStarting = false
                }
            }
        }
    }
}

struct JoinRoomListView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var rooms: [Room] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var selectedRoom: Room? = nil

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading rooms...")
                } else if let error = error {
                    Text(error).foregroundColor(.red)
                } else if rooms.isEmpty {
                    Text("No open rooms available.")
                        .foregroundColor(.secondary)
                } else {
                    List(rooms) { room in
                        Button(action: { selectedRoom = room }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(room.room_name ?? "Unnamed Room")
                                    .font(.headline)
                                Text("Host: \(room.host_id)")
                                    .font(.subheadline)
                                Text("Participants: ?/\(room.max_participants)") // Will show actual count in details
                                    .font(.caption)
                                Text("Timer: \(room.timer_minutes ?? 0) min")
                                    .font(.caption)
                            }
                        }
                    }
                }
                Spacer()
                Button("Close") { presentationMode.wrappedValue.dismiss() }
                    .foregroundColor(.red)
            }
            .padding()
            .navigationTitle("Join a Room")
            .onAppear { fetchRooms() }
            .sheet(item: $selectedRoom) { room in
                JoinRoomDetailsView(room: room, isPresented: $selectedRoom)
                    .environmentObject(authVM)
            }
        }
    }

    func fetchRooms() {
        isLoading = true
        error = nil
        Task {
            do {
                let response = try await SupabaseManager.shared.client
                    .from("rooms")
                    .select()
                    .eq("status", value: "open")
                    .order("created_at", ascending: false)
                    .execute()
                let allRooms = try JSONDecoder().decode([Room].self, from: response.data)
                await MainActor.run {
                    self.rooms = allRooms
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

// Add ParticipantRow for displaying a user
struct ParticipantRow: View {
    let profile: UserProfile
    var body: some View {
        HStack {
            // Placeholder avatar
            Circle()
                .fill(Color.blue)
                .frame(width: 36, height: 36)
                .overlay(Text(profile.username?.prefix(1).uppercased() ?? "?").foregroundColor(.white))
            VStack(alignment: .leading) {
                Text(profile.username ?? "User")
                    .font(.headline)
                if let goal = profile.focus_goal {
                    Text(goal).font(.subheadline).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct JoinRoomDetailsView: View {
    let room: Room
    @Binding var isPresented: Room?
    @State private var joined = false
    @State private var participants: [UserProfile] = [] // This should include host
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var isJoining = false
    @State private var isStarting = false
    @State private var sessionStarted = false
    @State private var waitingForHost = false
    @State private var roomStatus: String = "open"
    @State private var sessionRoom: Room?
    @State private var hostProfile: UserProfile? = nil
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        if roomStatus == "in_session", let startedRoom = sessionRoom {
            SessionView(room: startedRoom, participantsCount: participants.count + 1)
        } else {
            VStack {
                if isLoading {
                    ProgressView()
                } else if let error = error {
                    Text(error).foregroundColor(.red)
                } else {
                    if !joined {
                        // Show host as the only participant before joining
                        if let hostProfile = getHostProfile() {
                            ParticipantRow(profile: hostProfile)
                        } else {
                            Text("Host info unavailable")
                        }
                        Text("Room is waiting for \(room.max_participants - 1) more participant\(room.max_participants - 1 == 1 ? "" : "s").")
                            .foregroundColor(.secondary)
                    } else {
                        // After joining, show both host and joiner
                        if let hostProfile = getHostProfile() {
                            ParticipantRow(profile: hostProfile)
                        }
                        ForEach(participants.filter { $0.id != room.host_id }) { profile in
                            ParticipantRow(profile: profile)
                        }
                        if (participants.count + 1) >= room.max_participants {
                            Text("Room is full, waiting for host to start.")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                if !joined {
                    Button("Join Room") {
                        joinRoom()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 8)
                }
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.red)
                .padding(.bottom, 16)
            }
            .onAppear {
                print("JoinRoomDetailsView appeared for room: \(room.id)")
                fetchHostProfile()
                if joined {
                    subscribeToParticipants()
                    subscribeToRoomStatus()
                }
            }
            .onDisappear {
                print("JoinRoomDetailsView disappeared")
                unsubscribeFromParticipants()
                unsubscribeFromRoomStatus()
            }
        }
    }
    // Helper to get host profile
    private func getHostProfile() -> UserProfile? {
        return hostProfile
    }
    // Fetch host profile from Supabase
    private func fetchHostProfile() {
        isLoading = true
        Task {
            do {
                let userResp = try await SupabaseManager.shared.client
                    .from("users")
                    .select()
                    .eq("id", value: room.host_id)
                    .single()
                    .execute()
                if let profile = try? JSONDecoder().decode(UserProfile.self, from: userResp.data) {
                    await MainActor.run {
                        self.hostProfile = profile
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.error = "Failed to decode host profile."
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to fetch host profile."
                    self.isLoading = false
                }
            }
        }
    }
    // Subscribe to participants in real time
    private func subscribeToParticipants() {
        RealtimeManager.shared.subscribeToParticipants(roomId: room.id) { updatedParticipants in
            Task {
                var profiles: [UserProfile] = []
                for p in updatedParticipants {
                    do {
                        let userResp = try await SupabaseManager.shared.client
                            .from("users")
                            .select()
                            .eq("id", value: p.user_id)
                            .single()
                            .execute()
                        if let profile = try? JSONDecoder().decode(UserProfile.self, from: userResp.data) {
                            profiles.append(profile)
                        }
                    } catch {
                        // Optionally log error
                    }
                }
                await MainActor.run {
                    self.participants = profiles
                }
            }
        }
    }
    // Subscribe to room status in real time
    private func subscribeToRoomStatus() {
        RealtimeManager.shared.subscribeToRoomStatus(roomId: room.id) { updatedRoom in
            DispatchQueue.main.async {
                print("[Joiner] Room status update: \(updatedRoom.status)")
                self.roomStatus = updatedRoom.status
                self.sessionRoom = updatedRoom
            }
        }
    }
    // Unsubscribe from participants and room status
    private func unsubscribeFromParticipants() {
        RealtimeManager.shared.unsubscribeParticipants()
    }
    private func unsubscribeFromRoomStatus() {
        RealtimeManager.shared.unsubscribeRoomStatus()
    }

    private func joinRoom() {
        guard let user = authVM.user else {
            self.error = "User not authenticated."
            return
        }
        isJoining = true
        error = nil
        Task {
            do {
                let payload: [String: AnyEncodable] = [
                    "room_id": AnyEncodable(room.id),
                    "user_id": AnyEncodable(user.id.uuidString)
                ]
                _ = try await SupabaseManager.shared.client
                    .from("room_participants")
                    .insert(payload)
                    .execute()
                await MainActor.run {
                    self.isJoining = false
                    self.joined = true
                    self.waitingForHost = true
                    self.subscribeToParticipants()
                    self.subscribeToRoomStatus() // Ensure joiner listens for session start
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to join room: \(error.localizedDescription)"
                    self.isJoining = false
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
