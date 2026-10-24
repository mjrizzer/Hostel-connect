# Verification record

Checked on 2026-10-22.

| Check | Result |
| --- | --- |
| Flutter 3.47.7 / Dart 3.13.5 analysis of lib, test and integration_test | No issues |
| Flutter unit/widget tests | 5 passed |
| TypeScript compilation | Passed |
| Backend and Firestore rules tests against the Firestore emulator, Node 22 | 19 passed; 0 skipped |
| Administrator production build | Passed; Vite reports a bundle-size advisory |
| Production dependency audits, functions and admin | 0 reported vulnerabilities |
| Menu shape | Seven days, four meals per day, English text validated |
| Inventory seed rerun | Counts preserved; existing machine status not overwritten |

Backend tests cover racing reservations, one active laundry session per account, owner-only finishes, administrator override, private rules, session persistence, report deduplication without status changes, date-only approved menu overrides, chat rate limits/replies/ownership/moderation, drying opt-out/cancellation, reminder timing and deduplication, and no sports reminder records. Reminder send tests stub FCM and assert owner-only targeting; they are not live push-delivery tests.

The test output includes expected `PERMISSION_DENIED` logs from denied-access assertions and harmless metadata-service lookup warnings in the local environment.

Not executed: Android APK build, physical-device integration tests, live Firebase deployment, live Cloud Tasks/IAM/App Check verification, actual closed-app notifications, iOS builds, and interactive administrator login. `flutter doctor` confirms the Android SDK is absent. Firebase project configuration and signing credentials were not supplied.

The device smoke test is provided in `integration_test/app_test.dart`. After provisioning staging services and debug App Check, run `flutter test integration_test/app_test.dart -d DEVICE_ID`. Complete the release acceptance checklist in SETUP.md before distributing the app.

The original menu photographs remain in the project. Three ambiguous readings were accepted by the user and documented in the seed; the transcription is not independently certified by hostel staff.
