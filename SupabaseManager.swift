import Foundation
import Supabase

class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient

    private init() {
        let supabaseUrl = URL(string: "https://ignlkiboenpsdkikhbpn.supabase.co")!
        let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlnbmxraWJvZW5wc2RraWtoYnBuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTIzNDc5NTAsImV4cCI6MjA2NzkyMzk1MH0.ftL4yYDV54iNCCZfCoGBDfAe7BNYiVZUT4HbKpZnNOU"
        client = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseKey)
    }

    func signInWithGoogle() async throws {
        try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: URL(string: "karthik.devs.VibinWork://")
        )
    }

    @MainActor
    func handleOpenURL(_ url: URL) async {
        do {
            _ = try await client.auth.session(from: url)
        } catch {
            print("Failed to handle redirect URL: \(error)")
        }
    }
}
