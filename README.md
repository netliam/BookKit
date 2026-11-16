# 📚 BookKit

> ⚠️ **Status:** Work in progress. The library is not production-ready yet.

**BookKit** is a modular Swift library for building EPUB readers (EPUB 2 & 3) in iOS apps. It focuses on flexibility, clean architecture, and full control over the reading experience — without external service dependencies.

Designed for both **UIKit** and **SwiftUI**, it provides the core building blocks needed to implement a modern reader: parsing, rendering, navigation, and user interaction (highlights, bookmarks, etc.).

---

## ✨ What it aims to solve

Most EPUB solutions are either:
- Too rigid (hard to customize UI/UX)
- Too heavy (external SDKs, lock-ins)
- Too opaque (limited control over rendering)

**BookKit** takes the opposite approach:
- You own the UI
- You control persistence
- You extend the engine

---

## 🚀 Features (current & planned)

### 📖 Core EPUB support
- EPUB 2 parsing ✅
- EPUB 3 parsing 🚧
- OPF / NCX / NAV support
- Resource handling (HTML, CSS, images)

### 🧭 Navigation
- Chapter-based navigation
- Table of contents generation
- Horizontal pagination ✅ (`UIPageViewController`, curl or slide transition)
- Vertical pagination 🚧

### 🖍️ User interaction
- Text selection
- Highlights: filled, underline, squiggly and strikethrough, in any color
- Bookmarks
- Notes

### 🎨 Reader customization
- Apple Books-style reader: full-screen pages with floating controls, whole-book page numbers, Contents (table of contents, bookmarks, highlights)
- Font size & family
- Themes: Original, Quiet, Paper, Bold, Calm, Focus, following the system dark mode
- Line Guide: keeps the line you're reading prominent (dim or blur the rest)
- Layout tuning (line height, margins)

### 🔍 Search
- Full-text search ✅ (runs off the main thread, opens the match highlighted)

### 💾 Persistence
- Reading position tracking
- Highlight/bookmark persistence: use the built-in `BKJSONReaderStore`, or plug in your own storage

---

## 🧱 Architecture

- 100% Swift
- `WKWebView`-based rendering layer
- Modular design (parser, renderer, models separated)
- No external dependencies

The library is intentionally **unopinionated about storage and UI**, so it can fit different app architectures (VIP, MVVM, etc.).

---

## 📦 Installation

### Swift Package Manager

**Requirements:**
- iOS 16+ or Mac Catalyst 16+
- Xcode 15+

Add the package (this fork):

https://github.com/netliam/BookKit.git

In `Package.swift`:

```swift
.package(url: "https://github.com/netliam/BookKit.git", from: "0.1.0")
```

Then:

```swift
.product(name: "BookKit", package: "BookKit")
```

---

## 📕 PDF

PDFs open in their own Books-style reader, built on PDFKit:

```swift
let store = BKJSONReaderStore()
if let reader = BKPDFReaderViewBuilder.build(url: pdfURL, highlightStore: store, positionStore: store) {
    reader   // nil when the file isn't a readable PDF (e.g. password protected)
}
```

- **Reading:** pages fill the screen, controls show on tap, and edge taps or swipes turn pages.
- **Navigation:** a page slider, plus Contents built from the PDF's outline.
- **Marks:** bookmarks, and colored highlights from the selection menu (tap one to recolor or remove it).
- **Search and sharing:** search with snippets, and Share for the selection or the file.
- **Storage:** highlights and bookmarks are ordinary `BKHighlight`s whose coords are `BKPDFLocation`s, saved in the same stores as EPUB marks. The PDF file itself is never modified.
- **Book identifier:** by default it comes from the file's contents (`BKPDFReaderViewBuilder.identifier(forPDFAt:)`).

## 🗯️ Comics (CBZ)

Comic book archives open page by page, with zoom:

```swift
let reader = try BKComicReaderViewBuilder.build(url: cbzURL, highlightStore: store, positionStore: store)
```

- **Reading:** pages fill a black screen; tap the edges or swipe to turn, and pinch or double-tap to zoom.
- **Controls:** a page slider, bookmarks, a Pages grid (all pages or bookmarked only), and Share.
- **ComicInfo.xml:** supplies the title, the authors and right-to-left reading for manga.
- **Pages:** they're read from the archive on demand with `BKZipArchive` (a small read-only ZIP reader in Core) and decoded at screen size.
- **Declaring the file type:** iOS has no system type for `.cbz`, so declare one in your app's `Info.plist`, or the document picker greys `.cbz` files out:

