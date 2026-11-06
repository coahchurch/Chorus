import PresenterCore
import SwiftUI

struct ServicePreflightView: View {
    let model: AppModel
    let serviceID: String

    @Environment(\.dismiss) private var dismiss
    @State private var serviceName = ""
    @State private var findings: [Finding] = []
    @State private var loading = true
    @State private var errorMessage: String?

    private struct Finding: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let isWarning: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Service Preflight", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if loading {
                ProgressView("Checking service…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Preflight Could Not Run",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                Text(serviceName)
                    .font(.title3.weight(.semibold))
                if findings.isEmpty {
                    ContentUnavailableView(
                        "Ready to Present",
                        systemImage: "checkmark.seal",
                        description: Text("All service references are present, and no empty or strongly unbalanced bilingual song slides were found.")
                    )
                } else {
                    List(findings) { finding in
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(finding.title)
                                    .font(.subheadline.weight(.medium))
                                Text(finding.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: finding.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                .foregroundStyle(finding.isWarning ? .orange : .green)
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .padding(18)
        .frame(width: 580, height: 560)
        .task(id: serviceID) { await runPreflight() }
    }

    private func runPreflight() async {
        loading = true
        errorMessage = nil
        findings = []
        defer { loading = false }

        do {
            let service = try await model.client.loadValue(Service.self, id: serviceID)
            serviceName = service.name
            if service.items.isEmpty {
                findings.append(Finding(
                    title: "Service is empty",
                    detail: "Add at least one service item before presenting.",
                    isWarning: true
                ))
                return
            }

            for item in service.items {
                switch item.itemKind {
                case .presentation:
                    do {
                        let presentation = try await model.client.loadValue(
                            Presentation.self, id: item.refId
                        )
                        if let media = presentation.background {
                            do {
                                let mediaItem = try await model.client.loadValue(
                                    MediaItem.self, id: media.mediaId
                                )
                                if model.isMediaFileMissing(mediaItem) {
                                    findings.append(Finding(
                                        title: "\(item.name): background media is missing",
                                        detail: "The referenced background file is not available in this library.",
                                        isWarning: true
                                    ))
                                }
                            } catch {
                                findings.append(Finding(
                                    title: "\(item.name): background media unavailable",
                                    detail: error.localizedDescription,
                                    isWarning: true
                                ))
                            }
                        }
                        findings += SongLyricsAudit.inspect(presentation).map { issue in
                            Finding(
                                title: "\(item.name) — \(issue.slideName)",
                                detail: issue.detail,
                                isWarning: true
                            )
                        }
                    } catch {
                        findings.append(Finding(
                            title: "\(item.name): presentation unavailable",
                            detail: error.localizedDescription,
                            isWarning: true
                        ))
                    }
                case .song:
                    do {
                        let presentation = try await model.client.loadValue(
                            Presentation.self, id: item.refId
                        )
                        findings += SongLyricsAudit.inspect(presentation).map { issue in
                            Finding(
                                title: "\(item.name) — \(issue.slideName)",
                                detail: issue.detail,
                                isWarning: true
                            )
                        }
                    } catch {
                        if let song = await model.loadSong(item.refId) {
                            findings += SongLyricsAudit.inspect(song.presentation()).map { issue in
                                Finding(
                                    title: "\(item.name) — \(issue.slideName)",
                                    detail: issue.detail,
                                    isWarning: true
                                )
                            }
                        } else {
                            findings.append(Finding(
                                title: "\(item.name): song unavailable",
                                detail: "The lyric document could not be loaded.",
                                isWarning: true
                            ))
                        }
                    }
                case .media:
                    do {
                        let media = try await model.client.loadValue(MediaItem.self, id: item.refId)
                        if model.isMediaFileMissing(media) {
                            findings.append(Finding(
                                title: "\(item.name): media file is missing",
                                detail: "Relink or re-import this media before the service.",
                                isWarning: true
                            ))
                        }
                    } catch {
                        findings.append(Finding(
                            title: "\(item.name): media unavailable",
                            detail: error.localizedDescription,
                            isWarning: true
                        ))
                    }
                case .audio:
                    do {
                        let audio = try await model.client.loadValue(AudioItem.self, id: item.refId)
                        if model.isAudioFileMissing(audio) {
                            findings.append(Finding(
                                title: "\(item.name): audio file is missing",
                                detail: "Relink or re-import this audio before the service.",
                                isWarning: true
                            ))
                        }
                    } catch {
                        findings.append(Finding(
                            title: "\(item.name): audio unavailable",
                            detail: error.localizedDescription,
                            isWarning: true
                        ))
                    }
                case .playlist:
                    do {
                        _ = try await model.client.loadValue(Playlist.self, id: item.refId)
                    } catch {
                        findings.append(Finding(
                            title: "\(item.name): playlist unavailable",
                            detail: error.localizedDescription,
                            isWarning: true
                        ))
                    }
                case .header, .info:
                    break
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
