# System Design Trainer

A personal iPhone app that teaches system design step by step, for interviews and for real
engineering work. You learn a concept, retrieve it from memory, get assessed later on
questions you have not seen, and review it on a spaced schedule. It runs fully offline,
and a local notification reminds you every day at 3 pm.

- **Learn:** lessons covering foundations, data systems, distributed correctness, scaling
  and production engineering. Each has an objective, prerequisites, intuition, mechanism,
  an example, tradeoffs, misconceptions, a worked scenario, diagrams and exact source
  sections.
- **Practice:** recall, explain, predict, estimate, diagnose and design questions, with
  hints. The app records whether each answer was independent, hinted or revealed.
- **Assess:** topic quizzes, delayed retention checks, cumulative quizzes, a final
  assessment on unfamiliar scenarios, and timed interview exercises. These use a question
  pool that practice never shows.
- **Case studies:** ten designs worked stage by stage, from requirements to evolution,
  plus an unguided variant of each.
- **Labs:** optional build exercises in C/C++ (key-value server, cache, thread pool, WAL
  recovery, rate limiter, performance and failure testing).

How the learning mechanics follow the research is in
[docs/LEARNING_DESIGN.md](docs/LEARNING_DESIGN.md). Current status is in
[docs/PROGRESS.md](docs/PROGRESS.md).

## Install on your iPhone

You need a Mac with Xcode 16 or later, your iPhone and a cable (Wi-Fi works after the first
install).

1. Clone the repository and open the project:
   ```sh
   git clone https://github.com/RonShk/system_design_app.git
   open system_design_app/ios/SystemDesignTrainer.xcodeproj
   ```
2. In Xcode, go to **Settings → Accounts**, click **+** and sign in with your Apple ID. A
   free account works.
3. Select the **SystemDesignTrainer** target, open the **Signing & Capabilities** tab and
   set **Team** to your Personal Team. If Xcode says the bundle identifier is taken,
   change `com.ronshaked.systemdesigntrainer` to something unique, such as adding your
   initials.
4. Connect the iPhone and unlock it. On the phone, tap **Trust**. On iOS 16 or later,
   turn on **Settings → Privacy & Security → Developer Mode** and restart when asked.
5. In Xcode's toolbar, pick your iPhone as the run destination and press **Run** (⌘R).
6. The first launch is blocked as an "Untrusted Developer". On the phone, go to
   **Settings → General → VPN & Device Management**, tap your Apple ID, then tap
   **Trust**. Open the app again.
7. In the app, tap **Turn on reminders and start** and allow notifications. The reminder
   is set for 3:00 pm. To check delivery, use **Settings (gear on Today) → Send a test
   notification**, then lock the phone.

**Free Apple ID limit:** apps installed with a free account stop opening after 7 days.
Repeat step 5 to refresh; your progress is kept. The Apple Developer Program ($99/year)
gives 1-year builds and TestFlight, with no code changes.

**Back up:** Settings → Export progress saves a JSON file to Files or iCloud Drive.
Deleting the app deletes its data. Import restores the file, and malformed files are
rejected without changing anything.

## Develop

```sh
npm ci                                   # content tooling (Node 20+)
npm run content                          # validate content/ and regenerate the bundled JSON
npm run content:strict                   # also enforce delivery targets and rewrite docs/COVERAGE.md
npm test                                 # content pipeline tests
(cd ios/TrainerCore && swift test)       # learning rules: scheduler, mastery, checking, persistence
cd ios && xcodebuild test -project SystemDesignTrainer.xcodeproj -scheme SystemDesignTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO   # app + UI tests
```

To update the app on the phone, pull and press Run in Xcode again. Data migrates
automatically.

To add or change content, follow [docs/CONTENT_GUIDE.md](docs/CONTENT_GUIDE.md), run
`npm run content`, and commit both `content/` and the regenerated JSON.

Documentation:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): code layout, data flow, persistence and migration rules
- [docs/DELIVERY.md](docs/DELIVERY.md): why native, signing options, platform limits
- [docs/CURRICULUM.md](docs/CURRICULUM.md): coverage matrix
- [docs/COVERAGE.md](docs/COVERAGE.md): generated per-lesson coverage report
- [docs/SOURCES.md](docs/SOURCES.md): sources, licences, verification
- [docs/TESTING.md](docs/TESTING.md): what is tested and how; verification results
- [docs/PROGRESS.md](docs/PROGRESS.md): status, known limitations, next actions
- Backlog: [GitHub Issues](https://github.com/RonShk/system_design_app/issues)

## Sources and licence

The lessons are original writing. They cite and link to their sources (Kleppmann's
Cambridge notes, OSTEP, *Computer Networks: A Systems Approach*, CMU 15-445, the Google
SRE books, MIT 6.5840 papers, Build Your Own Redis, the System Design Primer, RFCs and
official documentation) and do not redistribute them. See
[docs/SOURCES.md](docs/SOURCES.md).