```xml
<key>UTImportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key><string>com.bookkit.cbz</string>
    <key>UTTypeDescription</key><string>Comic Book Archive</string>
    <key>UTTypeConformsTo</key><array><string>public.zip-archive</string><string>public.data</string></array>
    <key>UTTypeTagSpecification</key>
    <dict><key>public.filename-extension</key><array><string>cbz</string></array></dict>
  </dict>
</array>
```

`BKBookFormat.allContentTypes` then includes it. CBR (RAR) archives aren't supported, since that needs a third-party decoder.

## 📱 Kindle books (MOBI, AZW3)

Unencrypted Kindle books are converted into an EPUB-style folder and read in the EPUB reader:

```swift
let book = try BKMobiConverter.convert(fileURL, to: bookFolder)   // .mobi, .azw3, .azw, .prc
```

- **MOBI 6:** the HTML is split at its page breaks. `filepos` links become anchors and images are written out.
- **AZW3 / KF8:** parts are rebuilt from their skeletons and fragments. Stylesheets, fonts, images and internal links are resolved.
- **Both:** Contents comes from the book's NCX, and metadata (title, author, language, cover) from EXTH.
- **Not supported:** DRM-protected books and HUFF/CDIC compression. These throw `BKBookError.unreadable`.
- **File types:** declare `com.bookkit.mobi` (`mobi`, `prc`) and `com.bookkit.azw3` (`azw3`, `azw`) in `UTImportedTypeDeclarations`, conforming to `public.data`, like `.cbz` above. Then the document picker allows them.

## 📄 Plain text and Markdown

`.txt` and `.md` files are converted into an EPUB-style folder and read in the same reader, so themes,
Line Guide, search, highlights and page numbers all work:

```swift
let book = try BKTextBookConverter.convert(fileURL, to: bookFolder)   // returns a BKEpubBook
BKReaderViewBuilder.build(book, spineIndex: 0, delegate: delegate)
```

- **Chapters:** Markdown is split at its headings. Plain text is split at lines like "Chapter 1" or "Part Two", and a Project Gutenberg `Title:`/`Author:` header becomes the book's metadata.
- **Long chapters:** these are cut into parts so pages stay quick to lay out.
- **File types:** use `BKBookFormat(fileURL:)` to tell formats apart, and `BKBookFormat.allContentTypes` for a document picker.

## 🔀 Migrating from DCEpubReaderKit

The library was renamed to BookKit, with no compatibility shims:

- **Package and product:** `DCEpubReaderKit` → `BookKit`. Use `import BookKit`, or the modules `BookKitCore`, `BookKitParser` and `BookKitRendering`.
- **Types:** the `DC` prefix is now `BK`, e.g. `DCReaderViewBuilder` → `BKReaderViewBuilder`, `DCHighlight` → `BKHighlight`, `DCEpubParser` → `BKEpubParser`. Replacing `\bDC([A-Z])` with `BK$1` in your code covers it.
- **Saved data is untouched:** reader preferences in `UserDefaults` and the `BKJSONReaderStore` folder use the same keys and paths as before.

## 🛠️ Roadmap

- [x] EPUB2 parsing
- [ ] EPUB3 full support
- [ ] Vertical pagination
- [x] Horizontal pagination
- [x] Highlights & bookmarks
- [x] State persistence helpers
- [x] Search engine
- [ ] Performance optimizations (large books)
- [ ] Accessibility improvements (VoiceOver, dynamic type)

---

## 💾 Using the built-in store

`BKJSONReaderStore` keeps highlights, notes, bookmarks and the reading position in one JSON file per book
(`Application Support/DCEpubReaderKit` by default; the folder kept its pre-rename name so existing data stays put). Wrap it in `BKStoreReaderDelegate` and pass that as the reader's delegate:

```swift
let store = BKJSONReaderStore()
let position = await store.position(bookId: book.uniqueIdentifier)

BKReaderViewBuilder.build(
    book,
    spineIndex: position?.spineIndex ?? 0,
    initialCoords: position?.coords,
    delegate: BKStoreReaderDelegate(store: store)
)
```

