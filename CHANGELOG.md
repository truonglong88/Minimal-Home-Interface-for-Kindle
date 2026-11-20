# Changelog

## Unreleased

Changes made since the last push to GitHub. They get the plugin version of the
next push.

- Contents: every chapter of long books is listed; rows are only drawn when they
  scroll into view (faster to open, less battery). Titles wrap to two lines
- Contents: the chapter being read opens two thirds of the way down the screen
- Reading: tap the strip along the bottom edge (where the time left is written) to
  switch time left in book / in chapter / nothing; it no longer turns the page
- Fix: "time left in chapter" didn't show in a book's last chapter; books without
  chapters skip that choice
- Updates over Wi-Fi: when a newer build is on GitHub, a dot appears on Home's
  Settings button and Settings shows an *Update available* card. *Update*
  downloads it, checks its checksum, installs it and restarts KOReader; if
  anything fails the old version stays. Checked only when Wi-Fi is already on
  and Home or Settings opens (at most once an hour from Home)
- Fix: tapping *‹ Back* on Contents could also open the chapter half hidden under
  the header, so the book jumped to an earlier page (the same applied to every
  scrolling page)
- Contents: swipe up from the bottom edge goes Home, as on Settings
- Updates download in the background: Settings stays usable (scroll, Back, swipe
  Home) and shows the progress from the file as it arrives. If a book is open
  when it finishes, it installs on the way back to Home
- Long-press the clock strip to take a screenshot on Settings, Contents and the
  other full pages too (as on Home and in a book)
- Swipe up for Home / pull down for the quick panel on Settings, Contents and the
  other pages (and the pull-down on Home): only from a thin strip at the edge,
  around the grabber, and only after a 150 px pull. Scrolling a list near the
  bottom no longer jumps Home
- Two update channels, set by how the plugin was built: official releases
  (Stable) and test builds from the `dev` branch (Dev). The Settings footer
  shows which one

## 0.1.35 – first public release

**Home**
- Currently reading (progress, time left, Continue reading), Start reading for a
  new library, Recent, All books with four sort orders, What's next after a book
- Search by title or author as you type, accents optional, recent searches
- Hold a book to delete it (asks first); Kindle-only (DRM) books are tagged
- A book that can't be opened shows a message and Home stays

**Reading**
- Minimal reading screen: clock on top, time left in chapter at the bottom,
  even top and bottom margins
- Reading menu: page slider with ‹ › one-page steps, Contents, Go to page
  (number keypad), Font panel (font, size, line spacing, margins, alignment),
  bookmark
- Swipe down from the top for the quick panel, up from the bottom for Home
- KOReader's own menus and gesture shortcuts are switched off on the page;
  page turns, links, footnotes and long-press on a word still work
- Finished screen at the end of a book

**Quick panel and Settings**
- Wi-Fi, Dark mode, Rotation lock, brightness with Auto (light sensor)
- Wi-Fi popup: networks nearby, join with a tap, password card
- Settings: SSH, full refresh, screensaver, default font, page-turn buttons,
  sleep timer, Restart KOReader, Exit to Kindle; swipe down for the quick panel,
  up for Home

**Everywhere**
- Own keyboard (letters / numbers / number keypad, Vietnamese Telex or English)
- Snackbar messages and a confirm dialog, also for KOReader's own messages
- Wi-Fi and the front light are off while the device sleeps and restored on wake
