//
//  ContentView.swift
//  VibinWork
//
//  Created by Karthik  on 13/07/25.
//

import SwiftUI
import Supabase

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

struct UserProfile: Decodable, Encodable {
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
}

struct MainView: View {
    let user: User
    @State private var isMatching = false
    var body: some View {
        let fullName: String = {
            if let anyJson = user.userMetadata["full_name"], case let .string(name) = anyJson {
                return name
            }
            return "User"
        }()
        VStack(spacing: 24) {
            Text("Welcome, \(fullName)!")
                .font(.title)
            Text("Email: \(user.email ?? "N/A")")
                .foregroundColor(.secondary)
            Spacer().frame(height: 32)
            Button(action: {
                isMatching = true
            }) {
                HStack {
                    Image(systemName: "person.2.fill")
                    Text("Find Partner")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .accessibilityLabel("Find Partner")
            .padding(.horizontal, 32)
            Spacer()
        }
        .padding()
        .fullScreenCover(isPresented: $isMatching) {
            MatchLoadingView(isPresented: $isMatching)
        }
    }
}

struct MatchLoadingView: View {
    @Binding var isPresented: Bool
    var body: some View {
        VStack(spacing: 32) {
            ProgressView()
                .scaleEffect(2)
            Text("Looking for a partner...")
                .font(.title2)
                .fontWeight(.medium)
            Button("Cancel") {
                isPresented = false
            }
            .foregroundColor(.red)
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(0.95))
        .ignoresSafeArea()
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
            experience_level: experienceLevel
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
