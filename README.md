# catchos-fixes-Lenovo-L14-G2

**English** | [Polski](README.pl.md)

Fixes for **CachyOS** on a **ThinkPad L14 Gen 2a (AMD, type 20X6)** with a
**Qualcomm FastConnect 7800 (WCN785x, ath12k driver)** WiFi card.

> **WiFi fixes (`ath12k-ccfix`, `wifi-fast-resume`) are only for the Qualcomm Wi-Fi 7 card
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
| `touchpad-intertouch` | The Synaptics touchpad runs in the old PS/2 mode and wakes up slowly | ~0.92 s | ~0.62 s |
| `ryzen-power` | Lenovo caps the Ryzen 7 PRO 5850U at 25 W under sustained load (temperature only ~70 °C) | 2.92 GHz all-core | **3.12 GHz (+7%)**, 30 W |
| `lte-modem` | The Quectel EM120R-GL LTE modem isn't visible (ModemManager off, FCC lock) and reports `sim-missing` with a SIM inserted | no LTE | LTE connects on its own |
| `easyeffects-l14` | Speakers sound flat and tinny (no Dolby tuning from Windows) and distort when turned up | limiter cuts more than 6 dB 13% of the time | **0%**, Windows curve within ±0.17 dB; + mic preset (RNNoise, clarity, -18.9 dBFS) |
| `mic-l14` | Built-in microphone distorts above ~25%: the slider adds up to +60 dB of hardware gain (Capture +30 dB, Internal Mic Boost +30 dB) | 64% of samples clipped at 100% | **0%** at 100% (100% = the old 25%) |
| `audio-nosuspend` | Short "blep" when starting or seeking a video: the sound card pauses for a split second, then replays leftover old audio from its own buffer (EasyEffects makes it louder) | blep on 3 of 6 starts/seeks | rarer |

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

### Microphone preset (`L14-mikrofon`)

The same script also installs the **input** preset `L14-mikrofon` (EasyEffects → **Input** tab → **Presets**).
Install the `mic-l14` fix first, so the microphone doesn't distort before EasyEffects.

Chain: Filter 90 Hz → RNNoise → Equalizer → Compressor → Limiter.
- **Filter 90 Hz:** removes the fan/chassis rumble below 60 Hz (as loud as the voice there).
- **RNNoise:** noise reduction (constant hiss from the mic preamp).
- **Equalizer:** -3 dB below 220 Hz (less "boxy"), **+6 dB at 1.6 kHz** (the laptop mic was ~10 dB short
  on speech clarity there), -2 dB at 7 kHz (hiss, sibilance), low-pass 12 kHz.
- **Compressor + Limiter:** evens out the voice; measured on recordings from this laptop: speech at
  **-18.9 dBFS** (good level for calls), peaks -1 dBFS, limiter active 0.6% of the time.

