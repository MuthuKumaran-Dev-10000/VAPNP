# SevaSetu v1 App Flow & System Specification

This document defines the comprehensive user journeys, operational workflows, state transitions, and database schema mappings for the **SevaSetu** production platform.

---

## 1. Authentication & Role-Based Routing Flow

```text
               [ Login / Registration ]
                          │
                  Identify User Role
                          │
         ┌────────────────┼────────────────┐
         ▼                ▼                ▼
   [ UserRole.user ]  [ UserRole.temple ]  [ UserRole.priest ]
         │                │                │
     UserHome       TempleDashboard   PriestDashboard
```

### Scenario 1.1: Devotee (User) Login
1. Devotee opens the application and lands on **LoginScreen**.
2. Devotee enters credentials (e.g., `muthu@sevasetu.com` / `123456`).
3. App authenticates with `FirebaseService`.
4. Role validation maps the session to `UserRole.user`.
5. Session token is saved, routing the Devotee to the main landing view: **UserHome** (starts on **Social Wall** tab at index `0`).

### Scenario 1.2: Temple Admin Login
1. Temple Admin enters credentials (e.g., `pillayarpatti_admin@sevasetu.com` / `123456`).
2. App authenticates, identifying role as `UserRole.temple`.
3. System routes the admin to **TempleDashboard** containing tabs: Overview/Analytics, Manage Priests, Services, Orders, and Gallery.

### Scenario 1.3: Priest Login
1. Priest enters credentials (e.g., `vengadesh@sevasetu.com` / `123456`).
2. App authenticates, identifying role as `UserRole.priest`.
3. System routes the priest to **PriestDashboard** featuring tabs: Schedule, Temple Invites, Private Bookings, and Feed Posting.

---

## 2. Devotee Explore & Booking Flow

### Scenario 2.1: Browsing Temple and Priest Profiles
1. Devotee navigates to the **Explore Tab** on devotee home:
   - Toggle selection between **Temples Listing** and **Spiritual Priests**.
   - Input query in search bar (filters list dynamically by Name, Location, Rasi, or Nakshatra).
2. Devotee clicks on a Temple card (e.g., Pillayar Patti Temple) to open **TempleDetailScreen**, showing:
   - **Overview Tab**: Temple description, address (clickable to Google Maps), contact details, and Follow button.
   - **Gallery Tab**: Grid of uploaded temple images.
   - **Services Tab**: Grid of offered Pujas & Archanas.
   - **Posts Tab**: List of updates published specifically by this temple.
   - **Priests Tab**: Associated active priests.

### Scenario 2.2: BookMyShow-Style Slot Picker Sheet
1. Devotee views a service (e.g., "Ganapathy Homam"). Virtual/Online services display a **Video Cam icon**.
2. Devotee taps the **ADD** button on the service.
3. A slot picker sheet slides up from the bottom:
   - **Date Row**: Devotee selects a date (tomorrow + next 7 days).
   - **Time Slots Grid**: standard hourly slot chips.
   - **Exclusivity & Capacity Check**: System checks availability against `booked_slots/$serviceId/$date/$time` schema.
     - If `bookingCount >= maxParticipants` for that slot, the chip is grayed out, disabled, and displays a red **Booked** tag.
4. Devotee selects an active slot and taps **CONFIRM SLOT & ADD**.
5. Service is added to the cart as a `CartItem` wrapping the specific date and time slot.
6. The listing switches to a Swiggy-style counter capsule: `[ - | count | + ]`.
   - Tapping `+` opens the picker again to add another slot/date.
   - Tapping `-` decrements/removes the last added slot.

---

## 3. Cart & Payment Checkout Flow

### Scenario 3.1: Cart Management
1. Devotee opens **CartScreen** to review selected services.
2. Items are grouped by temple, service, selected date, and slot.
3. Devotee adjusts quantities using the `[ - | quantity | + ]` counter capsule.

### Scenario 3.2: Multi-Family Member Selection & Checkout
1. Devotee taps **PROCEED TO CHECKOUT**.
2. Under "Select Devotees", instead of choosing a single person, CheckoutScreen renders a checkbox roster of all registered family profiles:
   - `[x] Muthu Kumaran (Self)`
   - `[x] Karpagam (Spouse)`
   - `[ ] Murugan (Son)`
3. Devotee selects participating members.
4. System maps selections to the booking order database payload under the `participants` array:
   ```json
   {
     "participants": ["usr_muthu", "fam_karpagam_103"]
   }
   ```
