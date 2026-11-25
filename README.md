# catchos-fixes-Lenovo-L14-G2

**English** | [Polski](README.pl.md)

Fixes for **CachyOS** on a **ThinkPad L14 Gen 2a (AMD, type 20X6)** with a
**Qualcomm FastConnect 7800 (WCN785x, ath12k driver)** WiFi card.

> **WiFi fixes (`ath12k-ccfix`, `wifi-fast-resume`, `wifi-wowlan`) are only for the Qualcomm Wi-Fi 7 card
> WCN785x / FastConnect 7800** (e.g. Quectel NCM865 / QCNCM865, PCI ID `17cb:1107`), fitted in
> place of the factory WiFi card. With any other card they aren't needed – `install-all.sh`
> detects the card and skips them automatically. `iommu-fix` and `easyeffects-l14` work
> regardless of the WiFi card.
>
> Check which card you have:
> ```
> lspci -nn | grep -i network
> ```
> If the line contains `[17cb:1107]`, you have this card.

| Fix | Problem | Before | After |
|---|---|---|---|
| `iommu-fix` | Resume from sleep hangs for ~10 s (Lenovo BIOS bug with NVMe + IOMMU) | ~12 s | ~1.8 s |
| `ath12k-ccfix` | After resume the WiFi firmware forgets the country and takes ~7 s to work it out again | 16 s | — |
| `wifi-fast-resume` | NetworkManager spends a long time scanning 6 GHz instead of connecting right away | — | together with ath12k-ccfix: **~1.2 s** to WiFi |
| `wifi-wowlan` | In sleep the WiFi card is switched off completely, so on resume its firmware boots from scratch | ~0.76 s | ~0 s |
| `touchpad-intertouch` | The Synaptics touchpad runs in the old PS/2 mode and wakes up slowly | ~0.92 s | ~0.62 s |
| `easyeffects-l14` | Speakers sound flat and tinny (no Dolby tuning from Windows) and distort when turned up | limiter cuts more than 6 dB 13% of the time | **0%**, Windows curve within ±0.17 dB |

---

## Installing on a fresh system (A to Z)

All commands work in fish.

**1. Install git and GitHub CLI:**
```
sudo pacman -S --needed git github-cli
```

**2. Log in to GitHub** (the repo is private):
```
gh auth login
```
Choose in order: `GitHub.com` → `HTTPS` → `Yes` → `Login with a web browser`.
Copy the code shown, press Enter, paste the code in the browser and confirm.

**3. Download the repo:**
```
gh repo clone EstVsq/catchos-fixes-Lenovo-L14-G2 ~/catchos-fixes
```

**4. Install everything at once** (including the EasyEffects preset):
```
cd ~/catchos-fixes
```
```
sudo bash install-all.sh
```
Takes a few minutes (downloads ~150 MB of kernel sources and compiles the WiFi driver).

**5. Reboot:**
```
reboot
```

**6. Test:** close the lid, wait 20 s, open it and once WiFi is connected run:
```
journalctl -k -b | grep ccfix
```
```
journalctl -b -t wifi-fast-resume --no-pager | tail -3
```
You should see `restored country code PL after resume` and `WiFi polaczone po ~1700 ms`
("WiFi connected after ~1700 ms").

> Without `gh`: open the repo on github.com → green **Code** button → **Download ZIP**,
> unpack it to `~/catchos-fixes` and continue from step 4.

---

## EasyEffects preset for the speakers (`easyeffects-l14`)

The preset alone (without the other fixes):
```
cd ~/catchos-fixes
```
```
sudo bash easyeffects-l14/easyeffects-l14-install.sh
```
The script installs EasyEffects with its plugins (`lsp-plugins-lv2`, `calf`) and copies the
`L14-windows` preset to your home directory. If EasyEffects is running, it loads the preset
right away; if not, start EasyEffects and choose **Presets → L14-windows**.

Check in EasyEffects:
- **Equalizer:** 16 bands, mode **APO (DR)**
- **Multiband Compressor → band 0:** sidechain **Peak**, lookahead **5 ms**

Set the volume **only** with **Limiter → Input gain** (default +12.5 dB).

| Problem | What to change |
|---|---|
| Everything too quiet | Limiter → Input gain **+13.5** |
| Bass too weak | Multiband Compressor → band 0 → Threshold **-15** |
| Bass "rattles" | Multiband Compressor → band 0 → Threshold **-21** |

