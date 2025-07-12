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

struct MainView: View {
    let user: User
    var body: some View {
        let fullName: String = {
            if let anyJson = user.userMetadata["full_name"], case let .string(name) = anyJson {
                return name
            }
            return "User"
        }()
        VStack(spacing: 16) {
            Text("Welcome, \(fullName)!")
                .font(.title)
            Text("Email: \(user.email ?? "N/A")")
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct ContentView: View {
    @StateObject private var authVM = AuthViewModel()

    var body: some View {
        NavigationStack {
            if let user = authVM.user {
                MainView(user: user)
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
