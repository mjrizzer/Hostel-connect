# Local browser preview

This uses the actual Flutter feature screens, a development-only in-memory Firestore fixture, the exact equipment inventory and the translated menu. Availability is sample data, labeled on every screen. Mutations return an explicit preview error and start buttons are disabled. No Firebase configuration, personal accounts or live reservations are used.

```powershell
flutter build web --debug --target tool/preview.dart --no-web-resources-cdn
node tool/serve-preview.cjs
```

Open http://127.0.0.1:4173. Use the five navigation tabs; theme options are available from Settings. The production application still starts from `lib/main.dart` and uses Firebase.

Debug mode is required because the development fixture deliberately rejects release builds.
