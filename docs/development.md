# Development

```
minimalhome.koplugin/      the plugin (this folder is what users install)
  main.lua                 entry point: hooks into the file browser and the reader
  _meta.lua                name and version
  mh/theme.lua             design tokens: sizes scale from a 1264 px design width
  mh/device.lua            light, Wi-Fi, SSH, sleep timer, refresh… (KOReader APIs)
  mh/wifi.lua              Wi-Fi on/off, scan, join (for the Wi-Fi popup)
  mh/reader.lua            reading screen: style, status bar, touch zones
  mh/messages.lua          KOReader's messages and questions in our look
  mh/updater.lua           updates from GitHub releases (check, download, verify, install)
  mh/data/                 library, model (pure logic), search, prefs
  mh/ui/                   screens and widgets (home, search, settings, reader menu,
                           quick panel, keyboard, Wi-Fi popup, snackbar, confirm…)
  fonts/                   Literata and Inter (SIL Open Font License)
  screensavers/            screensaver pictures (see docs/images/NOTICE.md)
spec/                      tests (stubs for KOReader modules in spec/stubs)
tools/                     test, package, deploy, screensaver helper
```

## Tests

```sh
git clone --depth 1 https://github.com/koreader/koreader ../koreader
sh tools/test.sh ../koreader      # unit tests + smoke tests against KOReader's widgets
luacheck minimalhome.koplugin     # lint
```

Needs LuaJIT and luacheck. The smoke tests paint every screen with KOReader's real
layout widgets; they catch crashes, not looks. Always check on a device too.

## Package

```sh
sh tools/package.sh                              # raises the patch version, Dev channel
sh tools/package.sh --no-bump --channel stable   # same version, Stable (release workflow)
```

Writes `dist/minimalhome-x.y.z.zip` and `dist/latest.json` (version, file name,
size, SHA-256, channel), which the in-app updater reads. The zip carries
`build.lua` with its channel.

## Branches and update channels

- `dev`: every push runs `.github/workflows/dev.yml`, which replaces the `dev`
  pre-release with the new zip and `latest.json`. Devices running a Dev build
  offer it in Settings.
- `main`: official releases. Publishing a release runs `release.yml`, which
  attaches the zip (Stable channel) and `latest.json`. Devices running a Stable
  build offer the newest release.

## Release

Update `CHANGELOG.md`, commit, then tag: `git tag vX.Y.Z && git push --tags`.
GitHub Actions runs the tests, builds the zip and attaches it to a release.
