# Install, update, remove Minimal Home

## Install over USB

1. Download `minimalhome-x.y.z.zip` from the [Releases](../../../releases) page.
2. Connect the device by USB.
3. Unzip into the `koreader/plugins/` folder on the device, so you get
   `koreader/plugins/minimalhome.koplugin/` (on a Kindle:
   `/mnt/us/koreader/plugins/minimalhome.koplugin/`).
4. Eject, then restart KOReader (KOReader menu → *Exit* → *Restart KOReader*).

Minimal Home opens instead of KOReader's file browser. Books come from the
device's documents folder (KOReader's home folder).

## Update over Wi-Fi (SSH)

1. On the device: quick panel (swipe down) → *All Settings* → *SSH access* on.
   Settings shows the address and port.
2. On your computer, from the folder with the new zip:

```sh
unzip -o minimalhome-x.y.z.zip -d /tmp/mh
tar -C /tmp/mh -czf - minimalhome.koplugin | \
  ssh -p 2222 root@<device-ip> \
  "cd /mnt/us/koreader/plugins && rm -rf minimalhome.koplugin && tar -xzf -"
```

3. Restart KOReader. *Settings* shows the installed version at the bottom.

Tar over SSH is used instead of `scp`, which hangs against KOReader's SSH
server on some setups.

From a clone of this repository, `tools/deploy.sh <device-ip>` does the same.

## Remove

Delete the `koreader/plugins/minimalhome.koplugin` folder and restart KOReader.
KOReader's own file browser and reading screen come back. Your books, reading
progress and highlights are KOReader's and are not touched.

Minimal Home changes a few KOReader defaults for new books (margins, status bar
items, line spacing). Books keep these after removal; change them in KOReader's
own menus if you like.
