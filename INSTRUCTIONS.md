# 🧑‍🤝‍🧑 VibinWork — iOS App

An iOS productivity app that matches users for real-time, one-on-one, timed co-working sessions with similar interests. Built using SwiftUI, Supabase, and integrated with a voice SDK (Twilio/Agora/Daily).

---

## 📌 MVP Feature Overview

- 🔐 User Authentication (Email, Apple Sign-In)
- 🎯 Profile creation with goals/interests
- 🤝 Matchmaking with real-time availability
- 🎙️ In-app 1:1 voice call
- ⏱️ Timer-based sessions (e.g., 25/50 min)
- ✅ Session end cleanup (disconnect + free up users)
- 🗒️ (Optional) Post-session feedback

---

## 🧱 Stack Overview

| Layer | Tech Stack |
|-------|------------|
| **Frontend** | SwiftUI (iOS), Combine |
| **Backend** | Supabase (PostgreSQL, Auth, Edge Functions, Realtime) |
| **Voice SDK** | Twilio Voice / Agora / Daily.co (Pick 1) |
| **Storage** | Supabase Storage (user avatars etc.) |
| **DevOps** | Xcode, Git, TestFlight, App Store Connect |

---

## 📐 Database Schema (Supabase)

### `users`
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary Key |
| email | Text | Unique |
| username | Text | Display name |
| interests | Text[] | Array of interest tags |
| is_available | Boolean | True = looking for session |
| current_session_id | UUID | FK to `sessions.id` |
| created_at | Timestamp | — |

### `sessions`
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary Key |
| user1_id | UUID | FK to `users.id` |
| user2_id | UUID | FK to `users.id` |
| start_time | Timestamp | UTC |
| end_time | Timestamp | UTC |
| status | Text | 'active' / 'completed' / 'cancelled' |

### `feedback` _(optional)_
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary Key |
| session_id | UUID | FK to `sessions.id` |
| submitted_by | UUID | FK to `users.id` |
| rating | Integer | 1–5 |
| comment | Text | Free text |

---

## ⚙️ Supabase Setup

- [x] Create project on Supabase
- [x] Enable Email and Apple Sign-in
- [x] Setup tables (`users`, `sessions`, optionally `feedback`)
- [x] Configure RLS policies for:
  - Users can only update their own data
  - Only session participants can read/write to session
- [x] Enable Realtime on `users` and `sessions`
- [x] Create edge function (e.g., `matchmake.ts`) for pairing logic

---

## 🔧 Core Features Implementation Plan

### ✅ Authentication
- Swift Package: `Supabase/Auth`
- Handle login, signup, session restore
- Store session token securely

### 👤 Onboarding/Profile Setup
- Collect: username, interests (multi-select), working style
- Upload to Supabase `users` table

### 🔄 Matchmaking Logic
- User taps “Find Partner”
- Check for available users with similar interests (`is_available = true`)
- If match found:
  - Create session in `sessions` table
  - Update both users’ `is_available = false`
  - Set `current_session_id`
- If no match: wait or retry

### 🎙️ Voice Call (Pick One)
#### Option A: **Twilio Voice**
- Twilio Programmable Voice SDK
- Generate Access Token (via Supabase Function)
- Create room with two participants

#### Option B: **Agora**
- Use Agora iOS SDK
- Create channel per session (`session:id`)
- Manage join/leave via tokens

#### Option C: **Daily.co**
- WebRTC via Daily Swift SDK
- Simple integration + browser fallback

### ⏱️ Session Timer
- Start timer when call connects
- Auto-disconnect after N minutes
- Cleanup: mark users as available, clear `current_session_id`, set session status

---

## 🧪 Testing Plan

| Component | Test |
|----------|------|
| Auth | Signup/login/logout workflows |
| Matchmaking | Simulate 2+ users finding partners |
| Timer | Auto disconnect logic |
| Voice | End-to-end call setup/teardown |
| Realtime | UI updates on user/session changes |

---

## 🎨 Future Enhancements

- 🔁 Re-match with past partner
- 🔔 Push Notifications (e.g., session reminders)
- 🌎 Language filters / regional match
- 🧠 AI-based matching by personality
- 📊 User productivity analytics
- 💬 Text-based chat during session

---

## 🗂 File/Folder Structure Suggestion

📁 FindMyPartnerApp
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
- `CombineExt` (for publishers/operators)
- `SwiftLint` for code quality

---

## 🚀 Launch Checklist

- [ ] Complete core session flow
- [ ] Test end-to-end with multiple users
- [ ] Beta test via TestFlight
- [ ] Add App Store screenshots, privacy policy, app icons
- [ ] Submit for review

---

## 🧠 Notes

- All session logic must be server-verified (no client-side trust)
- Consider Supabase Functions to handle matchmaking or cleanups
- Use Supabase Realtime to listen to session state updates

---

> 💬 *“Build focused, together.”*

