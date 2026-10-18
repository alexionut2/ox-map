import SwiftUI
import OxydeCore

/// Two taps to report: pick a category, and it sends after a short undo window. Large
/// targets, no typing. Categories that are restricted in the current region are hidden.
struct ReportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let reports = model.reports
        NavigationStack {
            VStack(spacing: 16) {
                switch reports.state {
                case .pending(let cat, let left):
                    pending(cat, left)
                case .sending:
                    ProgressView("Sending…").frame(maxHeight: .infinity)
                case .sent(let cat):
                    done(cat)
                case .failed(let message):
                    failed(message)
                case .idle:
                    grid
                }
            }
            .padding(OX.gutter)
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { reports.reset(); dismiss() } } }
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.reports.isConfigured {
                Banner(symbol: "server.rack", text: "Community reporting needs the Oxyde backend, which isn't configured in this build. See docs/BACKEND.md.",
                       tone: .warning)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(model.reports.allowedCategories) { cat in
                    Button {
                        model.haptics.tap(enabled: model.settings.value.hapticsEnabled)
                        model.reports.submit(cat, at: location.lastFix, traffic: model.traffic)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: cat.symbol).font(.system(size: 30, weight: .semibold)).frame(height: 36)
                            Text(cat.title).font(.footnote.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("report.\(cat.rawValue)")
                }
            }
            Text("Your report is shared with other drivers at your current position and labeled as a driver report. It expires automatically.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Tip: say “Hey Siri, report traffic in Oxyde Map” to report hands-free.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func pending(_ cat: ReportCategory, _ left: Int) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: cat.symbol).font(.system(size: 54)).foregroundStyle(.tint)
            Text("Reporting \(cat.title.lowercased())…").font(.title2.bold())
            Text("Sending in \(left)").font(.headline).monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            Button("Undo") { model.reports.undo() }.buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("report.undo")
        }
    }

    private func done(_ cat: ReportCategory) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(.green)
            Text("\(cat.title) reported").font(.title2.bold())
            Text("Thanks. Other drivers can confirm or dismiss it.").foregroundStyle(.secondary)
            Spacer()
            Button("Done") { model.reports.reset(); dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
        .onAppear { model.haptics.success(enabled: model.settings.value.hapticsEnabled) }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 48)).foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center)
            Spacer()
            Button("Back") { model.reports.reset() }.buttonStyle(SecondaryButtonStyle())
        }
    }
}
