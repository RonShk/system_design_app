# Delivery decision: installable web app on GitHub Pages

Decided 2026-11-14 after inspecting the development machine and the platform rules.

## What was checked

| Question | Finding | How it was checked |
|---|---|---|
| Can a native app be signed for long-term use? | No code-signing identity is installed on this Mac. Without the paid Apple Developer Program ($99/year), a free Apple ID signs builds that expire after 7 days and must be reinstalled from a Mac. | `security find-identity -v -p codesigning` → 0 identities; Apple's free-provisioning rules |
| Can a web app be installed on iPhone? | Yes. A site with a manifest whose `display` is `standalone` becomes a Home Screen web app. | WebKit, "Web Push for Web Apps on iOS and iPadOS" — https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/ |
| Can it notify while closed? | Yes, through standard Web Push (Push API + Notifications API + service worker) for Home Screen web apps on iOS 16.4+. Permission must be requested from a tap. No Apple Developer membership is needed. | Same WebKit post |
| Can a web app schedule a *local* notification with no server? | No. The Notification Triggers API was a Chrome experiment and is not in Safari. A push has to be sent by something on the network. | https://web.dev/notification-triggers ; Apple Developer Forums thread 735402 |
| Free hosting? | GitHub Pages is free for public repositories and this repository is public. | `gh repo view` |
| Something to send the push without a laptop or paid backend? | A scheduled GitHub Actions workflow can send Web Push directly to Apple's push service. Free for public repositories. | GitHub Actions documentation |

## Decision

1. **App**: a static, installable PWA (Vite + React + TypeScript) served from GitHub Pages.
   All lessons and questions are precached by the service worker at install, so the app
   works offline. Progress is stored in IndexedDB on the phone.
2. **Reminders**: Web Push. `.github/workflows/reminders.yml` runs every 15 minutes, reads
   the reminder configuration, and sends a push when the preferred local time has passed
   and no reminder was sent yet that local day.
3. **No backend, no accounts, no paid services.**

Rejected: a native SwiftUI/Capacitor app. It would give true local notifications, but with
no paid developer account it would stop launching every 7 days, which fails "reliable
installation and daily use" and "do not depend on my laptop". The domain logic is plain
TypeScript with no browser dependencies, so wrapping it natively later remains possible.

## How reminder configuration reaches the workflow

The repository is public, so the push subscription must not be committed or logged.
It is stored in a GitHub Actions **repository variable** (`REMINDER_CONFIG`), which is
readable only by people with access to the repository settings, not by the public.

Two ways to set it:

- **From the app (recommended)**: paste a fine-grained personal access token limited to
  this one repository with *Variables: read and write* and *Actions: read and write*.
  The app then writes the variable itself whenever reminders are enabled, disabled, or
  the time or time zone changes, and can trigger a real test push.
- **Manual**: the app shows the configuration JSON to copy into
  *Settings → Secrets and variables → Actions → Variables → `REMINDER_CONFIG`*.

The token is stored only on the phone (IndexedDB) and is sent only to `api.github.com`.

## Known limits (operating system and platform)

- GitHub's scheduler is best-effort; runs can start several minutes late. A reminder
  arrives at the preferred time or up to roughly 15–30 minutes after it, not to the minute.
- GitHub disables scheduled workflows in a public repository after 60 days without
  repository activity. Each run calls the "enable workflow" API to keep the schedule
  alive, and any push to the repository also resets the timer. This keep-alive has not
  been observed over a 60-day period here; if reminders ever stop, re-enable the workflow
  under the repository's *Actions* tab.
- iOS only delivers Web Push to web apps opened from the Home Screen icon, and the
  permission prompt only appears after a tap inside the installed app.
- iOS may revoke a push subscription if pushes arrive without showing a notification; the
  service worker always shows one.
- Deleting the Home Screen icon deletes the app's local data. Export progress first
  (Settings → Export).
- Verification in this project was done in desktop Chrome at phone dimensions. Install,
  push delivery, and offline behaviour on a physical iPhone are listed as device-only
  checks in [PROGRESS.md](PROGRESS.md).
