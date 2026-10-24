# Hostel Connect

Flutter Android application and Firebase backend for HS1, HS2, Kennedy, DJ and MB.

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

Firebase project configuration, App Check registration, Cloud Tasks IAM, Android SDK, and release signing must be provisioned before deployment. This repository contains actual Firebase operations, not a demo data mode. No live deployment or APK is included.

## Repository privacy

API keys, Firebase app configuration, service-account credentials, signing keys, local environment files, logs, dependency directories and original menu photographs are excluded from Git. `admin/.env.example` contains empty variable names only. The English menu and screenshots using sample data are included. Supply your own configuration locally as described in the setup guide; never commit secrets.

A separate, clearly labeled read-only browser preview is available; see [preview instructions](docs/PREVIEW.md).
