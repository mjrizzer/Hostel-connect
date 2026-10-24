# Set up and deploy Hostel Connect

## Toolchain

The dependency lockfiles are included. Development used Flutter 3.47.7 / Dart 3.13.5, Java, and Node 24.20.0; the final backend suite also passed on the target Node 22 runtime. Cloud Functions target Node 22. Use Node 22 for deployment and CI. Install Android Studio with the Android SDK and accept its licenses using `flutter doctor --android-licenses`. This workspace includes a local Flutter SDK under `.tools/flutter` (ignored by Git).

Run from the project root:

```powershell
flutter pub get
npm --prefix functions ci
npm --prefix admin ci
flutter analyze
flutter test
npm --prefix functions test
npx firebase-tools emulators:exec --only firestore --project demo-hostel-connect "npm --prefix functions test"
npm --prefix admin run build
```

The ordinary backend test command deliberately skips emulator tests if `FIRESTORE_EMULATOR_HOST` is absent. Use the emulator command to execute the authorization and transaction suites. Backend tests invoke the actual function handlers against Firestore Emulator; they do not prove live App Check, IAM, task scheduling or FCM delivery. They reset their demo database: never point them at a production database. Node's test concurrency is one so database reset cannot race rule fixtures.

## Firebase project

1. Create a Firebase project with billing enabled for Functions, Cloud Tasks and Scheduler. Choose Firestore Native mode in a suitable Indian region. Functions use `asia-south1` consistently in backend, mobile and admin.
2. Enable **Anonymous** authentication for students and **Google** authentication for administrators. Add the admin hosting domain to authorized authentication domains.
3. Register Android application `in.hostelconnect.hostel_connect`. Download its `google-services.json` into `android/app/`. This is project configuration, not a service-account key. Do not add private service-account credentials to any client.
4. Register the app with App Check using Play Integrity. Register SHA-256 signing fingerprints and configure Play Integrity eligibility for your distribution method. Use debug App Check tokens only for development, registered in the Firebase console. Release builds select Play Integrity automatically. Enable App Check enforcement for Firestore; callable enforcement is already enabled in code.
5. Enable the Cloud Tasks, Cloud Functions, Cloud Run, Cloud Build, Artifact Registry, Firebase Cloud Messaging and Cloud Scheduler APIs as requested by deployment. Use a restricted deployment identity. Verify the runtime service account can enqueue tasks and invoke **only** the private `deliverReminder` task handler. Follow the Firebase task queue IAM guidance linked below; do not make the task handler public.
6. Install Firebase CLI and select your project explicitly. Authenticate locally using your own account, not committed credentials.

```powershell
npx firebase-tools login
npx firebase-tools use --add
npm --prefix functions run build
npx firebase-tools deploy --only firestore,functions --project YOUR_PROJECT_ID
```

There is intentionally no checked-in project ID or `.firebaserc` pointing to a live project.

## Seed inventory and the translated menu

The source photographs are `menu1.jpeg.jpeg` and `menu2.jpeg.jpeg`. All 28 English meals are in `assets/menu/weekly-menu.json`. The user accepted the three documented ambiguous readings; `acceptedInterpretations` preserves their provenance. `docs/WEEKLY_MENU.md` is a readable rendering of the same data. Alternatives remain alternatives and are not silently converted into additional courses.

Use Application Default Credentials outside the repository:

```powershell
gcloud auth application-default login
$env:GCLOUD_PROJECT='YOUR_PROJECT_ID'
node scripts/database_initialization/seed.cjs
```

The seed creates missing records only. It preserves occupancy, existing administrator revisions and immutable `originalWeeklyMenu` records. It creates exactly five buildings, sixteen machines and three sports facilities. It will refuse a menu import if `verified` is false or `verificationNotes` is nonempty. To test locally, set `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080` and use `GCLOUD_PROJECT=demo-hostel-connect`.

## Administrator dashboard

The separate dashboard is a responsive JavaScript web application using the Firebase Web SDK (the spec permits a separate administrator interface). It has no student registration flow.

