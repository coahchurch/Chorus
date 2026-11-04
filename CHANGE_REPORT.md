# COAH Chorus - Technical Change Report

## Current implementation status (last technical refresh)

This section documents the current code state in addition to the feature history above. The report is deliberately implementation-oriented: it names the owning file, runtime data flow, persisted values, extension points, and the settings or code location needed to change each behavior.

### Build and runtime identity

- The executable and product are named **COAH Chorus** in the macOS app project and assets, while the repository and package names retain MxU/Chorus compatibility identifiers.
- The generated Xcode project is `apps/mac/Chorus.xcodeproj`. It is generated from `apps/mac/project.yml`; do not hand-maintain generated source membership unless the repository workflow intentionally changes.
- The app target depends on several local Swift packages under `apps/mac/Packages/`. The main source modules are:
  - `PresenterCore`: documents, library, indexing, import, search, songs, Bible, themes, and starter documents.
  - `OutputEngine`: screen roles, layer routing, output composition, and preview rendering.
  - `RenderEngine`: presentation composition and rendering primitives.
  - `SlideScene`: shared document and scene types.
  - `MediaEngine`: audio/video transport and media decoding.
  - `NDIKit`: discovery and sending/receiving for NDI.
  - `LocalAPI`: REST, WebSocket, scoped remote control, and `/remote`.
  - `StreamEngine`, `AudioEngine`, and `DeckLinkKit`: streaming, audio, and hardware-output support.
- Application state is rooted in `AppModel`, primarily in `apps/mac/Sources/AppModel.swift`.
- SwiftUI scene and window creation is split among `COAHApp`, shell views, module views, and panel/scene helpers under `apps/mac/Sources/`.
- `UserDefaults` stores operator preferences and small selections; authored library documents are stored through the library engine rather than directly as preference values.
- `CHANGE_REPORT.md` is documentation only. UI behavior is implemented by the Swift/SwiftUI files listed below.

## 10. Detailed application architecture

### 10.1 Startup and application shell

The app starts in the main application model and library client. Startup has several responsibilities:

1. Resolve the active library root and construct `LibraryClient`.
2. Start the library engine and database-backed reader.
3. Restore the app shell and selected navigation state.
4. Reconcile starter presentations, themes, overlays, backgrounds, and repair any missing built-in documents.
5. Restore configured outputs and service controls.
6. Attach live-monitoring, Local API, media, and remote-control services.

The main ownership points are:

- `apps/mac/Sources/AppModel.swift`: application lifecycle, active library, imports, starter-library repair, library mutations, and presentation control bridges.
- `apps/mac/Sources/ChorusApp.swift`: SwiftUI app entry point and top-level scenes/windows.
- `apps/mac/Sources/ShellView.swift`: primary navigation shell.
- `apps/mac/Sources/LibraryView.swift`: library sections, browser, selection, context actions, and document creation.
- `apps/mac/Sources/PresentGridView.swift`: service/presentation live-control grid.
- `apps/mac/Sources/ServiceControls.swift`: live slide, media, Bible, overlay, and automatic lower-third synchronization.

To change startup behavior, begin with `AppModel` and the relevant lifecycle method that calls `LibraryClient.start(...)`. To change window or module chrome, use the shell/module files rather than changing document logic.

### 10.2 Library document architecture

The library is not a collection of unrelated JSON files managed by SwiftUI. It is an actor/engine-backed document store built around typed document entities.

Core types and layers are:

- Typed entities under `apps/mac/Packages/PresenterCore/Sources/PresenterCore/Library/`.
- SQLite indexing in `LibraryIndex.swift` and `LibraryReader.swift`.
- Encoded Automerge document storage in the library engine.
- A typed SwiftUI read-side snapshot, exposed through `LibraryClient`.
- Editor checkouts/forks and commit tokens for collision-safe editor sessions.

Important files:

- `LibraryEngine.swift`: library bootstrap, storage, document mutation, batches, synchronization, and transaction ordering.
- `LibraryEngine+Editor.swift`: editor checkouts, replicas, parked history, pins, and release.
- `LibraryClient.swift`: asynchronous public API over the engine, command queue/tail ordering, reader startup, and warm-up.
- `LibraryIndex.swift`: SQLite metadata, FTS, library discovery, and query ranking.
- `LibraryStore.swift`: document persistence and on-disk layout.
- `DocumentEntities.swift` and generated model files: typed document schemas.
- `packages/schema/documents.json`: source schema used to generate Swift and Local API models.

`LibraryClient.checkout(...)` must be distinguished from presentation live state. Checkout creates an editable fork of a document for the slide editor. Live presentation state is a separate rendered/published state and should not be modified directly through the checkout except by committing it through the editor model.

To add a persisted field:

1. Update `packages/schema/documents.json`.
2. Run `node packages/schema/codegen.mjs`.
3. Review generated Swift and Local API schema changes.
4. Make the new field optional for backward compatibility with existing libraries.
5. Add migration/normalization handling only if old encoded documents need it.
6. Update the appropriate UI binding and commit path.

To change library write behavior, inspect `LibraryClient.enqueue(...)`, `LibraryEngine` batch methods, and the current optimistic-read code. UI changes alone cannot fix library consistency problems because the read-side snapshot and engine persistence must agree.

### 10.3 Editor checkouts and the slide editor

The slide editor uses presentation, theme, overlay, confidence-layout, and other typed document checkouts.

Primary implementation:

- `apps/mac/Sources/SlideEditorView.swift`: editor chrome, loading state, selection, panels, canvas, and error/retry UI.
- `apps/mac/Sources/SlideEditorModel.swift`: document replica, selection state, object commands, commit/persistence, undo behavior, and output refresh.
- `apps/mac/Sources/SlideObjectInspector.swift`: object properties, fonts, alignment, opacity, media fills, and related controls.
- `apps/mac/Sources/EditorCanvas.swift` and related canvas files: editor canvas layout.
- `apps/mac/Sources/SlideEditorModel+Animations.swift`: animation timeline and animation step behavior.

The edit flow is:

1. An ID and document type are selected in the library.
2. `SlideEditorView` starts the appropriate typed `SlideEditorModel` initializer.
3. `LibraryClient.checkout(...)` queues behind the current library command tail.
4. The engine installs the document if needed and opens an editor token.
5. The model forks the canonical replica, initializes a mirror for SwiftUI observation, and opens a landing inbox for incoming changes.
6. User edits update the replica and observation mirror.
7. Commit/release logic flushes changes back into the canonical document and library batch.

