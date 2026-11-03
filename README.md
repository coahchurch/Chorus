# COAH Chorus

COAH Chorus is a native macOS presentation app for churches: lyrics (including OpenLyrics XML songbooks), slides, media, timers, stage displays, multitrack stems, timecode, NDI and DeckLink output, and live streaming. Everything runs on this Mac: no account, no server.

Choose English or Tamil in Settings → General → Language. The File → Import → Import OpenLyrics XML workflow preserves Tamil text and available Latin transliteration, and large songbooks import in responsive batches with progress. The separate Songs library supports importing lyrics from the clipboard, creating a song from scratch, and importing OpenLyrics songs. These documents store labeled lyric parts and paired original/transliteration lines—not slides—and generate slide projections only for preview and presentation, so live line-count changes never modify saved lyrics. During Present, adjust how many primary lyric lines appear on each slide; paired transliteration stays with its lyric line and custom song arrangements are preserved. When creating lyrics manually, add aligned lines in a second language and optionally generate an editable Latin transliteration. Generated transliterations use the system's transliteration rules and should be reviewed for accuracy. Untranslated interface text remains in English.

The Library's Bible tab imports OSIS or Zefania XML versions and pairs English/Tamil verses by reference. Like the other Library tabs, Bible can be dragged to reorder it in the tab row. Search by passage or verse text across imported versions, select a verse range, and use **Show Now** to take one verse live without saving a presentation; **Add to Plan** saves selected verses with reference/version labels and attaches them to the current service. The Bible tab can also configure a dedicated lower-third NDI feed with a preview, a selected slide theme, slide-only routing, and a transparent background, without changing the main outputs. In the slide editor, Background has its own inspector tab for song backgrounds. A song's library menu opens lyric checks and searchable tags; a service's menu runs a preflight for missing references, files, and likely bilingual line mismatches.

The Present sidebar keeps Audience, Stage, and Live Stream previews in separate tabs. Audience and Stage can target their own configured screen or stage-layout previews; Live Stream discovers NDI inputs, including OBS, and displays the selected feed without putting it on air. Settings includes a default song theme for unthemed songs; it is applied at presentation time and does not rewrite existing songs. Large library lists are paged in batches, and XML songbook imports write songs in bounded batches while reporting progress.

COAH Chorus is source-available under the PolyForm Shield License 1.0.0. See [LICENSE.md](LICENSE.md).

What the license allows:

- [x] Use it for any purpose, including commercially and in production, at a church, a venue, or a business
- [x] Read, modify, and build on the source
- [x] Fork it and distribute copies or modified versions, as long as the license and its notice travel with them
- [x] Contribute changes back

What it does not allow:

- [ ] Providing a product that competes with MxU Slides, or with any product MxU provides using it, even if that product is free, uses a different interface or platform, or is written in another language
- [ ] Removing or altering the license text or the required notice

The full terms, including what happens if MxU later ships a product that competes with yours, are in [LICENSE.md](LICENSE.md).

## Getting started

Requirements:

- macOS 14 or newer, Xcode 26 (Swift 6 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Node 24 (`.tool-versions`) for the schema codegen and the drive scripts
- Optional, for NDI inputs and outputs: install the [NDI SDK for Apple](https://ndi.video/for-developers/ndi-sdk/) at `/Library/NDI SDK for Apple`. Without it `NDIKit` builds a stub and NDI is unavailable in the app. After installing or removing the SDK, delete `~/Library/Caches/org.swift.swiftpm/manifests` and use Product › Clean Build Folder. `apps/mac/scripts/release-dmg.sh` still requires it.

The Blackmagic DeckLink SDK headers are vendored, so DeckLink output needs no install to build.

Build and run:

```bash
cd apps/mac
xcodegen generate
xcodebuild -project Chorus.xcodeproj -scheme Chorus -configuration Debug -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile build
open "$(xcodebuild -project Chorus.xcodeproj -scheme Chorus -configuration Debug -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -showBuildSettings 2>/dev/null | awk '/TARGET_BUILD_DIR/{print $3; exit}')/COAH Chorus.app"
```

Or open `Chorus.xcodeproj` in Xcode after `xcodegen generate` and run the `Chorus` scheme. Re-run `xcodegen generate` whenever you add or remove source files; the project file is generated and not checked in.

Dependency versions are pinned in the checked-in `Package.resolved` files for `LocalAPI` and `StreamEngine`. XcodeGen combines those pins into the app's generated lockfile. Every app build verifies the generated lock against the package pins, and the commands above and the release script disable automatic dependency updates. For an intentional dependency update, update the affected package's lockfile, regenerate the project, and test both the package and app.

## Building and testing

Each package builds and tests on its own with SwiftPM. None of them needs the NDI SDK (`NDIKit` builds a stub without it):

```bash
cd apps/mac/Packages
swift test --package-path PresenterCore
swift test --package-path SlideScene
swift test --package-path RenderEngine
swift test --package-path OutputEngine
swift test --package-path LocalAPI --force-resolved-versions
```

Run `node apps/mac/scripts/test-dependency-locking.mjs` from the repository root to check lock generation and rejection of missing, conflicting, or changed pins.

Debug builds are ad-hoc signed (`CODE_SIGN_IDENTITY: "-"` in `apps/mac/project.yml`), so a fresh clone builds and runs without an Apple developer account. Set `bundleIdPrefix`, `DEVELOPMENT_TEAM`, and a signing identity there before archiving or distributing.

### Document schema

Edit `packages/schema/documents.json`, then regenerate:

```bash
node packages/schema/codegen.mjs
```

That rewrites `PresenterCore/Sources/PresenterCore/Generated/Models.swift` and `LocalAPI/Sources/LocalAPI/Resources/document-schemas.json`. Fields added after a type ships must be optional so existing libraries keep decoding.

### Release build

`apps/mac/scripts/release-dmg.sh` builds, Developer ID-signs, notarizes, and staples a DMG. It expects a `notarization-profile` entry in your Keychain (`xcrun notarytool store-credentials`) and the NDI SDK's redistributable license file.

### Local API

With Settings › Local API enabled, the app serves a REST and WebSocket API on port 6980, authenticated by scoped bearer tokens created in the same pane. Open `/remote` on a phone on the same trusted network for touch-friendly live controls; the page needs an Operate key. `GET /v1/status` returns the live slide; `scripts/*.mjs` show it driving a show. The route table and OpenAPI document live in `apps/mac/Packages/LocalAPI`.

### Perf and diagnostics scripts

- `apps/mac/scripts/perf/run.sh` runs the scripted editor and animation perf check against a staged build and compares with `baseline.json`.
- `apps/mac/scripts/hitch-report.py` summarizes the main-thread hitches recorded in the app's breadcrumb logs (Help › Report a Problem saves them as a zip).
- `apps/mac/scripts/hls-sink.mjs` / `hls-replay.mjs` stand in for an HLS ingest endpoint when testing streaming.

## Contributing

Pull requests are welcome. By submitting one you agree that your contribution is licensed to MxU under the terms in [LICENSE.md](LICENSE.md). The MxU name and logos are trademarks and are not covered by the license.