5. Billing breakdown is calculated: Item Total + 5% Maintenance Fee + ₹10 Platform Donation = Grand Total.
6. Devotee chooses payment (Razorpay simulation) and clicks **PROCEED TO PAY**.
7. Payment completes. System updates the real-time capacity counter:
   - Increments `/seva/booked_slots/$serviceId/$date/$time/bookingCount` by `1` per selected slot.
8. System writes distinct order models in `seva/orders` and redirects to **BookingSuccessScreen**.

### Scenario 3.3: Receipt Generation & Open
1. Devotee clicks **DOWNLOAD RECEIPT** on success screen.
2. `PdfService` generates a styled PDF invoice including order info, payment references, temple guidelines, and Jitsi links.
3. SnackBar shows "PDF saved" message with an **OPEN** action.
4. Tapping **OPEN** invokes `OpenFilex.open(file.path)` to safely open the PDF in the system default viewer without `FileUriExposedException` crashes.

---

## 4. Bookings Management (Reschedule & Cancel) & Refund Flow

### Scenario 4.1: Viewing Booking Details
1. Devotee clicks the **Bookings Tab** (`My Bookings` screen).
2. Devotee taps a booking card. The card expands to reveal:
   - Order ID, Payment Ref, Assigned Priest contact, and Jitsi meeting details.
   - If status is `accepted`, a **JOIN LIVE** button launches Jitsi video streams.

### Scenario 4.2: Rescheduling a Slot
1. Devotee clicks the **RESCHEDULE** button inside the expanded card.
2. A reschedule bottom sheet opens showing dates and slots.
3. Availability is checked. Tapping an active slot and confirming updates the order in the database via `app.updateOrderDetails(updatedOrder)`.
4. Rescheduling frees up the capacity slot on the old date/time in `booked_slots` (decrements `bookingCount`) and occupies the capacity on the new date/time (increments `bookingCount`).

### Scenario 4.3: Cancel Booking & Automated Refund Calculations
1. Devotee clicks the **CANCEL** button.
2. System computes time remaining until slot start:
   - **Time to Slot Start > 24 Hours**: Devotee receives a confirmation showing: **"100% Refund Applicable (₹Amount)"**.
   - **Time to Slot Start between 12 to 24 Hours**: Devotee receives a confirmation showing: **"50% Refund Applicable (₹Amount/2)"**.
   - **Time to Slot Start < 12 Hours**: Devotee receives a confirmation showing: **"No Refund Applicable (₹0.00) for late cancellation"**.
3. Upon confirmation, system:
   - Sets order status to `cancelled`.
   - Decrements `/seva/booked_slots/$serviceId/$date/$time/bookingCount`.
   - Triggers a refund request log under `seva/refunds/$orderId` containing calculated amount and payment reference.
   - Refreshes state; status chip changes to a red **CANCELLED** state.

---

## 5. Family Profiles Flow

### Scenario 5.1: Roster View
1. Devotee navigates to the **Family Tab** (`My Family Roster`).
2. Roster cards are displayed containing:
   - Circular avatar image.
   - Name and colored gender icon:
     - **Male**: Blue male symbol (♂).
     - **Female**: Pink female symbol (♀).
     - **Transgender**: Black transgender symbol (⚧).
   - **Dynamic Age Calculation**: Dynamic parser computes age from DOB string supporting both `DD-MM-YYYY` (user added) and `YYYY-MM-DD` (seeded).
   - Astro details: Rasi, Nakshatra, Gothram, Lagnam.

### Scenario 5.2: Adding a Member (Full-Screen Form)
1. Devotee taps **floating action button (+)** on the Family tab.
2. System navigates to the full-screen **AddFamilyMemberScreen**:
   - Devotee taps profile photo to open bottom sheet: picks preset avatar or uploads image via gallery (Cloudinary bytes upload).
   - Fills Name and selects Relationship from dropdown (Spouse, Mother, Son, etc.).
   - Picks Gender via blue/pink/black styled ChoiceChips.
   - Taps Date of Birth field -> styled DatePicker opens and inputs value in `DD-MM-YYYY` format.
   - Fills optional Rasi, Nakshatra, Lagnam, Gothram.
3. Devotee taps **ADD FAMILY MEMBER**. Member is saved to `seva/family_profiles/$userId/$memberId` and pops back to list.