The overlay editor loading UI now has three states:

- normal/loading while checkout is pending;
- retryable failure when checkout returns no model;
- timeout after 15 seconds, where the user can retry the checkout instead of remaining in a permanent spinner.

To change checkout timeouts, locate the timeout task in `SlideEditorView.swift`. To change what happens on failure, update the model initializers in `SlideEditorModel.swift`, especially the presentation/theme/overlay branches. For missing-corrupt documents, fix document availability in `LibraryEngine+Editor.swift` or `AppModel` starter repair rather than hiding the error in SwiftUI.

## 11. Live presentation and output routing

### 11.1 Screen roles and outputs

Screen output roles are defined by the output model and consumed by `OutputManager`.

Relevant files:

- `apps/mac/Packages/OutputEngine/Sources/OutputEngine/OutputManager.swift`
- `apps/mac/Sources/ScreenConfigurationView.swift`
- `apps/mac/Sources/OutputPresetsController.swift`
- `apps/mac/Sources/NDIScreenOutputs.swift`
- `apps/mac/Sources/LivePanel.swift`
- `apps/mac/Sources/PresentGridView.swift`

Current roles include:

- `audience`: normal full presentation output.
- `confidence`: operator confidence/stage-facing layout where appropriate.
- `liveStream`: transparent overlay-only output for live-production systems.

The Live Stream role intentionally does not reuse the Audience rendering stack as a broad visual clone. It hides presentation layers not assigned to overlays and uses a transparent output background. To change which layers the Live Stream role displays, edit the layer visibility switch in `OutputManager.swift`.

Audience and Confidence should not receive the automatic Live Stream overlay layer. The isolation belongs in output rendering rather than only in the overlay-selection UI, so manual/live output code cannot accidentally leak a stream overlay onto another output.

### 11.2 Automatic lower-third routing

Automatic lower thirds for Live Stream are coordinated by `ServiceControls`, not by the slide editor or library browser.

Runtime flow:

1. Determine the current song/Bible presentation and current presented slide.
2. Select an overlay ID based on the document content:
   - Bible defaults come from `liveStream.defaultBibleOverlayID`;
   - song defaults come from `liveStream.defaultSongOverlayID`.
3. Create/update the automatic overlay slide from the current lyric/verse text.
4. Assign `automaticStreamOverlayID` so later dismissals remove the same overlay instance.
5. Refresh on live slide changes, so one overlay instance updates as the presenter advances.

Core code locations:

- `apps/mac/Sources/ServiceControls.swift`: live presentation synchronization, Tamil/English splitting, automatic overlay refresh, and current slide tracking.
- `apps/mac/Sources/Modules/LiveStreamModule.swift`: operator-facing Bible/song default overlay pickers.
- `apps/mac/Sources/Modules/ServiceControlsModule.swift`, `ServiceControlsPanel.swift`, and `ModuleWindow.swift`: module placement and service-controls rail/pop-out wiring.

To change the automatic overlay:

- Change defaults/persistence under `liveStream.defaultBibleOverlayID` and `liveStream.defaultSongOverlayID`.
- Change template selection and immediate refresh in `LiveStreamModule.swift`.
- Change overlay creation, replacement, dismissal, language splitting, and live-slide polling in `ServiceControls.swift`.
- Change output isolation in `OutputManager.swift`.
- Change available overlay definitions in the repaired starter overlay definitions or library documents.

Do not treat the stored ID as a permanently generated overlay. It is a template-document ID for the overlay. Service Controls instantiates a live overlay copy and tracks that live instance separately through `automaticStreamOverlayID`.

### 11.3 Lyrics and Bible lower-third themes

Starter overlay documents are defined in:

- `apps/mac/Packages/PresenterCore/Sources/PresenterCore/Library/StarterPacks/StarterPacks.swift`
- Repair/reconciliation: `apps/mac/Sources/AppModel.swift`

The four intended bilingual lyric lower thirds are:

- Clean Geometric (`pack.cleanGeometric.overlay.lyricsLower`)
- Bold Blocks / Yellow (`pack.boldBlocks.overlay.lyricsLower`)
- Digital (`pack.digital.overlay.lyricsLower`)
- Editorial Serif / Italic Serif (`pack.editorialSerif.overlay.lyricsLower`)

These are not ordinary full-screen lyric themes. They are lower-third Overlay documents containing text objects that accept runtime lyrics. Text is split at language boundaries and sized using `autoShrink` with minimum font sizes. The lyric lower thirds have static animation steps intentionally removed. Bible verse lower thirds retain their existing animation behavior.

To change a lyric design:

1. Edit its object geometry, fonts, colors, text boxes, and animation steps in `StarterPacks.swift`.
2. Keep runtime text object names and binding-compatible text placeholders consistent.
3. Keep minimum font sizes and `autoShrink` appropriate for the longest expected bilingual block.
4. Update `AppModel` repair logic when an existing installed document must be repaired.
5. Advance the starter-pack repair version so existing installations run the repair.
6. Use a focused overlay ID rather than matching overlay names, because users can rename documents.

The repair logic deliberately avoids replacing every customized overlay. It repairs known built-in document IDs and known design defects. User-edited overlays remain user content unless they are one of the startup-repair targets.

## 12. Song editing and presentation

### 12.1 Song document model

The song entity stores authored lyrics, not final presentation slides. Its core fields include:

- title and metadata;
- primary lyrics;
- paired secondary/transliteration lines;
- labeled parts;
- arrangement;
- presentation/reflow source.

Key files:

- `PresenterCore/.../Library/SongLyrics.swift`
- `apps/mac/Sources/SongEditorView.swift`
- `apps/mac/Sources/SongMapEditing.swift`
- `apps/mac/Sources/ImportLyricsSheet.swift`
- `apps/mac/Sources/SongClipboardImportSheet.swift`
- `apps/mac/Sources/ImportOpenLyricsSheet.swift`

Song presentation slides are generated from authored parts. Changes made to the live line-count setting should not mutate authored lyric documents. The same authored lyric stream feeds:

- normal song slide generation;
- slide preview;
- live stream lower thirds;
- song presentation output;
- service controls.

### 12.2 Original and transliteration layout

`SongEditorView.swift` lays out each verse as two side-by-side editors:

- original lyrics in the primary-language column;
- Latin transliteration in the adjacent column;
- a rounded text-background container;
- a height derived from the number of lyric lines;
- paired line validation for mismatched line counts.

To change the layout:

- Change the side-by-side composition in `partEditor(_:)`.
- Change column titles, spacing, borders, background, and widths in `lyricColumn(...)`.
- Change auto-fit height in `lyricEditorHeight(...)`.
- Change font or NS text-container behavior in `SongLinesTextEditor`.
- Change paste splitting in `splitPastedLyrics(...)`.

Text editors are represented through `NSViewRepresentable` because the app needs custom paste handling, vertical resizing, line-wrapped text storage, and direct control of the macOS text container. SwiftUI text-editor sizing alone does not provide all of that behavior in the current implementation.

### 12.3 Reflow and paired languages

The reflow pipeline is split across presentation and import code:

- `PresenterCore/.../Import/LyricTextImport.swift`
- `PresenterCore/.../Import/OpenLyricsImporter.swift`
- `apps/mac/Sources/ImportLyricsSheet.swift`
- `apps/mac/Sources/ServiceControls.swift`

Lines are normalized, preserved by logical verse/part, and then grouped according to the selected lines-per-slide. Bilingual pairing should use section labels and repeated section occurrences, not only array index, so uneven verses do not shift every later line.

To change lines-per-slide behavior, update the reflow function rather than only the SwiftUI slider. To change paired transliteration behavior, update both primary/source line normalization and presentation grouping, or the live Stream split logic may disagree with saved lyric presentation.

## 13. Library search and indexing

### 13.1 Search architecture

Library search has two layers:

1. SQLite FTS matching in `LibraryIndex.swift`.
2. normalized fuzzy fallback/ranking in `FuzzySearch.swift`.

Exact and prefix matching is useful for user-entered words. Levenshtein/adjacent-transposition scoring is useful for misspellings. Relevance ranking combines:

- title matches;
- exact or prefix term matches;
- transliterated/Latin text;
- lyric content;
- normalized width, case, and diacritics;
- subsequence or fuzzy similarity.

The FTS query normalizes multi-word searches into independent OR-prefix terms instead of requiring all words to match in one strict phrase. The UI should then rank combined results rather than appending fuzzy matches after exact results in arbitrary candidate order.

Core files:

- `LibraryIndex.swift`
- `FuzzySearch.swift`
- library browser filtering in `LibraryView.swift`
- fuzzy/search tests in `PresenterCore/Tests/PresenterCoreTests/`

To tune ranking:

- Change token normalization, Script-bridging, or width normalization in `FuzzySearch.swift`.
- Change exact SQL/FTS term construction in `LibraryIndex.swift`.
- Change the final score weights for title versus content.
- Add tests containing real Tamil title/lyric examples.
- Do not only loosen the fuzzy threshold; broad looseness can cause short generic words to outrank proper song-title matches.

For a query such as two Tamil transliterated words, first verify whether each script stream is indexed, whether query width/case/diacritics are normalized, and whether the title and lyric scores are combined deterministically.

## 14. OpenLyrics import

Primary implementation:

- `PresenterCore/.../Import/OpenLyricsImporter.swift`
- `PresenterCore/.../Import/LyricTextImport.swift`
- `apps/mac/Sources/ImportOpenLyricsSheet.swift`
- `apps/mac/Sources/LibraryView.swift`
- `apps/mac/Sources/AppModel.swift`
- tests under `PresenterCore/Tests/PresenterCoreTests/`

The importer supports:

- a single `<song>`;
- `<songbooks>` collections;
- direct `<lines>` text and nested `<line>` elements;
- title, CCLI, key, author, copyright, tempo, and presentation metadata where available;
- primary language/script;
- Latin transliteration;
- mixed verse/chorus/bridge parts;
- progress and import summaries.

`.xml` imports route through `OpenLyricsImporter` rather than generic text parsing. This distinction matters because generic imports do not preserve OpenLyrics metadata and XML namespaces/line structure.

Bulk imports enqueue bounded batches of up to 50 songs through `LibraryClient` and `LibraryEngine`. Each batch should report progress, publish one library batch, maintain optimistic UI state, and reconcile failed writes against the settled snapshot. Increasing the batch size without measuring memory and UI latency can make import UI/freeze behavior worse.

To change XML metadata mapping, start in `OpenLyricsImporter.swift`. To change user-facing import behavior, use `ImportOpenLyricsSheet.swift`. To change storage batching, use the bulk-create methods in `LibraryEngine.swift` and `LibraryClient.swift`.

## 15. Bible import and presentation

Primary implementation:

- `PresenterCore/.../Import/BibleXMLImporter.swift`
- `PresenterCore/.../Library/BibleStore.swift`
- `apps/mac/Sources/BibleLibraryView.swift`
- `apps/mac/Sources/BibleLibraryViewModel.swift`
- `apps/mac/Sources/ServiceControls.swift`

Supported XML families include OSIS and Zefania-style structures. Canonical verse identity uses:

- canonical book;
- chapter;
- verse.

Localized book names and translation-specific labels are presentation/import metadata rather than the canonical identity. This allows an English and Tamil translation to resolve the same verse without scanning translations or relying on a localized title.

Bible full-text and reference lookup use canonical indexes rather than a linear parse of all translations. To change canonicalization, update the importer and verse-ID helpers together. To change UI reference syntax, update parsing in `BibleLibraryViewModel.swift`; then add tests using both English and Tamil book references.

Show Now creates transient live content and does not persist a presentation. Add to Plan explicitly saves a reference-labelled presentation. This separation prevents an operator's transient preview from creating a service-plan side effect.

## 16. Overlay editing and missing-overlay repair

Overlay editing hangs generally need to be diagnosed at the document checkout boundary, not by only changing the spinner. The async path has:

1. SwiftUI editor task launches;
2. `LibraryClient.checkout(...)` waits for the library queue tail;
3. engine installs/loads the document;
4. replica and editor token are created;
5. model initialization refreshes scene state;
6. SwiftUI receives the model.

If any of steps 2-5 waits indefinitely, the whole UI remains in loading. The current view:

- reports immediate nil checkout;
- times out at 15 seconds;
- allows retry to create a new load task;
- cancels stale work when the presentation ID changes.

For a real recurring hang, also inspect:

- `LibraryClient.tail`: is an earlier queued task failing to settle?
- `LibraryEngine.checkout(...)`: is `installForEditor(...)` waiting on a missing file?
- `opened().store.url(...)`: does the document exist for its kind?
- parked editor history: is restore corrupted?
- Landing Inbox sequence/open behavior.

Starter overlays are repaired in `AppModel.swift` through document-ID-aware checks. Changing the starter marker alone does not repair an already-installed broken overlay. Known user-designed overlays should not be wholesale overwritten; targeted known-ID repair is the safer pattern.

