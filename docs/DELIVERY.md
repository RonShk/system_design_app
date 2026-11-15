# Delivery: native iOS app (SwiftUI)

## Decision history

- **2026-11-14, first decision:** installable web app (PWA) with Web Push sent by a
  scheduled GitHub Actions workflow. The reasons were that no code-signing identity was
  installed and that a free-signed native build expires after 7 days.
- **2026-11-14, superseded by the owner:** build it as a native app, because local
  notifications are simpler and more reliable than a push server, and remind daily at
  about 3 pm. The PWA work was never merged; nothing from it ships.

## What was built

| Concern | How |
|---|---|
| App | SwiftUI, iOS 17+, iPhone only, portrait. Xcode project `ios/SystemDesignTrainer.xcodeproj`. |
| Rules | `ios/TrainerCore`: a Swift package with no UI dependencies (scheduler, progress, checking, sessions, assessments, persistence, backup). Tested with `swift test` on macOS. |
| Content | Compiled from `content/` by `npm run content` into JSON under `ios/SystemDesignTrainer/Resources/content/` and bundled in the app. |
| Offline | Everything is in the app bundle. No network calls; the only links that leave the app are source citations. |
| Progress | JSON file in the app's Application Support directory, with the previous good copy kept as a backup. Survives app updates; removed if the app is deleted. Versioned migrations; validated export and import. |
| Reminders | One repeating `UNCalendarNotificationTrigger` at 15:00 local time by default (changeable in Settings). It is a local notification, so iOS delivers it with the app closed and with no server or network. |
| Cost | None, with a free Apple ID (see the expiry limit below). |

## Installing on an iPhone

Signing needs an Apple ID in Xcode. There are two options:

| Option | Cost | What it means |
|---|---|---|
| Free Apple ID ("Personal Team") | $0 | Install from Xcode over USB or Wi-Fi. **The install expires after 7 days**: the app stops opening until you run it from Xcode again. Your progress is kept, because reinstalling over the top keeps app data. |
| Apple Developer Program | $99/year | Builds last a year, and TestFlight lets you install without a cable. No code changes are needed. |

The step-by-step instructions are in the README.

## Known limits

- With free signing, the 7-day re-sign is the biggest day-to-day cost. Reinstalling takes
  about a minute with the phone connected, and progress survives it.
- Deleting the app deletes its data. Export from Settings first.
- Notifications need permission, which the app asks for during onboarding. If you decline,
  Settings shows the status and links to iOS Settings.
- Verification so far has been in the iOS Simulator (iPhone 17 Pro, iOS 26.2). Real-device
  checks are listed in [PROGRESS.md](PROGRESS.md).