The preset is for the **built-in speakers** – with headphones choose another preset or turn the effects off.

Chain: Equalizer → Bass Enhancer → Filter 165 Hz → Stereo Tools → Multiband Compressor → Limiter.
- **Equalizer:** 16 bands fitted to the impulse response of the speakers from Windows (192 samples, 48 kHz);
  max. error 0.17 dB. Cuts only (peak 0 dB), so the equalizer can't distort on its own.
- **Multiband Compressor:** the bass band (< 300 Hz) works as a bass limiter (Peak, lookahead 5 ms),
  so the kick drum doesn't turn the whole music down in the limiter. Tuned on recordings of radio and YouTube.
- **Limiter:** only a safety net – on loud radio it cuts more than 6 dB 0% of the time (was 13%).

---

## What about a new kernel?

Nothing to do:

- **iommu-fix** – the parameter lives in `/etc/default/limine`, and Limine adds it to every new kernel.
- **ath12k-ccfix** – a pacman hook (`/etc/pacman.d/hooks/90-ath12k-ccfix.hook`) runs after every
  `linux-cachyos-headers` update, downloads the new kernel sources, applies the patch and builds the driver.
  Kernel updates therefore take a few minutes longer and **need internet**.
  If the build fails (e.g. the driver code changed), the original driver is used automatically –
  WiFi works, it just reconnects more slowly after resume (~8 s).
- **wifi-fast-resume** – a plain script, it doesn't depend on the kernel.
- **wifi-wowlan** – a udev rule (`/etc/udev/rules.d/90-wifi-wowlan.rules`), doesn't depend on the kernel.
- **touchpad-intertouch** – a module option (`/etc/modprobe.d/psmouse-intertouch.conf`), doesn't depend on the kernel.

Checking which WiFi driver is in use:
```
modinfo -n ath12k ath12k_wifi7
```
A path with `updates/ath12k-ccfix` = patched. With `kernel/drivers/...` = original.

Manual rebuild (e.g. when the update ran without internet):
```
sudo /usr/local/sbin/ath12k-ccfix-build
```
Then reboot or reload WiFi:
```
sudo modprobe -r ath12k_wifi7; sudo modprobe ath12k_wifi7
```

The LTS kernel (`linux-cachyos-lts`) isn't covered by the driver patch – it runs the original driver.

---

## Removing

Everything at once:
```
sudo bash install-all.sh usun
```
Or one at a time, e.g.:
```
sudo bash ath12k-ccfix/ath12k-ccfix-install.sh usun
```
(`usun` is Polish for "remove".)

---

## Technical details

- **iommu-fix:** the Lenovo BIOS has an SMI routine that runs when the NVMe goes from D3 to D0 during
  resume from s2idle; with IOMMU translation enabled it stalls resume for ~10.25 s
  (nvme, xhci, renesas, hda block in `pci_pm_resume_noirq`). The kernel has a workaround in `amd_pmc`
  (the `fwbug_list`), but it matches models by machine type and doesn't include `20X6`.
  Long term: request adding `20X6` to `drivers/platform/x86/amd/pmc/pmc-quirks.c`.
- **ath12k-ccfix:** after resume the WCN785x firmware restarts with the WORLD regdomain
  and only gets the country back after an 802.11d scan (~7 s). The patch in `ath12k_core_resume()` sends
  the last known country (`ar->alpha2`) right away via `ath12k_wmi_send_set_current_country_cmd()` –
  the same as in ath11k (commit `7f0343b7b871`).
- **wifi-fast-resume:** after resume it waits for the country, aborts the full scan and has wpa_supplicant
  scan only the last used channel, so NetworkManager connects right away.
- **wifi-wowlan:** with WoWLAN configured (trigger: magic packet) mac80211 suspends the card in WoW mode
  instead of stopping it, so ath12k doesn't power the chip down and skips the firmware boot on resume
  (`pci_pm_resume_early` 522 ms → ~0 ms). The laptop still reaches s0i3. NetworkManager disconnects
  before sleep anyway, so in practice the trigger never fires.
- **touchpad-intertouch:** `psmouse.synaptics_intertouch=1` – the touchpad goes over SMBus (RMI4) instead of PS/2;
  only the TrackPoint stays on PS/2 (`serio_resume` ~0.6 s).