## 17. Service controls, modules, and remote operation

Service Controls is both a live controller and a synchronization bridge. It is not a separate presentation engine.

Important areas:

- `apps/mac/Sources/ServiceControls.swift`
- `apps/mac/Sources/Modules/*`
- `apps/mac/Sources/ServiceControlsPanel.swift`
- `apps/mac/Sources/ModuleWindow.swift`
- `apps/mac/Sources/ServicePlannerView.swift`
- `apps/mac/Sources/ServicePreflightView.swift`

Service preflight checks:

- missing service presentation references;
- missing media/files;
- likely primary/transliteration line mismatches;
- invalid song/Bible document state where the program can detect it.

Remote operation uses the Local API package:

- `APIRouter.swift`: routes;
- `APIScope.swift`: authorization scopes;
- `WireModels.swift`: API payload shapes;
- `RemoteControlPage.swift`: browser UI and JavaScript/API calls;
- `APIWebSocketHandler.swift`: live updates.

The remote web page is a client of REST/WebSocket operations. It does not bypass authentication or alter library documents through browser-local state.

## 18. Branding, assets, and configuration

Branding is distributed through several files rather than a single string constant:

- app icon asset catalog under `apps/mac/Assets.xcassets/AppIcon.appiconset/`;
- Xcode app metadata and scheme in `apps/mac/project.yml`/generated project;
- user-visible strings in SwiftUI source files;
- product names, helper names, bundle display names, release packaging, and documentation;
- README and the license text.

The app keeps compatible existing bundle/document identifiers where needed. To change the displayed app name, update `project.yml`, `README.md`, visible titles/help text, and release scripts together. Renaming bundle/document identifiers alone can break upgrades to existing user libraries or launch services.

To update the app icon, replace or generate all required icon sizes in the asset catalog and rebuild. Generated app-icon output may remain in DerivedData until macOS relaunches or Xcode cleans the build folder.

## 19. Performance, responsiveness, and diagnostics

Known hot paths:

- large-library initial browser rendering;
- bulk context-menu selection materialization;
- per-document import writes;
- SQLite/FTS and fuzzy candidate ranking;
- overlay document checkout and replica fork;
- incoming NDI conversion;
- SwiftUI editor mirror refresh.

Current mitigations include:

- initial 300-row library page with Load Next;
- sorted browser cache invalidated by library change state;
- bulk folder actions process 25 records per chunk;
- OpenLyrics imports process 50 records per batch;
- startup/install work yields during bounded batches;
- canonical Bible IDs avoid repeated translation scans;
- asynchronous Bible decoding/import persistence;
- incoming NDI frame conversion off the main UI thread;
- lazy/per-action context-menu resolution.

These are workload bounds, not guaranteed main-thread profiling. Hitches can still come from SwiftUI layout, expensive document decode, an unbounded replica update, duplicate editor sessions, or disk/network activity.

Diagnostic entry points:

- `apps/mac/Sources/PerfHooks.swift`
- `apps/mac/Sources/BodyMeter.swift`
- `apps/mac/scripts/hitch-report.py`
- `apps/mac/scripts/perf/run.sh`
- Help → Report a Problem breadcrumb zip

When adding performance work, measure the specific operation first. Keep one complete end-to-end test, and compare CPU/main-thread work, wall time, and number of document writes rather than relying only on UI feel.

## 20. Test strategy and commands

Swift package tests can be run independently:

```bash
cd apps/mac/Packages
swift test --package-path PresenterCore
swift test --package-path SlideScene
swift test --package-path RenderEngine
swift test --package-path OutputEngine
swift test --package-path LocalAPI --force-resolved-versions
```

App build:

```bash
cd apps/mac
xcodegen generate
xcodebuild -project Chorus.xcodeproj -scheme Chorus \
  -configuration Debug \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile build
```

Validation should cover:

- OpenLyrics parse/import with Tamil and Latin streams.
- unequal verse line counts and section occurrence alignment.
- Bible OSIS/Zefania import and canonical verse reference.
- Live Stream isolation from Audience and Confidence.
- Bible and song automatic overlay replacement/dismissal.
- each of the four lyrics lower thirds and bilingual shrink fit.
- lyric-editor side-by-side layout and tall verse scrolling.
- overlay checkout success, immediate failure, timeout, retry, and cancellation.
- exact/prefix/fuzzy Tamil and English song searches.
- starter overlay repair with markers already present.
- library batching under large imports.
- real OBS/NDI only on hardware-available validation.

## 21. Manual modification cookbook

- Change lower-third overlay templates: `LiveStreamModule.swift`, `ServiceControls.swift`, `OutputManager.swift`, and `StarterPacks.swift`.
- Change four starter lyric designs: `StarterPacks.swift`; repair installed copies in `AppModel.swift`.
- Change Bible or song automatic text: language/extraction logic in `ServiceControls.swift`.
- Change output isolation or transparency: `OutputManager.swift`.
- Change Live Stream tab and role UI: `ScreenConfigurationView.swift` and Live Stream modules.
- Change song editor fields/layout: `SongEditorView.swift`; presentation generation in `SongLyrics.swift`.
- Change transliteration generation/import: `LyricTextImport.swift`, `ImportLyricsSheet.swift`, and `OpenLyricsImporter.swift`.
- Change lyrics-per-slide: reflow code in PresenterCore plus Present controls in service/grid views.
- Change library ranking: `LibraryIndex.swift` and `FuzzySearch.swift`.
- Change large-library pagination: `LibraryView.swift` and library snapshot/cache invalidation.
- Change XML import batching: `LibraryClient.swift`, `LibraryEngine.swift`, and `OpenLyricsImporter.swift`.
- Change Bible import/lookup: `BibleXMLImporter.swift` and `BibleLibraryViewModel.swift`.
- Change remote API: LocalAPI route/wire/page files.
- Change default song theme: `SettingsView.swift` and song presentation-time fallback in `AppModel.swift`/PresenterCore presentation generation.
- Change app icon/name: asset catalog, `project.yml`, release scripts, README, and visible UI strings.
- Change overlay edit loading timeout/recovery: `SlideEditorView.swift`.
- Change overlay checkout internals: `SlideEditorModel.swift` and `LibraryEngine+Editor.swift`.
- The mobile `/remote` page can operate without a token on the configured LAN port. This is intentionally limited to current status, previous/next, clear, panic clear, and `Back to slide` (`/v1/show/return-underlying`). It does not expose library editing or settings. The implementation is in `LocalAPIServer.swift`, `LocalAPIController.swift`, `RemoteControlPage.swift`, `APIRouteTable.swift`, `APIBridge.swift`, `LocalAPIBridgeAdapter.swift`, and `ServiceControls.swift`. Because this mode is unauthenticated, it must only be enabled on a trusted LAN.

