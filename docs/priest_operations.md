# Priest Operations Flow

This document details the dashboard, features, and remote livestream integrations built for Priests in SevaSetu.

---

## 1. Priest Dashboard & Bookings Management

Priests interact with bookings through the `PriestDashboard`.
* **Data Synced**:
  * On init, the dashboard subscribes to orders matching the priest's ID as the assigned practitioner:
    `FirebaseDatabase.instance.ref('seva/orders').orderByChild('assignedPriest').equalTo(priestId)`
* **Tab Categorization**:
  * **Pending**: Orders assigned by temple admins that need priest acceptance (status `"assigned"`).
  * **Upcoming**: Accepted bookings (status `"accepted"`) ready to be performed.
  * **Completed**: Concluded bookings (status `"completed"`).
* **Actions**:
  * **Accept Booking**: Changes order status to `"accepted"`. This triggers a notification to the devotee and starts the live link preparation.
  * **Complete Booking**: Marks order status as `"completed"`.

---

## 2. Responding to Temple Invites

Priests can receive invitations from multiple temples to join their active roster.
* **Sync Actions**:
  * **Pull**: Subscribes to notification and temple updates.
  * **Push**:
    * When a priest clicks "Accept" or "Reject" on an invitation, they write their response directly to the temple's configuration node in RTDB:
      `/seva/temples/<templeId>/activePriests/<priestId> = "accepted"` (or `"rejected"`)
    * Pushes a response notification back to the Temple Admin.

---

## 3. Private Services CRUD

Priests can offer direct, private spiritual services (such as home pujas or personal horoscope readings) that devotees can book directly without temple involvement.
* **Sync Actions**:
  * **Pull**: Subscribed on app loading to view active offerings.
  * **Push**:
    * **Path**: `/seva/services/<serviceId>`
    * **Structure**: Created under the global services node, but populated with the `priestId` and leaving `templeId` empty.
    * Devotees will see these services under the priest's detail sheet on the Explore tab instead of the Temple details sheet.

---

## 4. Jitsi Meet Live Stream Integration

To allow devotees to participate in pujas remotely, Jitsi Meet streams are linked directly to each booking:
* **Mechanism**:
  * When a booking is finalized, a secure room link is generated using the Jitsi Meet format:
    `https://meet.jit.si/sevasetu_<serviceId>_<timestamp>`
  * **Priest Stream**: The priest joins the room by clicking "JOIN LIVE" in the dashboard. The Jitsi Meet link is opened in the system browser or Jitsi Meet app.
  * **Devotee Stream**: The devotee gets access to the identical Jitsi link on their "My Bookings" receipt card to watch the livestream live.