Mic slider in the system at **100%** (with `mic-l14` that's a clean level).
Set the voice loudness **only** with **Compressor → Makeup** (default +13 dB).

| Problem | What to change |
|---|---|
| Others hear you too quietly | Compressor → Makeup **+15** |
| Background noise between words | RNNoise → **Enable VAD** on |
| Voice sounds "robotic" | RNNoise → Wet **-6 dB** (mixes some of the original back in) |

If apps don't use the preset: EasyEffects → **Input** tab – the app should be listed there
(or turn on *Process all input streams* in the EasyEffects settings).

---

## Microphone without distortion (`mic-l14`)

The built-in microphone (Realtek ALC257) distorted above ~25%. The volume slider drives two hardware
amplifiers at once, and 100% meant **+60 dB** (Capture +30 dB + Internal Mic Boost +30 dB).
The fix keeps **Internal Mic Boost at 0 dB** and caps **Capture at +23.25 dB**, so
**100% on the slider = the old 25%** and the whole 0–100% range is clean.

The fix alone:
```
cd ~/catchos-fixes
```
```
sudo bash mic-l14/mic-l14-install.sh
```
The script writes an override of the ALSA card profile to your home directory
(`~/.config/alsa-card-profile/paths/`, system files stay untouched), restarts WirePlumber
and sets the microphone slider to 100%. At the end it shows the mixer state – it should be
**Capture 54 [23.25dB]** and **Internal Mic Boost 0 [0.00dB]**.

Measured (same voice, same distance):

| Slider | Hardware gain before → after | Clipped samples before → after |
|---|---|---|
| 50% | +40 dB → +4.5 dB | 11% → 0% |
| 100% | +60 dB → +23.25 dB | 64% → **0%** (peak -10 dBFS) |

For a headset plugged into the jack only **Mic Boost** is kept at 0 dB (Capture isn't capped).

---

## No "blep" when seeking (`audio-nosuspend`)

When nothing plays – even for a split second while seeking a YouTube video – PipeWire pauses the built-in
sound card (and suspends it after 5 s), and `snd_hda_intel` powers the Realtek codec down. On resume the card
replays leftover old audio from its own buffer, heard as a short "blep"; EasyEffects (limiter +12.5 dB) makes it louder.
It isn't in any PipeWire recording (checked before and after EasyEffects) and it isn't an xrun (ERR counter unchanged).

The fix alone:
```
cd ~/catchos-fixes
```
```
sudo bash audio-nosuspend/audio-nosuspend-install.sh
```
- WirePlumber (`~/.config/wireplumber/wireplumber.conf.d/51-audio-nosuspend.conf`): the built-in output
  `alsa_output.pci-0000_07_00.6.*` gets `node.pause-on-idle = false` and `session.suspend-timeout-seconds = 0` –
  it plays silence instead of pausing. HDMI and Bluetooth aren't affected.
- `snd_hda_intel power_save=0` (`/etc/modprobe.d/audio-nosuspend.conf`; also in TLP if it's installed).

At the end the script shows `power_save: 0`, `session.suspend-timeout-seconds = 0` and `node.pause-on-idle = false`.
Cost: about 0.1–0.3 W more.

---

## Power limit 30 W (`ryzen-power`)

Raises the CPU power limit (PPT SLOW) from Lenovo's 25 W to **30 W** – the maximum this laptop accepts
(STAPM is hard-capped at 30 W; 35 W is cut back to 30 immediately). Measured with all 16 threads loaded:
2.92 → 3.12 GHz (**+7%**), ~85 °C after 3 minutes, fan ~4150 instead of ~3100 rpm. CPU and GPU share one
power budget, so the iGPU gains a bit too. In normal work (browser, editor) there's no difference.

Active **only on AC and in the "Performance" power profile**; on battery or in other profiles Lenovo's
limits apply. Checked at boot, after resume and every 20 s (Lenovo may restore its limits).
Installs `ryzenadj` (built from github.com/FlyGoat/RyzenAdj) if it's missing.

Check:
```
sudo ryzenadj -i 2>/dev/null | grep -E 'STAPM LIMIT|PPT LIMIT (FAST|SLOW)'
```
```
journalctl -t ryzen-power
```
Values (W, °C) are at the top of `/usr/local/sbin/ryzen-power-apply`.

## LTE modem (`lte-modem`)

Only for the **Quectel EM120R-GL** LTE modem (PCI `1eac:1001`); without it the script does nothing.
`install-all.sh` sets it up with the APN `a2mobile.pl`. With a different SIM/operator, pass your APN:
```
sudo bash lte-modem/lte-modem-install.sh internet
```
The script enables ModemManager, turns on the FCC unlock, sets SIM slot 1 and disables SIM-presence
detection in the modem (without that the modem reports `sim-missing` even with a SIM inserted), and creates
the NetworkManager connection **LTE** (IPv4, connects automatically; WiFi has priority).

Check:
```
mmcli -m any | grep -E 'state:|signal quality|operator name'
```
`connected` + operator name = works. Use `-m any`, not `-m 0` – after every sleep the modem gets a new number.

> Don't know your APN? Connect once and read what the network assigned:
> `sudo systemctl stop ModemManager`, then
> `sudo bash -c 'exec 3<>/dev/wwan0at0; printf "AT+CGCONTRDP=1\r" >&3; timeout 3 cat <&3'`
> (the APN is the third field), then `sudo systemctl start ModemManager`.

## What about a new kernel?

Nothing to do:

- **iommu-fix** – the parameter lives in `/etc/default/limine`, and Limine adds it to every new kernel.
- **ath12k-ccfix** – a pacman hook (`/etc/pacman.d/hooks/90-ath12k-ccfix.hook`) runs after every
  `linux-cachyos-headers` update, downloads the new kernel sources, applies the patch and builds the driver.
  Kernel updates therefore take a few minutes longer and **need internet**.
  If the build fails (e.g. the driver code changed), the original driver is used automatically –
  WiFi works, it just reconnects more slowly after resume (~8 s).
- **wifi-fast-resume** – a plain script, it doesn't depend on the kernel.
- **touchpad-intertouch** – a module option (`/etc/modprobe.d/psmouse-intertouch.conf`), doesn't depend on the kernel.
- **ryzen-power** – a systemd service + timer, doesn't depend on the kernel.
- **lte-modem** – settings live in ModemManager, NetworkManager and the modem itself, they don't depend on the kernel.

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
  the last known country right away via `ath12k_wmi_send_set_current_country_cmd()` –
  the same as in ath11k (commit `7f0343b7b871`).
  The last real country is cached separately (from the 802.11d result), because when NetworkManager
  disconnects before sleep, cfg80211 resets the regdomain and `ar->alpha2` becomes `00`.
- **wifi-fast-resume:** after resume it waits for the country, aborts the full scan and has wpa_supplicant
  scan only the last used channel, so NetworkManager connects right away.
- **touchpad-intertouch:** `psmouse.synaptics_intertouch=1` – the touchpad goes over SMBus (RMI4) instead of PS/2;
  only the TrackPoint stays on PS/2 (`serio_resume` ~0.6 s).
- **ryzen-power:** Lenovo "performance" profile sets STAPM 30 W, PPT FAST 30 W, PPT SLOW 25 W, Tctl 100 °C,
  StapmTimeConst 1 s. Under full load the CPU sits at PPT SLOW = 25.0 W at ~70 °C, i.e. power-limited.
  `ryzenadj` sets SLOW 30 / FAST 35 / Tctl 95; STAPM above 30 W and `--stapm-time` are rejected by the SMU.
  Going back to stock = briefly switching `platform_profile`, which makes the firmware re-apply its limits.
- **lte-modem:** the modem has two SIM slots and SIM-presence detection enabled by default
  (`AT+QSIMDET: 1,1`); in this laptop the detect pin reads "no card", so the SIM is never powered
  (`+CPIN: ERROR 10`). `AT+QUIMSLOT=1` + `AT+QSIMDET=0,0` are stored in the modem's NV memory.
  `AT+CEER: Requested service option not subscribed` = wrong APN – a2mobile needs `a2mobile.pl`.
- **mic-l14:** the ACP path `analog-input-internal-mic.conf` merges `Capture` (0–63, -17.25…+30 dB) and
  `Internal Mic Boost` (0–3, +10 dB per step) into one slider, so 100% = +60 dB. The override sets
  `volume = zero` for `Internal Mic Boost` / `Int Mic Boost` and `volume-limit = 54` (+23.25 dB) for `Capture`;
  in `analog-input-mic.conf` only `Mic Boost` gets `volume = zero`. PipeWire reads overrides from
  `~/.config/alsa-card-profile/paths/` before `/usr/share/alsa-card-profile/mixer/paths/`.
- **audio-nosuspend:** recorded the browser output (`easyeffects_sink` monitor) and the card output
  (`alsa_output…` monitor) while seeking: both clean, EasyEffects adds 33 ms latency and a ~25 ms decay, no stale audio.
  `pw-top` showed no new xruns, but the output in state `I` (idle) and `easyeffects_sink` in `S` between plays –
  the stale audio comes from the ALSA ring buffer when the paused PCM restarts.