---

# Legacy feature-history record

The sections below preserve the chronological implementation record that preceded the detailed architecture and modification reference above.

This report consolidates the work performed across the COAH Chorus project conversations, including changes made in the current work session. It distinguishes implemented application behavior from operations that still require an explicit verification step.

## Executive summary

The project has been branded and extended into a macOS presentation app for song, Bible, service-plan, and live-output workflows. The work includes OpenLyrics songbook import, Tamil/Latin lyric pairing and live reflow, Bible XML import/search/presentation, song background controls, service preflight and review tools, a dedicated lower-third NDI output, audience/stage/live-stream previews, and changes intended to reduce large-library UI stalls.

The existing song library contains 18,852 expected records from the supplied Tamil and English XML sources (16,075 Tamil and 2,777 English). A comparison-driven repair has now been applied and verified: the final comparison matched all 18,852 records and found **zero** remaining differences in generated slide text or reflow source, with zero unmatched, ambiguous, undecodable, or source-origin-mismatched records. Three English entries still score low on lyric-token overlap because their content is generic (for example, “Spontaneous” or “Live”); their normalized titles resolve to the expected source records without ambiguity. Both the original backup and a fresh pre-repair snapshot are preserved.

## 1. App setup, branding, and import foundation

- Completed the initial macOS build prerequisites: Xcode first-launch setup, Metal Toolchain, Node, and XcodeGen. Installed the ProPresenter protobuf compiler/plugin needed for local code generation.
- Fixed a generated-build product-path collision by giving the NDI and DeckLink helper products distinct names. Built and launched the app after the environment setup.
- Rebranded the macOS app as **COAH Chorus** and added the supplied app icon to the asset catalog.
- Updated user-visible names, metadata, project/scheme names, helper names, API/docs, import labels, and build/release tooling. Kept the existing bundle identifier and `.mxuslides`/`.mxubackup` formats for compatibility.
- Converted the supplied icon artwork into the app icon asset set and verified compiled icon renditions.
- Built on the existing generated Xcode project and its PresenterCore, rendering, output, NDI, and import packages.
- Enabled ProPresenter import by generating the protobuf Swift sources and updating the resolved package pins; the ProImport focused suite passed 112 tests.
- Added OpenLyrics XML parsing for both a single `<song>` and `<songbooks>` collections.
- The importer reads lyrics represented directly inside `<lines>` as well as nested `<line>` elements, extracts title and song metadata, and identifies Latin-script transliteration separately from the primary lyric script.
- Added a dedicated songbook import sheet and Library/AppShell entry points. The sheet retains the transliteration option; line-count changes now belong to the Present workflow rather than import.
- Routed `.xml` imports through the OpenLyrics importer rather than generic pasted-lyrics parsing, preserving song metadata such as CCLI information and musical key when present.
- Added clear load/import summaries and per-songbook progress reporting. Import parsing happens off the main actor, and record writes are now batched through the library engine (see responsiveness section).
- Documented supported songbook and Bible workflows in the README.

## 2. Song lyrics, bilingual alignment, and live reflow

- Added Tamil-script and Latin transliteration handling. Source-provided transliteration is kept as a distinct stream and paired with primary lyric lines; the importer recognizes ISO 15924 `Latn` metadata.
- Reworked bilingual slide grouping so a Tamil lyric and its corresponding Latin line remain together. Reflow uses the same grouping logic as initial import.
- Added section-aware alignment for additional-language streams. When both streams contain section labels, matching is performed within the corresponding section and repeated section occurrence instead of allowing an uneven verse to shift subsequent pairings. Non-sectioned input retains the existing fallback behavior.
- Normalized imported section and script metadata, including common section labels and Latin script declarations, to avoid false transliteration matches.
- Added a Present-time **Lines** slider, bounded from 1 to 32 primary lyric lines per slide. Applying a value rebuilds the current lyric grouping; paired transliteration remains with its lyric. The control is available for both a selected presentation and service presentation cards.
- Added a default song-theme preference in Settings. It is used as the presentation-time fallback for songs without an assigned theme; explicit unthemed slides remain unthemed, and existing presentations are not rewritten simply by changing the default.
- Added lyric review/audit and searchable song tags. The audit can flag empty slides and likely bilingual line-count imbalance; it does not claim semantic proof that every transliteration is the correct translation.
- Added paired-language checks to service preflight so an operator can catch likely line-count problems before a service. These heuristics complement, rather than replace, human proof-reading of Tamil and transliteration.

## 3. Bible import, search, planning, and presentation

- Added a PresenterCore Bible XML importer for OSIS and Zefania formats, including OSIS verse milestones, numbered/localized book names, common English book aliases, and invalid/empty input handling.
- Bible versions are stored as JSON under the app's Application Support data directory. Verse identity uses canonical book, chapter, and verse so English and Tamil translations can be matched independent of localized book names.
- Added a Bible tab in the Library with version import/selection, book/chapter navigation, reference search, full-text search across selected versions, and English/Tamil verse matching.
- Added passage-range selection and verse-reference/version labels.
- **Show Now** sends a selected verse directly to the live presentation path using a transient in-memory presentation; it does not require saving a song or making a slide deck first.
- **Add to Plan** creates a saved passage presentation and adds it to the current service, retaining reference/version information.
- Added a canonical verse-ID index for the Tamil translation lookup used by search results and passage slides to avoid repeatedly scanning a full translation.

## 4. Song backgrounds, lower thirds, and NDI outputs

- Added a dedicated Background inspector tab in the slide editor, including presentation-wide background media and fill controls for songs.
- Added a separate lower-third output target rather than mixing it into the ordinary NDI output. It has its own NDI sender, transparent background behavior, lower-third theme routing, and Slide-only layer routing.
- Added lower-third preview/theme selection and persistence in output settings. The same fired slide can therefore use a lower-third design on that target without replacing its normal appearance on the other outputs.
- Added **Audience**, **Stage**, and **Live Stream** preview tabs to the Present sidebar. Audience and Stage can select their respective configured output/layout previews. Live Stream discovers NDI inputs (including an OBS NDI source) and displays the selected incoming feed; selecting an input is for monitoring and does not put that feed on air.
- Moved NDI frame conversion off the main UI thread for the incoming-feed preview.

