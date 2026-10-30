# Hostel Connect

Flutter Android application and Firebase backend for HS1, HS2, Kennedy, DJ and MB.

## Android download

Download the APK from [GitHub Releases](https://github.com/mjrizzer/Hostel-connect/releases). The current free-plan test build supports Android ARM64 devices, including the Galaxy S23, and requires Android 7.0 or later. Enable installation from your browser when Android asks, then open Hostel Connect to create an anonymous session.

This development build provides live reservations without scheduled reminders. See [free-plan capabilities and limitations](docs/FREE_PLAN.md) before sharing it. The administrator dashboard requires the original Cloud Functions backend.

## Architecture

- Flutter / Riverpod / GoRouter; feature screens share typed repositories and snapshot providers.
- Public availability documents never contain owner UIDs. Private sessions, account state, tokens and moderation records are separately protected.
- All mutations use App Check enforced callable functions. Firestore transactions arbitrate reservations and ownership.
- Transactional reminder outbox → Firestore trigger → Cloud Tasks → private task handler. Games never create reminders.
- Separate web administrator dashboard uses Google authentication and server-issued admin claims; anonymous accounts cannot administer.
- Exact inventory is seeded idempotently. All 28 meals are translated from the two supplied MH MENU 25–26 photographs. User-accepted interpretations of unclear print are recorded with the English seed.

See [setup and deployment](docs/SETUP.md), [English weekly menu](docs/WEEKLY_MENU.md), and [menu seed](assets/menu/weekly-menu.json).

## Run checks

```sh
flutter pub get
flutter analyze
flutter test
npm --prefix functions ci
npx firebase-tools emulators:exec --only firestore --project demo-hostel-connect "npm --prefix functions test"
npm --prefix admin ci
npm --prefix admin run build
```

Firebase project configuration, App Check registration, Cloud Tasks IAM, Android SDK, and release signing must be provisioned for the original backend deployment. The free-plan edition has separate configuration and security rules documented above. APK downloads are distributed through GitHub Releases rather than tracked in the source tree.

## Repository privacy

API keys, Firebase app configuration, service-account credentials, signing keys, local environment files, logs, dependency directories and original menu photographs are excluded from Git. `admin/.env.example` contains empty variable names only. The English menu and screenshots using sample data are included. Supply your own configuration locally as described in the setup guide; never commit secrets.

A separate, clearly labeled read-only browser preview is available; see [preview instructions](docs/PREVIEW.md).
