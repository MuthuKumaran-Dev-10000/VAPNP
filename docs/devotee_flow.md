# Devotee User Flow

This document explains the user experience and data synchronization pathways for Devotees (standard users) in the SevaSetu application.

---

## 1. Explore, Search and Discovery

The landing page of the devotee is `UserHome` (Explore Tab).
* **Data Pulled**:
  * Realtime streams of Temples (`/seva/temples`) and Priests (`/seva/priests`) are subscribed to on init via `AppProvider.listenAllGlobalData()`.
* **Client-side Filtering**:
  * Devotees can search for temples by name or location, and search for priests by name, rasi, or birth star.
  * Searching is implemented locally by filtering the list variables using string operations:
    ```dart
    final filteredTemples = app.temples.where((t) {
      return t.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          t.address.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
    ```

---

## 2. Shopping Cart and Booking Selection

SevaSetu allows booking multiple services across different temples or priests in a single transaction.
* **Mechanism**:
  * The shopping cart is managed globally in `AppProvider` using a local reactive List (`List<ServiceModel> _cart`).
  * Adding a service checks if the item already exists in the cart to avoid duplicates:
    ```dart
    void addToCart(ServiceModel s) {
      if (!_cart.any((item) => item.id == s.id)) {
        _cart.add(s);
        notifyListeners();
      }
    }
    ```
  * Cart state is persisted in memory.

---

## 3. Astrological Family Profiles (Roster)

Devotees can maintain a roster of family members to include in puja bookings (puja sankalpams).
* **Data Synced**:
  * **Path**: `/seva/family_profiles/<userId>/<memberId>`
  * **Sync Actions**:
    * **Pull**: Subscribed on app loading inside `AppProvider.listenUserSessions` via `_firebaseService.getFamilyProfilesStream(userId)`. Updates are streamed in real time to the "Family" tab.
    * **Push**: Adding a family member compiles profile details (including calculations of age from birth year, rasi, nakshatra, and gothram) and calls `_firebaseService.addFamilyMember` to push a new node to RTDB.

---

## 4. Razorpay Payment Gateway Integration

Before a booking is finalized, payments are processed securely through the Razorpay SDK:
* **Mechanism**:
  * The checkout screen initializes the Razorpay plugin with the test API key: `rzp_test_SzBkemjjVqb8Ap`.
  * **Configuration Options**:
    * `key`: API Key.
    * `amount`: Total cart amount in paise (INR × 100).
    * `name`: `"SevaSetu"`.
    * `description`: `"Spiritual Services Checkout"`.
    * `prefill`: User email and mobile number.
  * **Callbacks**:
    * On successful payment, the gateway returns a `PaymentSuccessResponse` containing `paymentId`, `orderId`, and `signature`.
    * The client verifies these and calls `AppProvider.bookCartServices` passing the `paymentId` as the database payment reference.

---

## 5. Booking Order Completion & PDF Receipts

Once Razorpay responds with a success signal:
1. **Push Booking Orders**: The client loops through the cart items and writes booking records to `/seva/orders`.
2. **Push Notifications**: Sends alerts to the respective temples and priests.
3. **Generate PDF Receipt**: The app invokes `PdfService.generateReceipt(order)` locally:
   * Uses the `pdf` package to draw a high-fidelity spiritual receipt containing temple name, devotee name, booking date, amount, Jitsi Meet link, and payment reference.
   * On mobile, the PDF is saved using `path_provider` in local temporary directories, with a snackbar offering an "OPEN" file action.
