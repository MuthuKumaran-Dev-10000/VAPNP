# Seva MVP Spec

## Product Vision
- Build a divine-feeling booking app for temples, priests, and devotees.
- Support online darshan, special prayers, temple tours, and iyer booking requests.
- Keep the MVP fast, clean, and demo-ready for authority review.

## MVP Scope
- Email/password login and signup.
- Role-based onboarding for devotee, temple admin, and priest.
- Temple browsing and service discovery.
- Booking request flow with accept/decline status.
- Simple temple admin dashboard for menu, orders, priests, and income snapshots.
- Priest dashboard for incoming requests.
- Devotee dashboard for search, cart, billing, and attendance.

## Current Flutter Paths
- `lib/main.dart` — app bootstrap, Firebase init, role routing.
- `lib/core/theme.dart` — divine visual theme and colors.
- `lib/core/models/user_model.dart` — user roles and auth profile model.
- `lib/core/models/priest_model.dart` — priest profile model.
- `lib/core/models/temple_model.dart` — temple profile model.
- `lib/core/models/service_model.dart` — darshan/prayer/tour service model.
- `lib/core/models/booking_model.dart` — booking record model.
- `lib/core/services/firebase_service.dart` — in-memory auth, demo seed data, booking store.
- `lib/core/services/auth_provider.dart` — auth state and session wrapper.
- `lib/core/services/app_provider.dart` — UI state for navigation and selections.
- `lib/core/services/seed_data.dart` — default seed entrypoint.
- `lib/features/auth/login_screen.dart` — sign in screen and demo access chips.
- `lib/features/auth/signup_screen.dart` — role-based signup screen.
- `lib/features/auth/forgot_password_screen.dart` — recovery placeholder.
- `lib/features/shared/dashboard_shell.dart` — shared app shell and bottom nav.
- `lib/features/temple/temple_dashboard.dart` — temple admin MVP dashboard.
- `lib/features/priest/priest_dashboard.dart` — priest request dashboard.
- `lib/features/user/user_home.dart` — devotee home and discovery view.
- `lib/widgets/offline_banner.dart` — reusable offline/demo status strip.

## Planned Feature Paths
- `lib/features/temple/` — temple profile, service builder, capacity manager, order board.
- `lib/features/priest/` — accept/decline queue, priest profile, temple invite handling.
- `lib/features/user/` — temple search, service booking, family members, PDF receipt, live room.
- `lib/features/payments/` — Razorpay checkout, payment verification, refund hooks.
- `lib/features/live/` — Jitsi room join, waiting room, broadcast room, live count limit.
- `lib/features/media/` — Cloudinary upload helpers for temple banners and service images.
- `lib/features/pdf/` — invoice and billing PDF generation.
- `lib/features/notifications/` — email and push notification triggers.

## Firebase / Backend Plan
- Use Firebase Auth for production login.
- Use RTDB for live booking state, temple menus, and queue updates.
- Use Cloud Functions for:
  - booking confirmation,
  - payment verification,
  - email notifications,
  - role-based moderation,
  - live-room scheduling.
- Keep client-side logic minimal and push sensitive operations to functions later.

## Data Shape
- `users/{uid}` — profile, role, contact, devotion details, family links.
- `temples/{templeId}` — temple profile, admin info, service list, media.
- `services/{serviceId}` — type, price, capacity, priest requirement, live flag.
- `bookings/{bookingId}` — user, temple, service, time, status, payment state.
- `priests/{priestId}` — priest bio, temple assignment, availability.
- `liveSessions/{sessionId}` — room metadata, start time, capacity, active state.

## UI Direction
- Deep maroon, gold, ivory, and stone palette.
- Soft cards, rounded corners, gentle shadows, and devotional spacing.
- Calm premium typography with a temple-inspired feel.
- Home screens should feel peaceful, not crowded.

## 2-Day Build Order
- Day 1: auth, role routing, temple discovery, service creation, booking request.
- Day 2: acceptance flow, payment stub, live room stub, billing PDF stub, UI polish.

## Decisions To Keep MVP Fast
- Use one codebase and one repo.
- Keep backend logic mostly in Firebase + service helpers.
- Keep live streaming to Jitsi only for the MVP.
- Use demo data and offline-safe storage first, then connect real backend services.

## Next Suggested Files
- `lib/features/booking/booking_screen.dart`
- `lib/features/payments/payment_screen.dart`
- `lib/features/live/live_session_screen.dart`
- `lib/features/pdf/invoice_screen.dart`
- `lib/features/media/cloudinary_picker.dart`
