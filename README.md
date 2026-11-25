# catchos-fixes

Poprawki dla **CachyOS** na **ThinkPad L14 Gen 2a (AMD, typ 20X6)** z kartą WiFi
**Qualcomm FastConnect 7800 (WCN785x, sterownik ath12k)**.

| Poprawka | Problem | Przed | Po |
|---|---|---|---|
| `iommu-fix` | Wybudzanie z uśpienia blokuje się na ~10 s (błąd BIOS-u Lenovo przy NVMe + IOMMU) | ~12 s | ~1,8 s |
| `ath12k-ccfix` | Po wybudzeniu firmware WiFi zapomina kraj i przez ~7 s go odgaduje | 16 s | — |
| `wifi-fast-resume` | NetworkManager długo skanuje 6 GHz zamiast od razu się połączyć | — | razem z ath12k-ccfix: **~1,7 s** do WiFi |

---

## Instalacja po świeżej instalacji systemu (od A do Z)

Wszystkie komendy działają w fish.

**1. Zainstaluj git i GitHub CLI:**
```
sudo pacman -S --needed git github-cli
```

**2. Zaloguj się do GitHuba** (repo jest prywatne):
```
gh auth login
```
Wybierz po kolei: `GitHub.com` → `HTTPS` → `Yes` → `Login with a web browser`.
Skopiuj pokazany kod, wciśnij Enter, w przeglądarce wklej kod i zatwierdź.

**3. Pobierz repo:**
```
gh repo clone EstVsq/catchos-fixes ~/catchos-fixes
```

**4. Zainstaluj wszystko naraz:**
```
cd ~/catchos-fixes
```
```
sudo bash install-all.sh
```
Potrwa kilka minut (pobiera źródła kernela ok. 150 MB i kompiluje sterownik WiFi).

**5. Restart:**
```
reboot
```

**6. Test:** zamknij klapę, odczekaj 20 s, otwórz i po połączeniu WiFi:
```
journalctl -k -b | grep ccfix
```
```
journalctl -b -t wifi-fast-resume --no-pager | tail -3
```
Powinno być `restored country code PL after resume` i `WiFi polaczone po ~1700 ms`.

> Bez `gh`: na github.com wejdź w repo → zielony przycisk **Code** → **Download ZIP**,
> rozpakuj do `~/catchos-fixes` i od kroku 4 tak samo.

---

## Co z nowym kernelem?

Nic nie trzeba robić:

- **iommu-fix** – parametr siedzi w `/etc/default/limine`, a Limine dodaje go do każdego nowego kernela.
- **ath12k-ccfix** – hook pacmana (`/etc/pacman.d/hooks/90-ath12k-ccfix.hook`) po każdej aktualizacji
  `linux-cachyos-headers` sam pobiera źródła nowego kernela, nakłada poprawkę i buduje sterownik.
  Aktualizacja kernela trwa przez to kilka minut dłużej i **wymaga internetu**.
  Jeśli budowa się nie uda (np. kod sterownika się zmienił), automatycznie działa oryginalny
  sterownik – WiFi działa, tylko po wybudzeniu łączy się wolniej (~8 s).
- **wifi-fast-resume** – zwykły skrypt, nie zależy od kernela.

Sprawdzenie, który sterownik WiFi działa:
```
modinfo -n ath12k ath12k_wifi7
```
Ścieżka z `updates/ath12k-ccfix` = poprawiony. Z `kernel/drivers/...` = oryginalny.

Ręczne przebudowanie (np. gdy aktualizacja szła bez internetu):
```
sudo /usr/local/sbin/ath12k-ccfix-build
```
Potem restart albo przeładowanie WiFi:
```
sudo modprobe -r ath12k_wifi7; sudo modprobe ath12k_wifi7
```

Kernel LTS (`linux-cachyos-lts`) nie jest objęty poprawką sterownika – działa na oryginalnym.

---

## Usuwanie

Wszystko naraz:
```
sudo bash install-all.sh usun
```
Albo pojedynczo, np.:
```
sudo bash ath12k-ccfix/ath12k-ccfix-install.sh usun
```

---

## Szczegóły techniczne

- **iommu-fix:** BIOS Lenovo ma procedurę SMI uruchamianą przy przejściu NVMe z D3 do D0 przy
  wybudzaniu z s2idle; z włączonym tłumaczeniem IOMMU wstrzymuje ona wybudzanie na ~10,25 s
  (nvme, xhci, renesas, hda blokują się w `pci_pm_resume_noirq`). Kernel ma obejście w `amd_pmc`
  (lista `fwbug_list`), ale dopasowuje model po typie maszyny i nie obejmuje `20X6`.
  Docelowo: zgłosić dopisanie `20X6` do `drivers/platform/x86/amd/pmc/pmc-quirks.c`.
- **ath12k-ccfix:** po wybudzeniu firmware WCN785x jest uruchamiane od nowa z regdomain WORLD
  i odzyskuje kraj dopiero po skanie 802.11d (~7 s). Poprawka w `ath12k_core_resume()` wysyła
  od razu ostatni znany kraj (`ar->alpha2`) przez `ath12k_wmi_send_set_current_country_cmd()` –
  tak samo jak w ath11k (commit `7f0343b7b871`).
- **wifi-fast-resume:** po wybudzeniu czeka na kraj, przerywa pełny skan i zleca wpa_supplicant
  skan tylko ostatnio używanego kanału, więc NetworkManager łączy się od razu.
