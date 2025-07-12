# 🧑‍🤝‍🧑 VibinWork — iOS App

An iOS productivity app that matches users for real-time, one-on-one, timed co-working sessions with similar interests. Built using SwiftUI, Supabase, and integrated with a voice SDK (Agora).

---

## 📌 MVP Feature Overview

- ✅ User Authentication (Google Sign-In via Supabase, fully implemented)
- ✅ Profile creation with goals/interests (Onboarding flow implemented, data saved to Supabase)
- 🤝 Matchmaking with real-time availability
- 🎙️ In-app 1:1 voice call
- ⏱️ Timer-based sessions (e.g., 25/50 min)
- ✅ Session end cleanup (disconnect + free up users)
- 🗒️ (Optional) Post-session feedback

---

## 🧱 Stack Overview

| Layer        | Tech Stack                                                  |
|--------------|-------------------------------------------------------------|
| **Frontend** | SwiftUI (iOS), Combine                                      |
| **Backend**  | Supabase (PostgreSQL, Auth, Edge Functions, Realtime)       |
| **Voice SDK**|  Agora                                                      |
| **Storage**  | Supabase Storage (user avatars etc.)                        |
| **DevOps**   | Xcode, Git, TestFlight, App Store Connect                   |

---

## 📐 Database Schema (Supabase)

### `users`

| Field                  | Type                      | Description                                 |
|------------------------|---------------------------|---------------------------------------------|
| id                     | UUID                      | Primary Key                                 |
| email                  | Text                      | Unique (from Supabase Auth)                 |
| username               | Text                      | Display name or nickname                    |
| avatar_url             | Text                      | Profile picture URL                         |
| focus_goal             | Text                      | Short description of current work goal      |
| interests              | Text[]                    | Interest tags (multi-select)                |
| working_style          | Text                      | e.g., Deep focus, Pomodoro, Chatty          |
| session_pref_duration  | Integer                   | Preferred session length in minutes         |
| timezone               | Text                      | e.g., Asia/Kolkata                          |
| availability           | JSON                      | Time blocks (optional MVP)                  |
| experience_level       | Text                      | Beginner / Intermediate / Expert            |
| is_available           | Boolean                   | Real-time status for matchmaking            |
| current_session_id     | UUID                      | FK to `sessions.id`                         |
| created_at             | Timestamp with time zone  | Default: `now()`                            |

---

### `sessions`

| Field             | Type                      | Description                          |
|------------------|---------------------------|--------------------------------------|
| id               | UUID                      | Primary Key                          |
| user1_id         | UUID                      | FK to `users.id`                     |
| user2_id         | UUID                      | FK to `users.id`                     |
| start_time       | Timestamp with time zone  | UTC                                  |
| end_time         | Timestamp with time zone  | UTC                                  |
| status           | Text                      | 'active' / 'completed' / 'cancelled' |
| duration_minutes | Integer                   | Optional, duration in minutes        |
| voice_room_id    | Text                      | Used by voice SDK                    |
| created_at       | Timestamp with time zone  | Default: `now()`                     |

---

### `feedback` _(optional)_

| Field         | Type                      | Description                  |
|---------------|---------------------------|------------------------------|
| id            | UUID                      | Primary Key                  |
| session_id    | UUID                      | FK to `sessions.id`          |
| submitted_by  | UUID                      | FK to `users.id`             |
| rating        | Integer                   | 1–5                          |
| comment       | Text                      | Free text comment            |
| created_at    | Timestamp with time zone  | Default: `now()`             |

---

## ⚙️ Supabase Setup

- [x] Create project on Supabase
- [x] Enable Google Sign-in (fully working, tested in app)
- [ ] Enable Apple Sign-in (not implemented yet)
- [x] Setup tables: `users`, `sessions`, `feedback` (optional)
- [x] Configure RLS (Row-Level Security) policies:
  - Users can only update their own records
  - Users can only see sessions/feedback they’re part of
- [x] Enable Realtime on `users` and `sessions`
- [x] Create Edge Functions (e.g., `matchmake.ts`) to handle session pairing

---

## 🔧 Core Features Implementation Plan

### ✅ Authentication
- Use `@supabase/supabase-swift`
- Google login with secure session handling (fully implemented)
- Store session token in Keychain
- Only Google sign-in is implemented for now (Apple sign-in pending)

---

### ✅ Onboarding / Profile Setup

- Onboarding flow is live and collects:
  - Username (auto-filled from Google)
  - Google profile image (avatar)
  - Focus goal
  - Interests (multi-select)
  - Working style (dropdown)
  - Session preferred duration (picker)
  - Timezone (dropdown, default Asia/Kolkata)
  - Availability (dropdown)
  - Experience level (dropdown)
- Data is saved to the Supabase `users` table on completion.

---

### 🔄 Matchmaking Logic
- User taps “Find Partner”
- Search `users` where `is_available = true` and match tags/timezone
- If match found:
  - Create new `session`
  - Set both users' `is_available = false`
  - Set their `current_session_id` to session ID
- If no match:
  - Poll or wait with retry mechanism

---

### 🎙️ Voice Call (Pick One)

#### Option A: **Twilio Voice**
- Twilio Programmable Voice SDK
- Access tokens generated via Supabase Edge Function

#### Option B: **Agora**
- Use Agora iOS SDK
- Create session-specific channel

#### Option C: **Daily.co**
- Daily Swift SDK
- Lightweight WebRTC

---

### ⏱️ Session Timer
- Start timer when session begins
- Disconnect automatically when timer ends
- Update `session.status = completed`, reset user states

---

## 🧪 Testing Plan

| Component     | Tests                                 |
|---------------|----------------------------------------|
| Auth          | Sign up, sign in, session restore      |
| Onboarding    | Validate and insert profile data       |
| Matchmaking   | User pairing logic + edge cases        |
| Sessions      | Timer, cleanup, status transitions     |
| Voice         | Join, leave, failover handling         |
| Realtime      | Reflect live status + session state    |

---

## 🎨 Future Enhancements

- 🔁 Re-match with previous partners
- 🔔 Push notifications (e.g., session reminders)
- 🌍 Match based on language, region, or timezone
- 🤖 AI-based smart pairing
- 📈 User productivity insights or streaks
- 💬 Optional in-session chat

---

## 🗂 Suggested Folder Structure

📁 VibinWorkApp
├── 📁 Models
├── 📁 Views
├── 📁 ViewModels
├── 📁 Services
│ ├── SupabaseManager.swift
│ ├── Matchmaker.swift
│ └── VoiceService.swift
├── 📁 Components
│ ├── TimerView.swift
│ ├── MatchLoadingView.swift
│ └── SessionCard.swift
├── 📄 App.swift
└── 📄 Info.plist

---

## 📦 Packages To Add

- `@supabase/supabase-swift`
- `TwilioVoice` or `AgoraRtcKit` or `DailySwift`
- `CombineExt` for reactive patterns
- `SwiftLint` for linting and clean code

---

## 🚀 Launch Checklist

- [x] Complete authentication (Google sign-in)
- [x] Complete onboarding (profile creation, save to Supabase)
- [ ] Complete onboarding → match → call flow
- [ ] Run end-to-end manual tests
- [ ] Push to TestFlight and gather feedback
- [ ] Add App Store metadata (screenshots, privacy, icons)
- [ ] Submit for App Store review

---

## 🧠 Notes

- Always validate session start/end server-side via Edge Functions
- Use Supabase Realtime listeners to live update session & user state
- Store call room IDs for debug/logging

---

> 💬 _“Build focused, together.”_