---

## 6. Instagram-Style Social Feed & Following Flow

### Scenario 6.1: Social Wall & Tab Filtering
1. Devotee opens the **Social Wall** (landing screen).
2. ChoiceChips filter is visible at the top: **All Updates** vs **Saved Sevas**.
3. All Updates is active by default.

### Scenario 6.2: Following System & Feed Priority
1. Devotee navigates to a Temple or Priest profile and taps the **FOLLOW** button.
2. System updates database:
   - Sets `seva/following/$userId/$targetId` to `true`.
   - Sets `seva/followers/$targetId/$userId` to `true`.
3. Feed prioritization algorithm filters/sorts the Social Wall:
   - Posts from followed targets (`authorId` in following map) are prioritized and floated to the top of the feed list, sorted by timestamp.
   - Posts from non-followed targets are displayed below.

### Scenario 6.3: Bookmarking (Saved Posts)
1. Devotee taps the bookmark icon button on a feed card.
2. System toggles the record under `seva/saved_posts/$userId/$postId`.
3. Saffron/gold filled bookmark denotes saved post. Devotee toggles the **Saved Sevas** ChoiceChip to view only bookmarked posts.

### Scenario 6.4: Double-Tap Like Action
1. Devotee double-taps a post image.
2. A white heart pop-up scales up and fades out in the center of the image.
3. System toggles like under `seva/likes/$postId/$userId` and increments count in real-time.

### Scenario 6.5: Reporting Posts (Hiding from Feed)
1. Devotee taps `more_vert` on a post and selects **Report Post**.
2. Devotee confirms.
3. System saves report details under `seva/reports/$postId/$userId` and the local devotee blocker list `seva/user_reports/$userId/$postId`.
4. The reported post is immediately filtered out and hidden from this devotee's Social Wall feed.

---

## 7. Temple Priest Association Flow

```text
       [ Temple Dashboard ]               [ Priest Dashboard ]
                 │                                  │
      Invite Priest (Pending)                       │
                 │                                  │
                 └─────────► System Alert ──────────┤
                                                    │
                                             Accept / Decline
                                                    │
                 ┌─────────── Accept ───────────────┘
                 ▼
         Priest Activated
  (Appears in Temple Priest Tab)
```

### Scenario 7.1: Temple Sending Invitation
1. Temple Admin navigates to **Manage Priests** tab.
2. Admin enters details of a priest and searches.
3. Admin clicks **SEND INVITATION**.
4. Database status is written under `seva/temples/$templeId/activePriests/$priestId` as `pending`.
5. System writes notification for Priest: `Invited to join Priesthood`.

### Scenario 7.2: Priest Responding to Invitation
1. Priest logs in, navigates to the **Temple Invites** tab, and views the invitation from the temple.
2. Priest has two options:
   - **Decline**: Sets status under `activePriests/$priestId` to `rejected`, and clears invitation.
   - **Accept**: Sets status to `accepted`, which links the priest.
3. Once accepted, the priest is linked:
   - Priest appears under the temple's active priests lists in searches and booking assignments.
   - Temple's services are available for the priest to assist.

---

## 8. Temple Order Assignment Flow

### Scenario 8.1: Order Assignment Workflow
1. Devotee places an order for a temple service.
2. Temple Admin views the booking under the **Orders** tab (marked as `pending`).
3. Admin clicks **ASSIGN PRIEST**.
4. A list of accepted associated priests is displayed (e.g., `Prassana Gurukkal`, `Mukuntha Gurukkal`).
5. Admin selects a priest.
6. System updates order status to `assigned` and sets `assignedPriest` and `assignedPriestName` in database.
7. System triggers notification to the assigned priest: `New Puja Assignment`.

### Scenario 8.2: Priest Acceptance of Booking
1. Priest logs in and views the assigned booking under their Dashboard **Schedule**.
2. Priest reviews details and clicks **ACCEPT ASSIGNMENT** (or **DECLINE ASSIGNMENT**).
3. If accepted:
   - Order status changes to `accepted`.
   - The Jitsi video call room becomes active.
   - Devotee receives booking status notification: `Puja Booking Confirmed by Priest`.
4. If declined:
   - Order status reverts to `pending` (unassigned).
   - Temple Admin is notified to re-assign a new priest.

---

## 9. Private Priest Booking Flow

