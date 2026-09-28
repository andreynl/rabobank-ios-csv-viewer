# CSV Viewer

CSV Viewer is a small SwiftUI application created for the Rabobank Team Native assignment. It displays the bundled `issues.csv` at launch and can import another CSV file through the system file picker.

<p align="center">
  <img
    src="CSVViewer/CSVViewer/Assets.xcassets/LaunchArtwork.imageset/launch-artwork.png"
    alt="Rabobank CSV Viewer launch artwork"
    height="420"
  />
</p>

## Requirements

- Xcode 27 or newer
- iOS 27 Simulator or device

## Run

1. Open `CSVViewer/CSVViewer.xcodeproj`.
2. Select the `CSVViewer` scheme and an iPhone or iPad destination.
3. Run the application.
4. Use **Import** to choose another CSV or text file.

From the repository root, build with:

```bash
xcodebuild build \
  -project CSVViewer/CSVViewer.xcodeproj \
  -scheme CSVViewer \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Run the test suite with an installed simulator name:

```bash
xcodebuild test \
  -project CSVViewer/CSVViewer.xcodeproj \
  -scheme CSVViewer \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

## Architecture

The application uses Clean Architecture boundaries inside one application target:

```text
CSVViewer
├── App
├── Domain
│   ├── Entities
│   ├── Repositories
│   └── UseCases
├── Data
│   ├── FileAccess
│   ├── Parsers
│   └── Repositories
└── Presentation
    ├── ViewModels
    └── Views
```

- **Domain** defines the generic CSV document, data-source types, repository contract, errors, and loading use case. It has no SwiftUI or concrete filesystem dependency.
- **Data** implements CSV parsing, file reading, error mapping, and balanced security-scoped URL access.
- **Presentation** contains the main-actor view model and state-driven SwiftUI views.
- **App** creates and injects the concrete dependency graph.

These are logical modules rather than separate framework targets. The protocol boundaries and one-way dependencies keep the code easy to test and allow each layer to move into its own target later if the product grows. For this assignment, logical modules demonstrate that scaling path without adding unnecessary build-system overhead.

## Data Flow

`ContentView` asks `CSVViewModel` to perform the initial load once. The view model calls `LoadCSVUseCase`, which depends on the `CSVRepository` protocol. `FileCSVRepository` reads and parses the selected source in detached user-initiated work, then the main-actor view model publishes one of these states:

- loading
- loaded document
- empty document
- failure with a user-facing message

Starting a newer import cancels the previous task and advances a request generation. This prevents a slow older result from replacing the newer document even if the underlying operation does not stop immediately.

## CSV Support

The parser supports:

- comma-separated fields;
- quoted fields and commas inside quotes;
- escaped double quotes (`""`);
- line breaks inside quoted fields;
- LF and CRLF record endings;
- an optional UTF-8 byte-order mark;
- empty and trailing fields;
- a final record without a terminating newline.

The first record is the header. Short rows are padded with empty values. Rows wider than the header, unterminated quoted fields, and non-UTF-8 input produce typed errors instead of silently losing data.

## Testing

The project uses Swift Testing for unit and integration tests and XCTest for UI coverage.

- Parser tests cover valid syntax, multiline data, BOM handling, row normalization, malformed input, and encoding errors.
- Repository tests cover real file parsing, error mapping, and security-scoped access cleanup after success and failure.
- Use-case tests verify repository delegation and error propagation.
- View-model tests cover state transitions, one-time initial loading, imported-file replacement, and stale-result protection.
- The composition test loads the bundled sample through the real dependency graph.
- UI tests verify launch, the import action, compact table layout, horizontal scrolling, and compact navigation styling.

## Current Limitations

- The delimiter is fixed to a comma.
- Files must use UTF-8 encoding.
- Imported documents remain in memory only and are not restored on the next launch.
- The viewer does not edit, sort, filter, or infer column types.
- The table renders the loaded document in memory rather than virtualizing very large datasets.

Possible next steps include delimiter configuration, streaming for very large files, filtering and sorting, persistent security-scoped bookmarks, and extracting logical layers into separate targets when independent build boundaries become useful.
