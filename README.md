# Wndr

Wndr is a Mac app for people who read a lot of PDFs and want their notes to stay close to the source material.

It gives you one place to collect papers, reports, and reference docs, highlight what matters, and keep Markdown notes alongside them. Everything stays on your Mac.

## Install

The easiest way to install Wndr is from GitHub Releases:

1. Open the [Releases](https://github.com/adamkz007/wndr/releases) page.
2. Download `Wndr-v0.3.0.dmg`.
3. Open the `.dmg` file.
4. Drag `Wndr.app` into your `Applications` folder.
5. Open Wndr from `Applications`.

If macOS warns you the app was downloaded from the internet, confirm that you want to open it.

## What Wndr Does

Wndr is built for a simple research workflow:

- Import PDFs by drag-and-drop or with the file picker
- Read in a focused, native Mac viewer
- Highlight and annotate important passages
- Write Markdown notes with live preview
- Organize documents with collections and tags
- Search your library by filename or content

## First Run

When you open Wndr for the first time:

1. Choose where you want your library to live.
2. Import a few PDFs.
3. Start reading, highlighting, and writing notes.

Wndr creates the library structure for you automatically.

## Current Status

`v0.3.0` is an early release, but the core workflow is already in place.

Available today:

- PDF import, reading, zooming, and navigation
- Highlights and underline annotations
- Markdown notes with auto-save and live preview
- Collections and tags for organization
- Search across your library
- Native light and dark mode support

In progress:

- Better linking between notes and PDF selections
- A richer inspector panel with more context around documents and annotations

## Build From Source

If you want to run the app from source instead of installing the release build:

1. Open `Wndr.xcodeproj` or `Wndr.xcworkspace` in Xcode.
2. Build and run the `WndrApp` scheme.

You’ll need macOS with Xcode installed.

## Documentation

If you want more detail, these files are the best place to look:

- `STATUS.md` for implementation progress
- `RELEASE.md` for packaging and release steps
- `docs/product-spec.md` for the product direction
- `docs/architecture.md` for the system design
- `docs/data-model.md` for storage and entities

## Privacy

- Your library stays local to your Mac
- No cloud account is required
- No analytics or telemetry run unless you explicitly opt in
