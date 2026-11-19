# Troubleshooting

**KOReader closes and the Kindle home screen appears.** KOReader crashed. Copy
`koreader/crash.log` from the device; the lines with `MinimalHome` show where.
Remove the plugin folder to get KOReader back while you look.

**Home shows "No books yet".** Books are read from KOReader's home folder (on a
Kindle, `/mnt/us/documents`). Copy EPUB, PDF, FB2, MOBI… files there.

**A book shows KINDLE ONLY.** It was bought from the Kindle Store and is
DRM-protected: open it in the Kindle's own reader.

**No covers.** Covers come from KOReader's *Cover browser* plugin; keep it enabled.
New books get covers the first time Home opens after they're added.

**The light or Wi-Fi didn't come back after waking.** Toggle it in the quick
panel. If it keeps happening, look in `crash.log` for `frontlight`, `Suspend`
and `Resume`.

**I need KOReader's own menu.** Quick panel → *All Settings* → *All KOReader settings*.

**Screenshots**: hold the status bar (Home or a book). Files go to
`koreader/screenshots/`.

**Still stuck?** Ask in [Discussions](https://github.com/truonglong88/Minimal-Home-Interface-for-Kindle/discussions) (no promise of a reply).