### Scenario 9.1: Direct Priest Booking
1. Devotee toggles to **Spiritual Priests** in Explore, and clicks on a priest profile card.
2. Devotee selects a direct private service (e.g., "Grihapravesham Homam") offered by the priest.
3. Devotee picks Date, time slot, and selects participating family profiles.
4. Devotee pays (Razorpay). Order is logged with `templeId` as empty and `priestId` populated.
5. Order status is saved as `pending`. Priest receives notification.

### Scenario 9.2: Priest Booking Management
1. Priest navigates to the **Private Bookings** tab.
2. Priest views the pending direct bookings:
   - **Accept**: Changes order status to `accepted` (notifies devotee, activates room).
   - **Reject**: Changes status to `declined`, triggers refund logic.
   - **Reschedule**: Priest can propose a new slot by tapping reschedule, sending a slot suggestion to the devotee.

---

## 10. Temple Content Creator Flow (Posting & Gallery)

### Scenario 10.1: Publishing Social Wall Updates
1. Temple Admin (or Priest) clicks the **floating action button** on their dashboard.
2. Form opens:
   - Selects image from device gallery (Cloudinary upload).
   - Enters spiritual caption.
3. Admin clicks **PUBLISH**.
4. System creates record under `seva/posts/$postId`. Devotees see this update on their Social Wall feed immediately.

### Scenario 10.2: Uploading Temple Gallery Images
1. Temple Admin navigates to the **Gallery Tab** on their dashboard.
2. Admin clicks **UPLOAD PHOTO**.
3. Selects photo, uploads via Cloudinary, and saves the image URL under the temple's `galleryImages` list: `seva/temples/$templeId/galleryImages`.
4. Devotees visiting this Temple explore page see the photo in the temple's gallery grid immediately.

---

## 11. Live Event Lifecycle Flow

### Scenario 11.1: Starting and Streaming an Event
1. When booking time arrives, Temple Admin (or assigned Priest) opens the order and clicks **START LIVE EVENT**.
2. System activates the Jitsi Meet stream room:
   - Updates order Jitsi status to `active`.
   - Triggers a high-priority push notification to all devotee participants: `Live Puja Event Started! Click to join.`.
3. Devotee receives notification, clicks it, and joins the live stream room inside the app webview interface.
4. When rituals are complete, Admin clicks **END EVENT**.
5. System sets order status to `completed`, deactivates the meeting room, and generates receipt log logs.

---

## 12. Temple Analytics Dashboard

The landing home screen for Temple Admins presents real-time operational metrics and financial charts to help them manage temple activities.

### Scenario 12.1: Viewing Analytics & Performance Metrics
1. Temple Admin logs in and lands on the **Analytics Dashboard**:
2. **Key Metric Tiles**:
   - **Today's Revenue**: Total earnings from pujas booked for today.
   - **Monthly Revenue**: Earnings from all bookings in the current month.
   - **Total Devotees**: Number of unique devotee accounts that have placed bookings.
   - **Active Priests**: Count of linked priests currently associated with the temple.
3. **Operational Lists & Trends**:
   - **Top Service**: Lists the most booked service (e.g. Maha Archana) by volume.
   - **Upcoming Events**: Timeline list of bookings scheduled for today and tomorrow.
   - **Pending Actions Badge**: Highlights unassigned orders and pending priest responses.

---

## 13. System Database Architecture & Schema Optimization

To support O(1) slot checking and high-volume performance, the app maps structures in Firebase RTDB:

### 13.1 Booked Slots Schema (`booked_slots`)
Optimizes slot availability checks by bypassing large order collection loops:
```json
{
  "booked_slots": {
    "serviceId_101": {
      "2026-06-10": {
        "09:00 AM": {
          "bookingCount": 4
        },
        "10:00 AM": {
          "bookingCount": 1
        }
      }
    }
  }
}
```

### 13.2 Following & Followers Nodes
Supports following links for personalized social wall prioritization:
```json
{
  "following": {
    "userId_muthu": {
      "templeId_pillayarpatti": true,
      "priestId_vengadesh": true
    }
  },
  "followers": {
    "templeId_pillayarpatti": {
      "userId_muthu": true
    }
  }
}
```

### 13.3 User Reports & Reported Posts Nodes
Hides reported posts from feed views at database lookup level:
```json
{
  "reports": {
    "postId_999": {
      "userId_muthu": true
    }
  },
  "user_reports": {
    "userId_muthu": {
      "postId_999": true
    }
  }
}
```