## 5. Service and remote-operation workflows

- Added service preflight checks for missing references/files and likely bilingual lyric line mismatches.
- Added service-plan Bible passage support so selected verses can be saved into the active service.
- Added a touch-friendly `/remote` browser page on the Local API, with authenticated operation using scoped bearer tokens. The existing REST/WebSocket status and show-control endpoints remain the transport; the remote page is a client of those endpoints, not a bypass around authentication.
- Kept live scripture “Show Now” separate from service plan persistence: an operator can display a selected verse immediately, or explicitly create and add a reference/version-labelled presentation to the current plan.
- Verified that songs and Bible verses use the live Slide layer for presentation. The dedicated lower-third NDI target is separate from the overlays layer and receives only the slide content through its configured theme.
- Preserved existing service metadata and presentation identity where a lyric repair/reflow changes slide text or slide count.

## 6. Large-library responsiveness and import behavior

- Changed Library row context menus so they no longer eagerly materialize the full selected-entry list for every row. Bulk selection is resolved only when a bulk action is invoked.
- Added bounded folder-refile processing in chunks of 25, with refused entries surfaced as errors instead of being silently discarded.
- Cached sorted library browser entries and invalidated that cache using library/list change state. Initial rendering is limited to 300 rows, with a **Load Next** action to continue through a large result set.
- Capped folder preview data to 16 entries.
- Added batched creation to the serialized LibraryClient/LibraryEngine write path. OpenLyrics imports now create songs in bounded batches (50 at a time), keep requested folder/sync-area assignment, yield between batches, and report progress.
- Kept optimistic read-side updates for each batch while publishing the underlying library batch as one operation. Import failures are reconciled against a settled library snapshot so successfully written IDs are not reported as if they were all lost.
- Added tests for bulk create, one-batch-per-chunk behavior, optimistic updates, and folder/area assignment.
- Optimized Bible verse lookup with a canonical-ID index as described above.
- Added asynchronous Bible version loading/import persistence so full translation files are decoded and written away from the SwiftUI main actor; import errors are reported in the Bible pane.
- The browser pagination is a deliberate workload bound, not a library-size cap: additional rows remain available through repeated **Load Next** actions.
- OpenLyrics library import uses batches of 50; mass folder moves use batches of 25. They are separate paths with different batch sizes because one creates documents and the other changes their folder/area.

These are targeted fixes to known hot paths, not a claim that every possible operation in the app has been profiled or that no macOS beachball can occur under any workload.

## 7. Existing song-library repair

- Source files: `~/Downloads/songsTamil_api.xml` (16,075 songs) and `~/Downloads/englishSongs.xml` (2,777 songs).
- Expected library total: 18,852 presentations across `Tamil Songs` and `English Songs`.
- The pre-repair comparison matched all 18,852 presentations and found 726 needing refresh (726 with changed slide text; 679 with changed reflow source; the counts overlap). It found zero unmatched records, ambiguous matches, decode failures, or source-origin mismatches.
- Matching normalizes titles and scores lyric-token overlap when a title has duplicate source records. Three English entries have generic “Spontaneous”/“Live”-style content and low token overlap; their exact normalized titles still resolve to the expected XML entries without ambiguity.
- The repair probe stages and validates all records before writing. It verifies source counts, library counts, decoding, origin, and song matches; writes only slide/section/reflow-source content while preserving presentation identity and unrelated metadata; and updates in bounded groups.
- Before applying changes, a full snapshot of the current library was created at `~/Library/Application Support/MxU Slides/Library-before-lyric-repair-20261101-2114`; its `index.sqlite` was byte-compared with the live database. The earlier `~/Library/Application Support/MxU Slides/Library-before-lyric-repair-20261101` backup was preserved.
- The first apply staged and wrote 726 presentations, but its immediate post-check identified 19 remaining differences. A second validated pass updated those 19; both runs scanned all 18,852 records and reported zero failed or ambiguous updates.
- Final post-repair comparison: **18,852 matched; 0 unmatched; 0 ambiguous; 0 decode failures; 0 source-origin mismatches; 0 changed slide-text records; 0 changed-source records**. Three records still have a low overlap score, but do not differ from their selected source output.

## 8. Code areas and verification

Notable current implementation areas include:

- `apps/mac/Packages/PresenterCore/Sources/PresenterCore/Import/OpenLyricsImporter.swift`
- `apps/mac/Packages/PresenterCore/Sources/PresenterCore/Import/LyricTextImport.swift`
- `apps/mac/Packages/PresenterCore/Sources/PresenterCore/Import/BibleXMLImporter.swift`
- `apps/mac/Packages/PresenterCore/Sources/PresenterCore/Library/LibraryEngine.swift`
- `apps/mac/Packages/PresenterCore/Sources/PresenterCore/Library/LibraryClient.swift`
- `apps/mac/Sources/ImportOpenLyricsSheet.swift`
- `apps/mac/Sources/ServiceItemChooser.swift`
- `apps/mac/Sources/PresentGridView.swift`
- `apps/mac/Sources/SettingsView.swift`
- `apps/mac/Sources/AppModel.swift`
- `apps/mac/Sources/LibraryView.swift`
- `apps/mac/Sources/BibleLibraryView.swift`
- `apps/mac/Sources/LivePanel.swift`
- `apps/mac/Sources/NDIScreenOutputs.swift`
- `apps/mac/Sources/OutputPresetsController.swift`
- `apps/mac/Sources/SlideObjectInspector.swift`
- `apps/mac/Sources/ServicePlannerView.swift`
- `apps/mac/Sources/ServicePreflightView.swift`
- `apps/mac/Packages/LocalAPI/Sources/LocalAPI/RemoteControlPage.swift`
- `apps/mac/Packages/PresenterCore/Sources/PresenterCore/Library/SongLyricsAudit.swift`
- `apps/mac/Packages/PresenterCore/Tests/PresenterCoreTests/LibraryActorTests.swift`

Focused validation most recently completed:

- `swift test --package-path apps/mac/Packages/PresenterCore --filter 'LibraryActorTests|ServiceItemChooserLogicTests|BibleXMLImporterTests|LyricTextImportTests|OpenLyricsImporterTests'` — **75 tests in 8 suites passed**, including the new batch-create cases.
- `git diff --check` — passed.
- `PATH="/tmp/node-v24.14.0-darwin-arm64/bin:$PATH" xcodebuild -project apps/mac/Chorus.xcodeproj -scheme Chorus -configuration Debug -destination 'platform=macOS' build` — **BUILD SUCCEEDED**.
- Pre-repair comparison — **18,852 matched; 726 changed slide-text records; 679 changed-source records**.
- Repair apply — **726 updates in the first pass, 19 residual updates in the second pass; 18,852 scanned; 0 failures**.
- Final post-repair comparison — **18,852 matched; 0 unmatched; 0 ambiguous; 0 decode failures; 0 changed slide-text records; 0 changed-source records**.
- `node --check scripts/animation-drive.mjs` — passed; the user-tagged script was inspected and not modified for this task.
- Chorus was closed normally for the offline repair and relaunched after the successful final comparison.

## 9. Remaining external verification

- A connected OBS/NDI sender and physical output screens are needed to verify real-world NDI discovery, latency, and audience/stage output behavior. The code/build can be verified without a live source, but this report does not claim a hardware-in-the-loop test.
- The final SwiftUI and batched-library changes compile in the Debug app build; they have not been manually exercised in a live presentation session after the final build.
- macOS responsiveness has not been measured with a formal benchmark suite. The listed changes remove specific repeated scans, eager selection expansion, unbounded initial rendering, and per-song import writes.
- The library now matches the supplied XML under the probe’s normalized-title, duplicate-resolution, reflow, and slide-text comparison. Three generic English entries have low lyric-token overlap, but are matched by title and produce no residual diff.

## 10. Feature batch: Bible passage presentation and accessibility

### Bible chapter builder

`apps/mac/Sources/BibleLibraryView.swift` now exposes **Present chapter** in the
chapter verse header. The action reads the currently indexed English chapter,
maps each English verse to the Tamil verse with the same canonical verse ID,
and creates an in-memory `Presentation` containing one slide per verse. Each
slide is generated through the existing `makeSlide(for:sectionID:tamil:)`
renderer, so the chapter uses the same bilingual typography, reference label,
version labels, auto-shrink behavior, and theme routing as individual Bible
verses. The first slide is fired through `ServiceControls.fire`; therefore the
existing next/previous slide commands and the LAN remote operate on the whole
chapter deck. No source XML is copied into the library and no existing
presentation is overwritten. The deck ID is deterministic for the selected
version, book, and chapter, which makes diagnostics and live-state tracking
stable during a service.

### Accessibility and appearance settings

`apps/mac/Sources/SettingsView.swift` adds persisted settings under the
`app.largeUI`, `app.highContrast`, and `app.accentColor` keys. Larger interface
uses SwiftUI's `.controlSize(.large)` at the settings-window root, high contrast
uses a controlled contrast multiplier rather than changing document colors, and
accent color is applied through `.tint` with indigo, blue, green, and orange
choices. The settings rows are searchable with the existing settings search
field, and the values survive relaunch through `@AppStorage`. These settings
currently target the settings and operator configuration surfaces; slide
document colors and output rendering remain unchanged.

### Operator command grouping

`apps/mac/Sources/PresentCommands.swift` adds a **Command Palette** menu under
Present. It provides direct menu access to next slide, previous slide, clear
all, and Settings, while reusing the existing `KeyCommand` bindings for the
navigation and clear actions. This deliberately does not introduce a second
shortcut engine: customized bindings continue to come from `KeyMapStore`, so
the menu and keyboard behavior cannot drift apart.

### Validation for this batch

- `xcodebuild -project apps/mac/Chorus.xcodeproj -scheme Chorus -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` — passed.
- The only remaining build diagnostic is the existing App Intents metadata warning; there are no Swift compile errors.
- The user-provided `EnglishBible.xml` and `TamilBible.xml` remain untracked and were not committed.

## 11. Current scope and deferred feature backlog

The user elected to keep the remaining feature backlog deferred after the
Bible/accessibility batch. No implementation was made for these items in this
update:

- rehearsal mode with simulated Audience, Confidence/Stage, and Live Stream
  outputs;
- saved speaker/person lower-third overlays and manual Live Stream triggering;
- an expanded NDI/output dashboard showing resolution, active overlay,
  dropped-frame counters, missing-source state, and runtime warnings;
- bulk library operations for rename, folders, theme assignment, missing
  transliteration generation, and repair/reflow;
- conservative duplicate detection with comparison, canonical selection, and
  explicit merge conflict decisions;
- a complete offline package-update workflow beyond the current bundled-library
  installation and merge prompt;
- a searchable, global command-palette window;
- shortcut conflict detection and shortcut editing;
- full theme preview scenarios;
- expanded VoiceOver labels, keyboard navigation, color-blind-safe indicators,
  and broader accessibility coverage;
- privacy-safe diagnostics export;
- physical-phone verification and further mobile remote polish;
- signed and notarized package distribution.

The existing implementations remain available and unchanged, including the
trusted-LAN remote on port 6980, conditional text fitting, bundled-library
installation/merge behavior, Live Stream-only overlay routing, bilingual song
editing, fuzzy library search, overlay editor timeout/retry behavior, and the
current unsigned package workflow. This section is a scope record, not a
claim that the deferred items are complete.

### Documentation-only update

This report update intentionally changes documentation only. No source files,
library assets, XML inputs, package contents, or runtime settings were changed
by this section.

## 12. Media, background, and presentation-asset separation

### Direct media selection is a slide

`apps/mac/Sources/ServiceControls.swift` now routes a direct
`fire(mediaItem:)` call through `fireMediaAsSlide`. The selected image or video
is represented as a one-slide in-memory `Presentation` using
`Slide.droppedMedia`, then sent through the normal slide firing path. This
replaces the currently presented slide instead of leaving the old slide
visible beneath a foreground media layer. The slide uses the existing
`CueMedia.droppedAsNewSlide` route, so the renderer's slide canvas fitting and
conditional text/media sizing apply consistently. Service-item media cues keep
their existing layer behavior; only direct library/media selection changes.

### Background imports remain backgrounds

`apps/mac/Sources/LibraryView.swift` now passes the selected library section
into media import behavior. Imports initiated from the Background tab call
`AppModel.importFiles(..., classification: .background)`. This applies to
both the file-picker import and drag-and-drop import paths. All other media
imports retain the normal default classification. In
`apps/mac/Sources/AppModel.swift`, newly imported media and reused duplicate
media receive the requested classification, so the Background tab filter and
global background picker see the item immediately. Selecting a background
still updates the persistent global background; it does not become a
foreground slide.

### Imported presentation assets

