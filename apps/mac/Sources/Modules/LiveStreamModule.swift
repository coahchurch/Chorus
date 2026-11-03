import PresenterCore
import SwiftUI

struct LiveStreamModule: View {
    let model: AppModel
    let controls: ServiceControls

    @AppStorage("liveStream.defaultBibleOverlayID") private var bibleOverlayID = ""
    @AppStorage("liveStream.defaultSongOverlayID") private var songOverlayID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ModuleHeaderBar {
                Text("LIVE STREAM")
            } trailing: {
                EmptyView()
            }

            Text("Choose the lower thirds shown automatically on the Live Stream output.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                defaultPicker(
                    title: "Bible verse",
                    selection: $bibleOverlayID,
                    onChanged: {
                        controls.refreshAutomaticStreamOverlay()
                    }
                )

                defaultPicker(
                    title: "Song lyrics",
                    selection: $songOverlayID,
                    onChanged: {
                        controls.refreshAutomaticStreamOverlay()
                    }
                )
            }

            Text("These overlays are visible only on a screen assigned to Live Stream.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func defaultPicker(
        title: String,
        selection: Binding<String>,
        onChanged: @escaping () -> Void
    ) -> some View {
        let overlays = model.entries(in: .overlays)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker(title, selection: selection) {
                Text("Automatic default").tag("")
                ForEach(overlays, id: \.id) { entry in
                    Text("\(entry.subkind.split(separator: "/").first.map(String.init) ?? "") — \(entry.name)")
                        .tag(entry.id)
                }
            }
            .onChange(of: selection.wrappedValue) { _, _ in onChanged() }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            if selection.wrappedValue.isEmpty {
                Text("Automatically uses a matching lower third.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if overlays.allSatisfy({ $0.id != selection.wrappedValue }) {
                Text("Saved overlay is no longer in the library.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}