To use your own storage, implement `BKReaderCoordsProtocol` directly (as the example app does with Realm),
or implement `BKHighlightStoreProtocol` + `BKReadingPositionStoreProtocol` and keep `BKStoreReaderDelegate`.

## ⚙️ Configuring the reader

Pass a `BKReaderConfiguration` to `build` to change what the reader does in your app. Everything has a default:

```swift
var configuration = BKReaderConfiguration()
configuration.defaults = UserDefaults(suiteName: "reader")!   // where settings and colors are kept
configuration.bookId = myBook.id                            // instead of the OPF identifier
configuration.showsSearch = false                           // also showsLineGuide, showsRotationLock, …
configuration.onClose = { dismissWindow(id: "reader") }      // the reader has its own window
configuration.onOpenExternalURL = { openURL($0) }
configuration.fonts = [BKReaderFont(name: "Literata", cssFamily: "Literata", files: [literataURL])]

BKReaderViewBuilder.build(book, spineIndex: 0, delegate: delegate, configuration: configuration)
```

### Highlight menu

`configuration.highlightMenu` sets the styles, colors and actions of the menus for selected text and for a tapped
highlight. The default is the Books-style menu.

```swift
configuration.highlightMenu.palettes = [
    BKHighlightPalette(style: .highlight, colors: [("Yellow", "#FACC15"), ("Green", "#4ADE80")]),
    BKHighlightPalette(style: .squiggly, colors: [("Crimson", "#DC143C"), ("Dodger Blue", "#1E90FF")])
]
configuration.highlightMenu.selectionActions = [.note, .search, .copy, .custom(sendToNotebook)]
configuration.highlightMenu.highlightActions = [.note, .copy, .delete]

let sendToNotebook = BKCustomHighlightAction(title: "Send to Notebook", systemImage: "book") { context in
    // context.text, .spineIndex, .coords, .cfi, and .highlight for a tapped highlight
}
```

The menu shows the colors of the current style (the tapped highlight's, or the last one used) and a Style submenu
for the others. A style with one color appears as its own button in the row. Highlights store `annotationStyle` and
`color` (`#RRGGBB`) separately and keep any color, including ones the palettes don't offer, so the delegate's
`save(highlight:)` gets them unchanged. Highlights saved by older versions (a `style` name such as `"pink"`) still
decode.

### Progress

Besides `handleCoords`, the delegate gets `handleProgress(book:progress:)` after each page turn: the fraction of the
whole book read, and the whole-book page and page count once the book has been counted (as the reader shows "11 of 39").

Use the same `bookId` with `BKStoreReaderDelegate(store:bookId:)`. For rotation lock, return
`BKReaderOrientationLock.supportedOrientations(for: window)` from your app delegate's
`application(_:supportedInterfaceOrientationsFor:)`.

## 🔁 EPUB CFI

Positions and highlights are stored as the reader's own `coords`. To sync with CFI-based readers (epub.js and others),
convert with `BKCFIConverter`:

```swift
let converter = BKCFIConverter(book: book)
let cfi = await converter.cfi(fromCoords: highlight.coords, spineIndex: highlight.spineIndex)
let place = await converter.coords(fromCFI: "epubcfi(/6/4[ch1]!/4/2/1:5)")   // (spineIndex, coords)
```

The spine step (`/6` above) is `<spine>`'s real position in the book's OPF (`BKEpubBook.spineStep`), as foliate-js and
epub.js compute it.

## 🔍 Search

The reader's toolbar includes search. To search outside the reader, use the engine directly:

```swift
let engine = BKEpubSearchEngine(book: book)
let results = await engine.search("whale")   // [BKSearchResult] with chapter, snippet and match
```

---

## 🧪 Project maturity

This project is currently:
- In active development
- API unstable
- Not recommended for production use yet

Expect breaking changes until a `1.0.0` release.

---

## 🤝 Contributing

Contributions are welcome, especially in:
- EPUB edge cases
- Rendering bugs
- Performance improvements
- Accessibility

Basic flow:
1. Fork
2. Create branch (`feature/...`)
3. Commit clearly
4. Open PR

---

## ⚖️ License

Full license text in LICENSE file

---

## 🧩 Author

**Josep Cerdá Penadés**  
Senior iOS Developer  
https://github.com/novecapa

---

## 💡 Notes

- This is a **low-level reader engine**, not a plug-and-play UI component.
- If you're looking for a "drop-in reader", this might not be it.
- If you want control and extensibility, you're in the right place.
