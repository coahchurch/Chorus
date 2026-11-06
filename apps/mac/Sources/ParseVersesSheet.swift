import AppKit
import PresenterCore
import SwiftUI
import UniformTypeIdentifiers

struct ParseVersesSheet: View {
    let model: AppModel
    let serviceID: String
    let controls: ServiceControls?

    @Environment(\.dismiss) private var dismiss
    @State private var bibleStore = BibleLibraryStore()
    @State private var isWorking = false
    @State private var status = "Choose a PowerPoint presentation to find Bible references."

    private var defaultEnglishVersion: BibleXMLImporter.Version? {
        bibleStore.versions.first { !isTamilVersion($0) }
    }

    private var defaultTamilVersion: BibleXMLImporter.Version? {
        bibleStore.versions.first(where: isTamilVersion)
    }

    private func isTamilVersion(_ version: BibleXMLImporter.Version) -> Bool {
        let nameParts = version.name.localizedLowercase.split {
            !$0.isLetter && !$0.isNumber
        }
        return nameParts.contains(where: { $0 == "tam" || $0 == "tamil" })
            || containsTamilScript(version.name)
            || version.verses.prefix(50).contains { containsTamilScript($0.text) }
    }

    private func containsTamilScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0B80...0x0BFF).contains($0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "text.book.closed")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Import and Parse Verses")
                        .font(.title3.weight(.semibold))
                    Text("Find Bible references in slide text and add verses to this Service Flow.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if isWorking {
                ProgressView(status)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import and Parse Verses…", systemImage: "doc.badge.plus") {
                    choosePowerPoint()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { await bibleStore.load() }
    }

    private func choosePowerPoint() {
        guard let pptxType = UTType(filenameExtension: "pptx") else {
            status = "PowerPoint file selection is unavailable on this system."
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [pptxType]
        panel.message = "Choose a PowerPoint presentation (.pptx)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await prepareAndParse(url)
            }
        }
    }

    private func prepareAndParse(_ presentationURL: URL) async {
        await bibleStore.load()
        guard let version = defaultEnglishVersion else {
            importBibleThenParse(presentationURL)
            return
        }
        await parse(presentationURL, using: version)
    }

    private func importBibleThenParse(_ presentationURL: URL) {
        let alert = NSAlert()
        alert.messageText = "No English Bible Version"
        alert.informativeText = "Import an English Bible XML file before parsing verse text."
        alert.addButton(withTitle: "Import Bible XML…")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let xmlType = UTType(filenameExtension: "xml") else {
            status = "Bible XML file selection is unavailable on this system."
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [xmlType]
        panel.message = "Choose an English Bible XML file"
        panel.begin { response in
            guard response == .OK, let xmlURL = panel.url else { return }
            Task { @MainActor in
                guard let name = requestVersionName(
                    default: xmlURL.deletingPathExtension().lastPathComponent
                ) else { return }
                isWorking = true
                status = "Importing Bible version…"
                await bibleStore.importFiles([xmlURL], versionName: name)
                isWorking = false
                guard let version = defaultEnglishVersion else {
                    status = bibleStore.errors.isEmpty
                        ? "Import an English Bible version before parsing."
                        : bibleStore.errors.joined(separator: "\n")
                    return
                }
                await parse(presentationURL, using: version)
            }
        }
    }

    private func requestVersionName(default name: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Name This Bible Version"
        alert.informativeText = "Choose a name to show in Chorus."
        let field = NSTextField(string: name)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func parse(
        _ presentationURL: URL,
        using version: BibleXMLImporter.Version
    ) async {
        isWorking = true
        status = "Importing PowerPoint and scanning its slides…"
        defer { isWorking = false }

        let hasScopedAccess = presentationURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                presentationURL.stopAccessingSecurityScopedResource()
            }
        }

        let summaries = await model.importPowerPoint(urls: [presentationURL])
        guard let summary = summaries.first else {
            status = "Chorus could not import this PowerPoint presentation."
            return
        }
        guard let presentationID = summary.presentationID else {
            status = summary.warnings.isEmpty
                ? "Chorus could not read this PowerPoint presentation."
                : summary.warnings.joined(separator: "\n")
            return
        }

        let original: Presentation
        do {
            original = try await model.client.loadValue(Presentation.self, id: presentationID)
        } catch {
            status = "The presentation was imported, but its slide text could not be read: \(error.localizedDescription)"
            return
        }

        var references: [BibleXMLImporter.Reference] = []
        for slide in original.slides {
            let text = slide.objects
                .filter { $0.objectKind == .text }
                .map(\.text)
                .joined(separator: "\n")
            references.append(contentsOf: BibleXMLImporter.references(in: text))
        }

        var resolved: [(reference: BibleXMLImporter.Reference, verses: [BibleXMLImporter.Verse])] = []
        var unresolved: [String] = []
        for reference in references {
            if let verses = BibleXMLImporter.verses(for: reference, in: version) {
                resolved.append((reference, verses))
            } else {
                unresolved.append(reference.displayName)
            }
        }

        var presentations: [Presentation] = []
        var items: [ServiceItem] = [
            ServiceItem(
                id: UUID().uuidString,
                itemKind: .presentation,
                name: original.name,
                refId: original.id
            ),
        ]
        let versionLabel = BibleVerseSlideBuilder.shortVersionName(version.name)
        let tamilVersion = defaultTamilVersion
        let tamilVersesByID = Dictionary(
            (tamilVersion?.verses ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let tamilVersionLabel = tamilVersion.map {
            BibleVerseSlideBuilder.shortVersionName($0.name)
        }
        let design = model.slideBuilding.lyricsDesign
        var verseCount = 0
        var passageCount = 0

        for group in resolved {
            let versePresentations = group.verses.map { verse in
                BibleVerseSlideBuilder.makePresentation(
                    for: verse,
                    versionName: versionLabel,
                    tamil: tamilVersesByID[verse.id],
                    tamilVersionName: tamilVersionLabel,
                    themeSlideName: design
                )
            }
            presentations.append(contentsOf: versePresentations)
            verseCount += versePresentations.count

            let isPassage = group.reference.verses == nil
                || group.reference.endChapter != nil
                || group.reference.verses?.lowerBound != group.reference.verses?.upperBound
            if isPassage, let first = versePresentations.first {
                passageCount += 1
                items.append(ServiceItem(
                    id: UUID().uuidString,
                    itemKind: .header,
                    name: group.reference.displayName,
                    refId: first.id,
                    mxuDescription: BibleXMLImporter.parsedPassageServiceMarker
                ))
            }
            items.append(contentsOf: versePresentations.map {
                ServiceItem(
                    id: UUID().uuidString,
                    itemKind: .presentation,
                    name: $0.name,
                    refId: $0.id,
                    mxuDescription: BibleXMLImporter.parsedVerseServiceMarker
                )
            })
        }

        do {
            if !presentations.isEmpty {
                let folderedPresentations = presentations.map { presentation in
                    var presentation = presentation
                    presentation.folder = "Parsed Verses"
                    return presentation
                }
                _ = try await model.createInDrive(folderedPresentations).value
            }
        } catch {
            status = "The PowerPoint was imported, but verse slides could not be saved: \(error.localizedDescription)"
            return
        }

        guard (try? model.service(serviceID)) != nil else {
            status = "The presentation was imported, but this Service Flow is no longer available."
            return
        }
        let newItems = items
        model.updateService(serviceID) { service in
            service.items.append(contentsOf: newItems)
        }

        let referenceCount = resolved.count + unresolved.count
        var result = "Added “\(original.name)” and \(verseCount) verse row\(verseCount == 1 ? "" : "s")"
        if passageCount > 0 {
            result += " in \(passageCount) passage group\(passageCount == 1 ? "" : "s")"
        }
        result += " to the end of the Service Flow. Found \(referenceCount) reference\(referenceCount == 1 ? "" : "s")."
        if references.isEmpty {
            result = "Added “\(original.name)” to the Service Flow. No Bible references were found in its slide text."
        } else if !unresolved.isEmpty {
            let examples = unresolved.prefix(5).joined(separator: ", ")
            result += " Could not find \(unresolved.count) reference\(unresolved.count == 1 ? "" : "s") in \(version.name): \(examples)"
            if unresolved.count > 5 { result += ", …" }
            result += "."
        }
        if !summary.warnings.isEmpty {
            result += " PowerPoint import notes: \(summary.warnings.prefix(3).joined(separator: "; "))"
            if summary.warnings.count > 3 { result += "; …" }
            result += "."
        }
        status = result
    }
}
