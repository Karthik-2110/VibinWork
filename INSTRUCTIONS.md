# 🧑‍🤝‍🧑 VibinWork — iOS App

An iOS productivity app for real-time, timed co-working sessions in user-created rooms. Built using SwiftUI and Supabase.

---

## 📌 MVP Feature Overview

- ✅ **User Authentication:** Google Sign-In via Supabase.
- ✅ **Profile Creation:** Onboarding flow to collect user details.
- ✅ **Room-Based Sessions:**
    - Create rooms with custom names, participant limits, and timer durations.
    - Browse and join existing open rooms.
- ✅ **Real-Time Waiting Room:**
    - Host and participants wait in a lobby.
    - Participant list updates in real-time for everyone.
- ✅ **Synchronized Session Timer:**
    - Host starts the session for all participants.
    - A shared, robust timer keeps everyone in sync, regardless of timezone.
- 🎙️ **In-app Voice Call:** (Next Step) Integration with a voice SDK.

---

## 🧱 Stack Overview

| Layer        | Tech Stack                                                  |
|--------------|-------------------------------------------------------------|
| **Frontend** | SwiftUI (iOS), Combine                                      |
| **Backend**  | Supabase (PostgreSQL, Auth, Realtime)                       |
| **Voice SDK**|  TBD (e.g., Agora, Twilio)                                  |
| **Storage**  | Supabase Storage (user avatars etc.)                        |
| **DevOps**   | Xcode, Git, TestFlight, App Store Connect                   |

---

## 📐 Database Schema (Supabase)

### `users`

| Field                  | Type                      | Description                                 |
|------------------------|---------------------------|---------------------------------------------|
| id                     | UUID                      | Primary Key (from Supabase Auth)            |
| email                  | Text                      | Unique                                      |
| username               | Text                      | Display name                                |
| avatar_url             | Text                      | Profile picture URL                         |
| focus_goal             | Text                      | Short description of current work goal      |
| ... (other fields)     | ...                       | ...                                         |
| created_at             | Timestamp with time zone  | Default: `now()`                            |

### `rooms`

| Field                   | Type                      | Description                                     |
|-------------------------|---------------------------|-------------------------------------------------|
| id                      | UUID                      | Primary Key                                     |
| host_id                 | UUID                      | FK to `users.id`                                |
| max_participants        | Integer                   | Maximum number of users allowed in the room     |
| status                  | Text                      | 'open' / 'in_session' / 'completed'             |
| room_name               | Text                      | Custom name for the room                        |
| timer_minutes           | Integer                   | Session duration in minutes                     |
| session_started_epoch   | BigInt                    | UNIX epoch (UTC seconds) for synchronized timer |
| created_at              | Timestamp with time zone  | Default: `now()`                                |

### `room_participants`

| Field      | Type                      | Description              |
|------------|---------------------------|--------------------------|
| id         | UUID                      | Primary Key              |
| room_id    | UUID                      | FK to `rooms.id`         |
| user_id    | UUID                      | FK to `users.id`         |
| joined_at  | Timestamp with time zone  | Default: `now()`         |

---

## ⚙️ Supabase Setup

- ✅ **Project Creation:** Project is live on Supabase.
- ✅ **Authentication:** Google Sign-in is enabled and integrated.
- ✅ **Database Tables:**
  - `users` table is set up.
  - `rooms` and `room_participants` tables are created and in use.
- ✅ **Row-Level Security (RLS):**
  - Basic policies are in place. Users can update their own records.
- ✅ **Realtime:**
  - Enabled on `rooms` and `room_participants` to power the live waiting room and session start.

---

## 🔧 Core Features Implementation Plan

### ✅ Authentication
- Uses `@supabase/supabase-swift`.
- Secure Google login and session handling is fully implemented.

---

### ✅ Onboarding / Profile Setup
- A multi-step onboarding flow collects user profile information.
- Data is saved to the Supabase `users` table upon completion.

---

### ✅ Room & Session Flow
- **Create Room:** Users can create a new room, setting a name, participant limit, and timer duration.
- **Join Room:** Users can see a list of `open` rooms and join them.
- **Waiting Room (Host View):** The host sees participants join in real-time and can manually start the session.
- **Waiting Room (Joiner View):** Participants see who is in the room and wait for the host to begin.
- **Real-time Updates:** A `RealtimeManager` handles Supabase Realtime subscriptions to keep room status and participant lists synchronized.

---

### ✅ Session Timer
- When the host starts the session, a `session_started_epoch` (UNIX timestamp) is saved to the `rooms` table.
- All clients use this epoch value to initialize a synchronized countdown timer.
- This approach is robust and works accurately across all timezones.

---

### 🎙️ Voice Call (Next Step)
- The next major feature is to integrate a voice SDK (e.g., Agora, Twilio) for in-session communication.

---

## 🧪 Testing Plan

| Component     | Tests                                         | Status      |
|---------------|-----------------------------------------------|-------------|
| Auth          | Sign up, sign in, session restore             | ✅ Complete |
| Onboarding    | Profile data validation and saving            | ✅ Complete |
| Rooms         | Create, join, real-time updates               | ✅ Complete |
| Sessions      | Synchronized timer, status transitions        | ✅ Complete |
| Voice         | Join, leave, mute                             | 🚧 Pending  |
| Realtime      | Live updates for participants & room status   | ✅ Complete |

---

## 🚀 Launch Checklist

- ✅ Complete authentication (Google sign-in)
- ✅ Complete onboarding (profile creation)
- ✅ Complete room creation and joining flow
- ✅ Complete real-time synchronized session timer
- 🚧 Implement in-app voice call
- ⬜️ Run end-to-end manual tests
- ⬜️ Push to TestFlight and gather feedback
- ⬜️ Add App Store metadata
- ⬜️ Submit for App Store review

---

## 🧠 Notes

- The timer is driven by a UTC-based UNIX epoch (`session_started_epoch`) to ensure it's timezone-proof.
- Realtime subscriptions on the `rooms` and `room_participants` tables are critical for the user experience.
- The initial 1:1 matchmaking concept has been replaced by a more flexible, user-driven room model.

---

> 💬 _“Build focused, together.”_
