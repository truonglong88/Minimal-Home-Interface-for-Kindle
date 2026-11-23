# Changelog

## Unreleased

Changes made since the last push to GitHub. They get the plugin version of the
next push.

- Comic mode for picture-only EPUB, MOBI, AZW3 and FB2: no clock, no status
  line, no margins; each picture fills the screen and one tap turns one comic
  page. Found by looking at 10 pages spread through the book (once per book);
  Font panel › COMIC MODE: Auto / On / Off
- Comic mode: pictures grow to fill the page (keeping their shape), and blank
  pages left behind a picture are passed over in the direction you are reading
- Settings › Device: *Storage* row, "2.3 GB free of 4 GB" with a used / free bar
- Home: *Sync books* link next to ALL BOOKS reads the documents folder again
  (books copied over SSH or USB while Home is open) and says how many are new;
  the list stays where it was scrolled

## 0.1.44 – updates from the device, battery warnings

**Updates over Wi-Fi**
- When a newer version is on GitHub, a dot appears on Home's Settings button and
  Settings shows *Update available*. *Update* downloads it in the background,
  checks it, installs it and restarts KOReader; if anything fails, the old
  version stays. If a book is open when it finishes, it installs on the way Home
- Settings › Device: *Version* row with a *Check update* button
- Checks only when Wi-Fi is already on and Home or Settings opens (at most once
  an hour from Home), in the background: no screen waits on the network
- Two channels, set by how the plugin was built: official releases (Stable) and
  test builds from the `dev` branch (Dev)

**Reading**
- The % of the book read at the bottom right, opposite the time left
- Tap the bottom strip to switch time left in book / in chapter / nothing; it no
  longer turns the page
- Contents: every chapter of long books is listed (rows drawn as they scroll into
  view), titles wrap to two lines, the chapter being read opens two thirds of
  the way down, swipe up from the bottom edge goes Home

**Gestures and look**
- Swipe up for Home and pull down for the quick panel only from a thin strip at
  the edge and after a 150 px pull, everywhere (pages, Home, while reading, with
  the reading menu open): scrolling a list no longer jumps Home
- The top grabber is a blunt "V"; the bottom bar stays straight
- Long-press the clock strip for a screenshot on every page

**Battery**
- At 20 % a snackbar "Battery low · 20%"; at 5 % a popup that stays until *OK*
  is tapped (plugging in closes it). Once per discharge, never while charging

**Fixes**
- *‹ Back* on Contents (and any scrolling page) could also tap the row half
  hidden under the header, so the book jumped to an earlier page
- "Time left in chapter" didn't show in a book's last chapter; books without
  chapters skip that choice

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