1. Register a Firebase Web app. Copy `admin/.env.example` to `admin/.env` and fill in its public Firebase configuration and reCAPTCHA Enterprise site key. Register this Web app with App Check. No private credentials belong here.
2. Run `npm --prefix admin run dev`. Sign in once with the intended verified Google account. No admin access is granted by signing in alone.
3. As a trusted project operator, run the following locally with ADC. The script rejects anonymous accounts and unverified Google accounts.

```powershell
$env:GCLOUD_PROJECT='YOUR_PROJECT_ID'
node scripts/grant-admin.cjs FIREBASE_ADMIN_UID
```

4. Sign in again to refresh claims. Build and deploy:

```powershell
npm --prefix admin run build
npx firebase-tools deploy --only hosting --project YOUR_PROJECT_ID
```

The backend validates the admin claim and a non-anonymous provider for every privileged operation. Clients cannot create roles. Reports are review queues; resolving a report and correcting equipment are distinct audited actions. A report alone never modifies occupancy or imposes a restriction. The dashboard limits a queue view to the most recent 200 records; use Firestore administrative tools for older records until an archival UI is added.

## Android builds

```powershell
flutter doctor
flutter run
flutter build apk --debug
```

For production, generate and securely back up an upload keystore. Create ignored `android/key.properties`:

```properties
storeFile=C:/secure/hostel-connect-upload.jks
storePassword=YOUR_LOCAL_SECRET
keyAlias=upload
keyPassword=YOUR_LOCAL_SECRET
```

```powershell
flutter build apk --release
flutter build appbundle --release
```

Release signing is configured from that file. Do not distribute an unsigned or debug-signed build. Output APK: `build/app/outputs/flutter-apk/app-release.apk`. Configure Play App Signing and App Check fingerprints before a Play distribution. No APK was generated in this workspace because an Android SDK, Firebase app configuration and release signing material were not supplied.

iOS scaffolding is included for future development. Add `GoogleService-Info.plist` to Runner in Xcode, enable push notifications and background remote notifications, configure APNs in Firebase, and provision Apple App Attest. iOS device validation remains outstanding.

## Reminders and reliability

Reservation transactions create a reminder outbox record, not a client timer. A retried Firestore trigger enqueues Cloud Tasks; a five-minute scheduler repairs pending enqueue failures. Duplicate tasks are harmless because the handler claims one outbox record transactionally. It rechecks session state and the owner's preference before sending. Ending a session or collecting/cancelling clothes invalidates the record. Drying reminders are independent of machine occupancy. Games never create an outbox record.

The send policy prioritizes avoiding duplicates: one FCM handoff attempt per reminder. A process crash after the claim but before FCM may lose a notification; a send whose outcome is uncertain is recorded as `deliveryUncertain`, never blindly retried. This is **not exactly-once delivery**. Cancellation cannot retract a notification already handed off to FCM. Android, connectivity and permissions can delay or prevent display. Monitor `pending`, `claimed`, `deliveryUncertain` and failure counts. Test the complete scheduled path in a staging Firebase project before release.

FCM tokens live in owner-private subcollections. Invalid tokens are removed on send; at most the ten most recently registered tokens are used. Optional reminder preferences are checked at dispatch. Anonymous account loss can make old sessions inaccessible; only a verified administrator may release them.

## Release acceptance checks still requiring devices/services

- Two Android devices: competing starts, realtime updates, owner-only finishes, offline restart/reconnection and server failures.
- Closed and background app: both reminder types, taps, permission denial, preference disable, token refresh and cancellation.
- Admin Google login, App Check on Android/Web, restricted task invocation and Firestore enforcement in staging.
- 360 px layouts, large fonts, TalkBack, dark mode, keyboard, longer chat histories and moderation of old messages.
- Keystore-backed release build and Play Integrity with the actual signing certificate.
- Review the translated menu with hostel staff before calling it an officially certified transcription.

## References

- [Firebase task queue functions and IAM](https://firebase.google.com/docs/functions/task-functions)
- [App Check enforcement for callable functions](https://firebase.google.com/docs/app-check/cloud-functions)
- [Flutter installation](https://docs.flutter.dev/install/manual)

Anonymous access plus App Check reduces abuse but does not prove hostel membership. Public chat and availability remain readable by authenticated anonymous app users. Add a separately designed residency-verification mechanism only if hostel policy later requires it.
