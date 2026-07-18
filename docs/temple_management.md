# Temple Management Flow

This document details the features, dashboards, and data pipelines built for Temple Administrators in SevaSetu.

---

## 1. Metrics & Earnings Dashboard

Upon signing in, Temple Admins land on the `TempleDashboard` (Home Tab).
* **Data Synced**:
  * On init, `AppProvider.listenUserSessions` is invoked with `UserRole.temple` to listen only to orders matching this temple's ID:
    `FirebaseDatabase.instance.ref('seva/orders').orderByChild('templeId').equalTo(templeId)`
* **Dashboard Logic**:
  * **Total Income**: Sums up the `amount` of all bookings with `status == 'completed'` or `paymentStatus == 'success'`.
  * **Pending Orders**: Count of orders in `"pending"` status.
  * **Active Bookings**: Count of orders in `"accepted"` or `"assigned"` state.
  * **Active Priests Count**: Count of priests registered with the temple under the status `"accepted"`.

---

## 2. Managing Temple Services

Temple Admins can create and edit the list of spiritual services/pujas they offer.
* **Sync Actions**:
  * **Pull**: Subscribed via `AppProvider.listenAllGlobalData` filtering matching service IDs.
  * **Push**:
    * **Path**: `/seva/services/<serviceId>`
    * **Structure**: Created with a unique push key. The service record cached the `templeId` but leaves `priestId` blank, indicating it is a temple-managed puja.
    * **Attributes**: Includes name, description, duration, price, max participants, and an illustration image URL.

---

## 3. Priest Invites & Association Registry

Temples can manage their registry of active priests to conduct their bookings.
* **Invite Mechanisms**:
  1. **Add Custom Priest**: Temple Admins can directly create a new priest login account. The account is created under `/seva/users` with password encrypted via BCrypt, and a corresponding profile is pushed to `/seva/priests` and marked immediately as `"accepted"` in the temple's active priest list:
     `/seva/temples/<templeId>/activePriests/<priestId> = "accepted"`
  2. **Invite Existing Priest**: Temple Admins can select an existing independent priest from the directory and click "Invite". This pushes a notification to the priest and writes a `"pending"` link under the temple's priest status subnode:
     `/seva/temples/<templeId>/activePriests/<priestId> = "pending"`

---

## 4. Bookings & Order Assignment

When a devotee books a temple service, the order enters a pending queue.
* **Assignment Workflow**:
  1. The order arrives in `/seva/orders` with `assignedPriest == ""` (Temple Assigned).
  2. The Temple Admin views the order and clicks "Assign Priest".
  3. The app presents a sheet listing all active priests whose status is `"accepted"`.
  4. Upon selection, the Temple Admin updates the order node in the database:
     * `assignedPriest` is updated with the selected Priest's ID.
     * `assignedPriestName` is updated with the Priest's name.
     * `status` is transitioned to `"assigned"`.
  5. The priest receives a booking notification immediately.
