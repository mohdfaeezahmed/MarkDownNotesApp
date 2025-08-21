# MarkDownNotesApp
Notes app built with SwiftUI for UI, Core Data for local persistence, and TextKit + AttributedString for Markdown editing &amp; preview, all running in dark theme with a modern Apple style design.

Markdown Notes App (iOS)

Built an iOS notes application using SwiftUI with elegant dark-mode UI, Markdown editing (via UIKit/TextKit) and live preview (via AttributedString.markdown).

Implemented offline persistence with Core Data (SQLite), supporting tags, search, and pinning; optional CloudKit integration for iCloud sync.

Designed reusable SwiftUI components (Tag chips, Gradient backgrounds, NavigationSplitView) with focus on clean architecture and declarative state management.


## Features
- Markdown editor (TextKit) + live preview (AttributedString)
- Offline storage (Core Data), search, tags, pinning
- Clean dark UI (SwiftUI, gradients, chips)
- Optional iCloud sync (CloudKit)

## Screens
- Notes list with search, tag filter, pinning
- Editor (split view on large screens; toggle on phones)
- Live Markdown preview

## Tech Stack
Swift 5.9+, SwiftUI, UIKit/TextKit, Core Data (SQLite), (optional) NSPersistentCloudKitContainer.

## Requirements
- macOS + Xcode 15+
- iOS 16+ simulator or device

## Getting Started
```bash
git clone https://github.com/mohdfaeezahmed/markdown-notes-swiftui.git
cd markdown-notes-swiftui
open MarkdownNotes.xcodeproj   # or .xcworkspace if you add packages later