PowerPoint presentations require image/video files to remain in the library so
their slide references can render. They are therefore not discarded, but
`apps/mac/Packages/PresenterCore/Sources/PresenterCore/MediaImport/ImportMediaResolver.swift`
can mark resolver-created assets with the internal
`__presentation_asset__` collection. The PowerPoint importer enables this mode
in `PPTXImporter.swift`. `AppModel.browserEntries(in:)` excludes those marked
dependencies from the general Media tab while retaining them for the imported
presentation. This prevents a presentation's internal pictures from becoming
ordinary user-selectable Media entries.

### Validation

- Debug Xcode build passed after the routing, import classification, and
  presentation-asset filtering changes.
- Existing service-item media behavior was preserved.
- No source XML files or library assets were added to the commit.

## 13. Preventing global-background flashes during media changes

`apps/mac/Packages/SlideScene/Sources/SlideScene/ShowState.swift` now accepts
the `useGlobalBackground` flag when firing a slide. Normal presentations keep
the default behavior and continue resolving their final fallback background
from the persistent global background. Direct media slides, created by
`ServiceControls.fireMediaAsSlide` in
`apps/mac/Sources/ServiceControls.swift`, pass `useGlobalBackground: false`.

This keeps the selected media item's own slide background as the only visual
background during a direct media-to-media handoff. The global background is
not cleared from settings and is still used as soon as a normal song,
presentation, or other slide is fired. The change therefore removes the
intermediate global-background frame without changing the user's configured
background.

Validation:

- Debug Xcode build passed after the transition change.
- Existing normal-slide global-background fallback remains enabled by default.

## 14. Background selection does not fire live output

Background entries are stored as the same underlying `MediaItem` type as
ordinary media, so the presentation shell previously interpreted a selected
background as a directly fireable media selection. `apps/mac/Sources/AppShell.swift`
now excludes media selections while the Background tab is active. This keeps
the current song or media output live instead of replacing it or briefly
revealing another background.

`apps/mac/Sources/LibraryView.swift` observes selection while the Background
tab is active and calls `setGlobalBackground(mediaID:)`. The clicked item is
therefore assigned as the persistent global background only; it is not fired
to the output. The new background becomes visible the next time a normal song
or presentation slide resolves the global-background fallback. Existing live
media remains visible until the operator explicitly changes or clears it.

## 15. Current Big confidence media mirror

`apps/mac/Sources/RenderContext.swift` now tracks whether the active output is
a foreground media presentation using `confidenceMediaModeBox`. Direct media
slides set this state, and service-item media sets it only when the media
classification is not `.background`. Normal slide firing clears the state, so
backgrounds and song slides do not trigger the mirror.

When the active confidence layout is named **Current Big**, its confidence
scene provider returns the same transitioned, visibility-filtered audience
scene while foreground media is active. This displays the media at the same
fit and crop as the Audience output rather than rendering it as a text
confidence layout. Other confidence layouts remain unchanged, and the
Current Big layout automatically returns to its normal confidence rendering
for songs, slides, and background-only output.

Validation:

- Debug Xcode build passed after the Current Big media mirror change.

### Preview-path correction

The first implementation covered physical confidence screens through
`OutputManager.confidenceSceneProvider`, but the Stage preview uses
`RenderContext.previewProvider(for:)` and its `PreviewTargetLogic` layout path.
That path previously bypassed the media mirror and always called
`ConfidenceSceneBuilder.scene`. `RenderContext.previewProvider(for:)` now
applies the same Current Big/foreground-media check to preview layout targets,
so the in-app Stage preview and the physical confidence output use identical
behavior.

### Media-state correction

The media mirror flag was initially set before calling the shared slide-fire
method. That method's normal-slide reset immediately cleared it, so the
Current Big branch never observed foreground media as active. The corrected
implementation carries an explicit `mediaMode` argument through
`ServiceControls.fire` and its deferred theme-fill path into `land`. Normal
slides pass the default `false`; direct media slides pass `true` after being
constructed, and background-classified service media remains excluded.
## 27. Service workflows, live undo, and remote pairing (2026-03-09)

### 27.1 Service export/import

The Library command menu now includes **Export Service…** and **Import Service…**. Service files use the `.chorusservice` extension and contain a versioned JSON envelope with the service metadata and ordered `ServiceItem` references. Imports always receive a new service ID and are selected as the current service, preventing accidental replacement of an existing service. Unsupported formats and malformed files are surfaced with an alert.

Implementation:

- `AppModel.exportService(_:to:)` writes a pretty-printed, sorted-key JSON document.
- `AppModel.importService(from:)` validates the format/version, creates a new ID, marks the name as imported, and persists the service.
- `LibraryCommands` owns the native save/open panels and user-visible error handling.

This is intentionally a service-only interchange format. Referenced library assets are not copied; the receiving library must contain the referenced songs, presentations, media, and overlays.

### 27.2 Command-Z for live slide actions

The existing Undo command now falls back to the focused `ServiceControls` instance after text-field, slide-editor, and library journal undo targets are exhausted. The latest live slide can be restored from `ShowState.lastSlide`, including a previously live foreground media slide when it has a presentation context. Live undo state is transient and is not written to the library.

### 27.3 QR remote pairing

Local API settings now provide **Show QR** beside the remote URL. The QR is generated locally with macOS Core Image (`CIQRCodeGenerator`), so no network service or third-party dependency is involved. Scanning the code opens the existing trusted-LAN remote at port `6980`.

### 27.4 Validation

- `xcodebuild -project apps/mac/Chorus.xcodeproj -scheme Chorus -configuration Debug -destination 'platform=macOS' build` passed after these changes.
## 28. v1 DMG packaging (2026-11-03)

Created an unsigned v1 distribution image from a fresh Release build:

- Output: `apps/mac/build/dmg-v1/COAH-Chorus-v1.dmg`
- Contents: `Chorus.app` and an `/Applications` installation link
- Approximate image size: 33 MB
- Build revision: `76505e6`

The image includes the app bundle and its embedded runtime dependencies. It is unsigned because this Mac has no valid Developer ID signing identity installed; macOS may require the user to approve the app in Privacy & Security on first launch.
## 29. Transparent live-stream lower third (2026-11-04)

Fixed the dedicated lower-third NDI output retaining an opaque black backdrop. The output engine previously handled transparent backgrounds only in the normal routed-output path; its `.liveStream` fast path returned early after explicitly setting black. Transparent lower-third targets now receive an alpha-zero background in that path as well, preserving downstream compositing over the stream video.

Added a focused regression test covering a live-stream-role output. OutputEngine tests and a full Debug Chorus build passed.
