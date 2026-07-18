# Feature Documentation: Authentication & Session Management

This document explains how the custom authentication system and local session persistence are implemented in SevaSetu, including data retrieval, structures, and failsafes.

---

## 1. How It Works
SevaSetu implements a **custom authentication flow** on top of the Firebase Realtime Database (RTDB), completely independent of Firebase Authentication. This satisfies the requirement to manage users, passwords, and sessions manually.

### Sign-up Flow
1. The user inputs their Full Name, Phone, Email, Password, Security Question & Answer, Role selection, and selects or uploads a Profile Photo.
2. The password is encrypted on the client using the standard `bcrypt` hashing algorithm (a salt is generated using `BCrypt.gensalt()` and applied via `BCrypt.hashpw(password, salt)`).
3. The hashed password and security details are stored directly under the `/seva/users/<userId>` node in the database.
4. If the registering role is `temple` or `priest`, a corresponding profile is created under `/seva/temples/<userId>` or `/seva/priests/<userId>`.

### Sign-in Flow
1. The user enters their email and plaintext password.
2. The system queries the database under `/seva/users` to find a matching email.
3. If found, the client performs a bcrypt comparison check using `BCrypt.checkpw(enteredPassword, storedHash)`.
4. If verified, the session details are written and the user is routed to their home dashboard.

### Forgot Password / Reset Flow
1. The user enters their email.
2. The system retrieves the security question linked to the user.
3. The user inputs the answer and their new password.
4. The system validates the answer case-insensitively, hashes the new password, and updates the database node.

---

## 2. Session Management & Failsafe
To manage local logins across app relaunches, the system uses `shared_preferences`.

### Platform Failsafe
Because certain web browsers and mobile emulators throw platform channel errors during unit testing or hot restarts, a **bulletproof in-memory fallback** has been implemented.
* If `SharedPreferences.getInstance()` throws an exception, the system catches the error and persists the session details inside private variables (`_fallbackUserId`, `_fallbackUserRole`) in `FirebaseService`.
* This ensures that signup, signin, and transitions never crash even if the device storage channel fails.

---

## 3. Data Structures & Mappings

### Data Pulled:
* **User Node**: `/seva/users/<userId>`
  * `name`: String
  * `email`: String
  * `phone`: String
  * `passwordHash`: String (bcrypt encrypted)
  * `securityQuestion`: String
  * `securityAnswer`: String
  * `profilePic`: String (HTTPS URL)
  * `role`: String (`user` | `temple` | `priest`)

### Data Pushed:
* **Session Persistence**:
  * `session_user_id`: String (stored in SharedPreferences or fallback variable)
  * `session_user_role`: String (stored in SharedPreferences or fallback variable)
