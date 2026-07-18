# Data Core & Database Schema

This document details the database schema paths under the `/seva/` root in the Firebase Realtime Database (RTDB), model validation rules, custom BCrypt password hashing, and local session management boundaries.

---

## 1. Firebase Realtime Database Schema Paths

All data in SevaSetu is nested under the `/seva` root key to isolate the app environment. The paths, operations, and attributes are structured as follows:

### 1.1 `/seva/users/<userId>`
Stores devotee, temple, and priest credentials and profile metadata.
* **Fields**:
  * `name` (String): Full name of the user.
  * `email` (String): Email address (used for lookup in custom auth).
  * `phone` (String): Contact number.
  * `passwordHash` (String): BCrypt hash of the plaintext password.
  * `securityQuestion` (String): Password recovery question.
  * `securityAnswer` (String): Password recovery answer.
  * `profilePic` (String): HTTPS URL of avatar.
  * `bio` (String): Short biography.
  * `role` (String): Either `"user"`, `"temple"`, or `"priest"`.

### 1.2 `/seva/temples/<templeId>`
Stores temple profile info and associated priest invite states.
* **Fields**:
  * `name` (String): Temple name.
  * `description` (String): Core description of deity and temple.
  * `address` (String): Location details.
  * `contact` (String): Public phone number.
  * `profileImage` (String): Profile thumbnail URL.
  * `coverImage` (String): Landscape banner image URL.
  * `galleryImages` (List of Strings): URLs of temple views.
  * `ownerUid` (String): Admin user ID linked to this temple.
  * `activePriests` (Map of `<priestId>` to Status): Status states: `"pending"`, `"accepted"`, `"rejected"`.

### 1.3 `/seva/priests/<priestId>`
Stores priest bio, experience, and astrological parameters.
* **Fields**:
  * `name` (String): Priest's full name.
  * `dob` (String): Date of birth (`YYYY-MM-DD`).
  * `age` (int): Calculated age.
  * `gender` (String): `"Male"` or `"Female"`.
  * `mobile` (String): Contact mobile.
  * `email` (String): Contact email.
  * `address` (String): Resident address.
  * `experience` (String): Years of practice.
  * `rasi` (String): Moon sign (e.g. `"Mesha"`).
  * `nakshatra` (String): Birth star.
  * `lagnam` (String): Ascendant sign.
  * `bio` (String): Specialty details.
  * `photo` (String): Avatar image URL.

### 1.4 `/seva/services/<serviceId>`
Lists temple pujas and independent priest private services.
* **Fields**:
  * `templeId` (String): Owning temple ID (empty for private services).
  * `priestId` (String): Owning priest ID (empty for temple services).
  * `name` (String): Name of the puja.
  * `description` (String): What the puja includes.
  * `amount` (double): Cost in INR.
  * `maxParticipants` (int): Limit of participants.
  * `duration` (String): Expected time (e.g., `"1 Hour"`).
  * `image` (String): Banner photo URL.

### 1.5 `/seva/orders/<orderId>`
Booking records of pujas.
* **Fields**:
  * `userId` (String): Devotee user ID.
  * `userName` (String): Devotee name.
  * `templeId` (String): Temple ID (empty for private service).
  * `templeName` (String): Cached temple name.
  * `priestId` (String): Target priest ID.
  * `serviceId` (String): Original service ID.
  * `serviceName` (String): Service title.
  * `assignedPriest` (String): Priest ID carrying out the service.
  * `assignedPriestName` (String): Priest name.
  * `bookingDate` (String): Booking target date (`YYYY-MM-DD`).
  * `bookingTime` (String): Target slot.
  * `amount` (double): Amount paid.
  * `status` (String): `"pending"` | `"accepted"` | `"assigned"` | `"completed"` | `"cancelled"`.
  * `paymentStatus` (String): `"pending"` | `"success"`.
  * `paymentReference` (String): Razorpay transaction reference.
  * `jitsiLink` (String): Video room URL for remote attendance.
  * `createdAt` (int): Epoch timestamp.

### 1.6 `/seva/posts/<postId>`, `/seva/likes`, `/seva/comments`
Social wall and feed data.
* **Fields**:
  * `/posts/<postId>`: `authorId`, `authorName`, `authorImage`, `imageUrl`, `caption`, `timestamp`.
  * `/likes/<postId>/<userId>`: `true` if liked, removed if unliked.
  * `/comments/<postId>/<commentId>`: `userId`, `userName`, `content`, `timestamp`.

---

## 2. Models Parsing and Validation

Each database model class implements `fromJson` and `toJson` validation rules to ensure safe casting:
* **String Safeness**: Casts raw inputs via `.toString()` with safe default values `?? ''`.
* **Number Safeness**: Safe conversions using `int.tryParse` or `double.tryParse` with default values `?? 0.0`.
* **Dynamic Maps/Lists**: Maps lists and dictionaries through checks (`is Map`, `is List`) to handle empty results dynamically.

---

## 3. Custom Authentication and Session Failsafe

### Password Encryption
Password security uses standard `bcrypt` hashing on the client side:
* **Creation**: Hashed with a random salt via `BCrypt.hashpw(password, BCrypt.gensalt())`.
* **Comparison**: Match verified via `BCrypt.checkpw(plaintext, hashedValue)`.

### Session Persistent Failsafe
To prevent Pigeon platform channel exceptions (e.g. `PlatformException(channel-error, Unable to establish connection...)`) from freezing the app on specific emulators, browsers, or during hot restarts:
1. At initialization, a connection check is performed on `SharedPreferences.getInstance()`.
2. If it succeeds, data persists to native disk.
3. If it throws an exception or times out, the flag `_useSharedPreferences` is set to `false`.
4. Subsequent calls bypass the native channel completely and store/read sessions in-memory, keeping the user signed in for the duration of the run.
