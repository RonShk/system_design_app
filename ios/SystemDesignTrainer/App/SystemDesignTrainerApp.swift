import SwiftUI
import TrainerCore

@main
struct SystemDesignTrainerApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(scheme)
                .task {
                    await model.reminders.refreshStatus()
                    model.refreshReminder()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Re-plan whenever the app comes forward or leaves, so the reminder text
                    // reflects what is due and a time-zone change is picked up.
                    if phase == .active || phase == .background { model.refreshReminder() }
                }
        }
    }

    private var scheme: ColorScheme? {
        switch model.state.prefs.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            TodayView().tabItem { Label("Today", systemImage: "sun.max") }.tag(0)
            LearnView().tabItem { Label("Learn", systemImage: "book") }.tag(1)
            PracticeView().tabItem { Label("Practice", systemImage: "arrow.triangle.2.circlepath") }.tag(2)
            AssessView().tabItem { Label("Assess", systemImage: "checkmark.seal") }.tag(3)
            StatsView().tabItem { Label("Progress", systemImage: "chart.bar") }.tag(4)
        }
        .sheet(isPresented: .constant(!model.state.prefs.onboarded)) {
            OnboardingView().interactiveDismissDisabled()
        }
        .alert("Saving failed", isPresented: .constant(model.saveError != nil)) {
            Button("OK") {}
        } message: { Text(model.saveError ?? "") }
    }
}

/// First launch: explains how the app works and asks for notification permission.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var time = Calendar.current.date(from: DateComponents(hour: 15, minute: 0)) ?? Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("System Design Trainer").font(.largeTitle.weight(.bold)).padding(.top, 24)
                Text("A course in system design built around how memory works.")
                    .font(.title3).foregroundStyle(.secondary)
                point("book", "Learn", "Short lessons teach one idea each: intuition, mechanism, tradeoffs, a worked scenario.")
                point("arrow.triangle.2.circlepath", "Practice", "You retrieve the idea from memory — explain, predict, estimate, diagnose — before seeing the answer.")
                point("calendar", "Review", "Concepts come back on later days with different questions, so you remember them rather than the wording.")
                point("checkmark.seal", "Assess", "Quizzes use questions practice never showed. A concept counts as retained only after a gap of a week or more.")
                Card {
                    Text("Daily reminder").font(.headline)
                    DatePicker("Remind me at", selection: $time, displayedComponents: .hourAndMinute)
                    Text("A notification on this phone, once a day. You can change or turn it off in Settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Turn on reminders and start") { finish(reminders: true) }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("onboard-start")
                Button("Start without reminders") { finish(reminders: false) }
                    .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("onboard-skip")
            }
            .padding(20)
        }
        .background(Theme.pageBackground)
    }

    private func point(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func finish(reminders: Bool) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        Task {
            if reminders { await model.reminders.requestPermission() }
            model.updatePrefs {
                $0.remindersEnabled = reminders
                $0.reminderHour = c.hour ?? 15
                $0.reminderMinute = c.minute ?? 0
                $0.onboarded = true
            }
        }
    }
}
