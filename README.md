# Discord DPI for Windows

[English](#english) · [Türkçe](#türkçe)

Windows counterpart of [rudyatkinson/discord-macos-dpi](https://github.com/rudyatkinson/discord-macos-dpi), built on [ByeDPI](https://github.com/hufrea/byedpi).

---

## English

A small installer that routes **only Discord's traffic** through a local DPI-bypass proxy. It is not a VPN: it does not slow down your internet and does not touch your browser or other apps.

### Install

Open PowerShell (no admin needed) and run:

```powershell
irm https://raw.githubusercontent.com/rudyatkinson/discord-windows-dpi/main/install.ps1 | iex
```

Takes about a minute, asks for no password, downloads Discord if it is not installed. **To update, run the same line again.**

The installer follows your Windows language. To force one: `$env:DISCORD_DPI_LANG = 'en'` (or `'tr'`) before the command.

### How it works

- **Local proxy.** [ByeDPI](https://github.com/hufrea/byedpi) (`ciadpi.exe`) listens only on `127.0.0.1:8881`. System proxy settings are not changed.
- **Launch flag.** Only a Discord started with `--proxy-server=socks4://127.0.0.1:8881` uses the proxy. Nothing in Discord's files is patched.
- **DNS.** ISPs that block Discord usually also poison DNS (every Discord name resolves to the block server). The service resolves the Discord zones over DNS-over-HTTPS (Cloudflare, then Google) and passes the real IPs to Discord with `--host-resolver-rules`. Its own connectivity probes use the same IPs.
- **Watchdog task.** A per-user Scheduled Task named `DiscordDPI` starts at logon and
  - keeps the proxy running;
  - relaunches Discord through the proxy if it was started without it (Start Menu, "open at login", or a restart after an update);
  - tests the connection every minute while Discord is open, and immediately on network changes;
  - if Discord becomes unreachable, tries the bypass strategies in order and switches to one that works.
- **No admin rights.** Everything lives in your user profile.

### Installed files

| Path | Purpose |
|---|---|
| `%LOCALAPPDATA%\DiscordDPI\` | `bin\ciadpi.exe`, the `discord-dpi.ps1` service script, the selected `strategy`, `VERSION` |
| `%LOCALAPPDATA%\DiscordDPI\logs\` | `watch.log` (service), `ciadpi.log` / `ciadpi.err.log` (proxy) |
| Scheduled Task `DiscordDPI` | background service (logon trigger, current user only) |
| Start Menu → `Discord DPI` | Status, Report a problem, Repair, Uninstall |

### Something is not working?

Start Menu → **Discord DPI → Report a problem**. It writes `DiscordDPI-diagnostics-….zip` to your Desktop. Its `summary.txt` starts with a one-line result and what to do:

- **No internet, or a sign-in page is required.** Not an installer issue; resolves once you are online.
- **Broken install, or the task is not running.** Re-run the install command.
- **Port 8881 is used by another program.** Quit the named program, then Repair.
- **Selected strategy fails, another works.** Use Repair (the service also switches within 5 minutes).
- **No strategy works.** ByeDPI is not enough for this network; a VPN or WARP is needed.
- **Connection looks fine.** The problem is elsewhere (voice channels, for example).

The zip contains the ISP name, DNS answers, VPN-like adapters, per-strategy test results (`000` = blocked) and the last log lines. It contains **no Discord account data and no public IP address.**

**Repair** and **Uninstall** are in the same Start Menu folder. Command-line equivalents:

```powershell
powershell -File "$env:LOCALAPPDATA\DiscordDPI\discord-dpi.ps1" status
powershell -File "$env:LOCALAPPDATA\DiscordDPI\discord-dpi.ps1" diagnose   # builds the zip, prints its path
powershell -File "$env:LOCALAPPDATA\DiscordDPI\discord-dpi.ps1" repair
powershell -File "$env:LOCALAPPDATA\DiscordDPI\discord-dpi.ps1" uninstall
```

Uninstall removes everything except Discord itself.

### Limitations

- **Voice channels** use UDP, which does not go through the proxy. Verified working on Türk Telekom (the voice signalling WebSocket is proxied, the UDP media is not blocked there). On a network that blocks UDP they will not work; this tool does not fix UDP blocking.
- **Discord's own updater** does not use Chromium, so it sees neither the proxy nor the DNS rules and would retry on the "Discord Updater" splash forever on a blocked network. While installed, the service sets `DESKTOP_TTI_UPDATE_CHECK_DEADLINE_MS` (15 s) in Discord's `settings.json`, which makes Discord give up on the update check and start the installed version (restored on uninstall). Discord starts about 15 s slower and will not auto-update while blocked; install new versions manually from discord.com when needed.
- **"Open Discord on startup"** launches Discord without the proxy at logon; the watchdog closes it and relaunches it through the proxy within a few seconds. You will see Discord open twice. Turn the setting off in Discord if that bothers you.
- **Windows Defender / SmartScreen** may flag `ciadpi.exe` (common for DPI tools). Adding an exclusion needs admin rights, so the installer does not do it. If the proxy never starts, check Windows Security → Protection history.
- **Windows on ARM** has no native ByeDPI build; the x64 build runs under emulation and is untested.
- Only the official Discord client is handled. Vesktop and other clients are out of scope.
- `--fake` based strategies can be unstable on Windows (per the ByeDPI README); they are at the end of the list.

### Adding strategies

Strategies are ByeDPI argument groups, tried in order. They live in the `$Script:Strategies` list in `discord-dpi.ps1`. Add a line, re-run the installer (or copy the file over `%LOCALAPPDATA%\DiscordDPI\discord-dpi.ps1`) and run Repair.

### Credits

- [rudyatkinson/discord-macos-dpi](https://github.com/rudyatkinson/discord-macos-dpi) for the design this mirrors.
- [hufrea/byedpi](https://github.com/hufrea/byedpi) for the proxy.

---

## Türkçe

**Sadece Discord trafiğini** yerel bir DPI-bypass proxy'sinden geçiren küçük bir kurulumcu. VPN değildir: internetinizi yavaşlatmaz, tarayıcınıza ve diğer uygulamalara dokunmaz.

### Kurulum

PowerShell açın (yönetici gerekmez) ve çalıştırın:

```powershell
irm https://raw.githubusercontent.com/rudyatkinson/discord-windows-dpi/main/install.ps1 | iex
```

Yaklaşık bir dakika sürer, şifre istemez, Discord kurulu değilse indirir. **Güncellemek için aynı satırı tekrar çalıştırın.**

Kurulumcu Windows dilinizi izler. Zorlamak için komuttan önce: `$env:DISCORD_DPI_LANG = 'tr'` (veya `'en'`).

### Nasıl çalışır

- **Yerel proxy.** [ByeDPI](https://github.com/hufrea/byedpi) (`ciadpi.exe`) sadece `127.0.0.1:8881` adresini dinler. Sistem proxy ayarları değişmez.
- **Başlatma bayrağı.** Sadece `--proxy-server=socks4://127.0.0.1:8881` ile başlatılan Discord proxy'yi kullanır. Discord'un dosyalarına dokunulmaz.
- **DNS.** Discord'u engelleyen İSS'ler genelde DNS'i de zehirler (her Discord adı engel sunucusuna çözülür). Servis, Discord bölgelerini DNS-over-HTTPS (önce Cloudflare, sonra Google) ile çözer ve gerçek IP'leri `--host-resolver-rules` ile Discord'a verir. Kendi bağlantı testleri de aynı IP'leri kullanır.
- **Watchdog görevi.** `DiscordDPI` adlı kullanıcı seviyesinde bir Zamanlanmış Görev oturum açılışında başlar ve
  - proxy'yi ayakta tutar;
  - proxy'siz açılan Discord'u (Başlat Menüsü, "açılışta başlat" veya güncelleme sonrası yeniden başlatma) proxy üzerinden yeniden açar;
  - Discord açıkken her dakika, ağ değişiminde ise anında bağlantıyı test eder;
  - Discord erişilemez olursa bypass stratejilerini sırayla dener ve çalışana geçer.
- **Yönetici hakkı gerekmez.** Her şey kullanıcı profilinizde durur.

### Kurulan dosyalar

| Yol | Amaç |
|---|---|
| `%LOCALAPPDATA%\DiscordDPI\` | `bin\ciadpi.exe`, `discord-dpi.ps1` servis scripti, seçili `strategy`, `VERSION` |
| `%LOCALAPPDATA%\DiscordDPI\logs\` | `watch.log` (servis), `ciadpi.log` / `ciadpi.err.log` (proxy) |
| Zamanlanmış Görev `DiscordDPI` | arka plan servisi (oturum açılışı tetikleyicisi, sadece mevcut kullanıcı) |
| Başlat Menüsü → `Discord DPI` | Durum, Sorun bildir, Onar, Kaldır |

### Bir şey çalışmıyor mu?

Başlat Menüsü → **Discord DPI → Sorun bildir**. Masaüstüne `DiscordDPI-diagnostics-….zip` yazar. İçindeki `summary.txt` tek satırlık bir sonuç ve ne yapmanız gerektiğiyle başlar:

- **İnternet yok veya giriş sayfası gerekiyor.** Kurulum sorunu değil; çevrimiçi olunca düzelir.
- **Kurulum bozuk veya görev çalışmıyor.** Kurulum komutunu tekrar çalıştırın.
- **8881 portunu başka program kullanıyor.** Adı yazan programı kapatıp Onar'ı çalıştırın.
- **Seçili strateji çalışmıyor, başkası çalışıyor.** Onar'ı kullanın (servis de 5 dakika içinde kendisi değiştirir).
- **Hiçbir strateji çalışmıyor.** ByeDPI bu ağda yetmiyor; VPN veya WARP gerekiyor.
- **Bağlantı iyi görünüyor.** Sorun başka yerde (örneğin ses kanalları).

Zip; İSS adını, DNS cevaplarını, VPN benzeri adaptörleri, strateji başına test sonuçlarını (`000` = engelli) ve son log satırlarını içerir. **Discord hesap verisi ve açık IP adresi içermez.**

**Onar** ve **Kaldır** aynı Başlat Menüsü klasöründe. Komut satırı karşılıkları:

```powershell
powershell -File "$env:LOCALAPPDATA\DiscordDPI\discord-dpi.ps1" status
powershell -File "$env:LOCALAPPDATA\DiscordDPI\discord-dpi.ps1" diagnose   # zip'i oluşturur, yolunu yazar
powershell -File "$env:LOCALAPPDATA\DiscordDPI\discord-dpi.ps1" repair
powershell -File "$env:LOCALAPPDATA\DiscordDPI\discord-dpi.ps1" uninstall
```

Kaldırma, Discord'un kendisi hariç her şeyi siler.

### Sınırlamalar

- **Ses kanalları** UDP kullanır, proxy'den geçmez. Türk Telekom'da çalıştığı doğrulandı (ses sinyalleşme WebSocket'i proxy'den geçer, UDP medya orada engelli değil). UDP'yi engelleyen bir ağda çalışmaz; bu araç UDP engelini çözmez.
- **Discord'un kendi güncelleyicisi** Chromium kullanmaz; proxy'yi de DNS kurallarını da görmez ve engelli ağda "Discord Updater" ekranında sonsuza kadar yeniden dener. Araç kuruluyken Discord'un `settings.json` dosyasına `DESKTOP_TTI_UPDATE_CHECK_DEADLINE_MS` (15 sn) yazılır; Discord bu süre sonunda güncelleme kontrolünden vazgeçip kurulu sürümü başlatır (kaldırmada geri alınır). Discord yaklaşık 15 sn geç açılır ve engelliyken otomatik güncellenmez; gerektiğinde yeni sürümü discord.com'dan elle kurun.
- **"Discord'u açılışta başlat"** ayarı oturum açılışında Discord'u proxy'siz başlatır; watchdog birkaç saniye içinde kapatıp proxy üzerinden yeniden açar. Discord'un iki kez açıldığını görürsünüz. Rahatsız ediyorsa ayarı Discord'dan kapatın.
- **Windows Defender / SmartScreen** `ciadpi.exe`'yi işaretleyebilir (DPI araçlarında yaygın). Dışlama eklemek yönetici hakkı ister, bu yüzden kurulumcu bunu yapmaz. Proxy hiç başlamıyorsa Windows Güvenliği → Koruma geçmişine bakın.
- **ARM Windows** için ByeDPI'nin yerel build'i yok; x64 build emülasyonla çalışır, test edilmedi.
- Sadece resmi Discord istemcisi ele alınır. Vesktop ve diğer istemciler kapsam dışıdır.
- `--fake` tabanlı stratejiler Windows'ta kararsız olabilir (ByeDPI README); listenin sonundadır.

### Strateji ekleme

Stratejiler sırayla denenen ByeDPI argüman gruplarıdır. `discord-dpi.ps1` içindeki `$Script:Strategies` listesinde durur. Bir satır ekleyin, kurulumcuyu yeniden çalıştırın (veya dosyayı `%LOCALAPPDATA%\DiscordDPI\discord-dpi.ps1` üzerine kopyalayın) ve Onar'ı çalıştırın.

### Teşekkür

- Tasarımı aynalanan [rudyatkinson/discord-macos-dpi](https://github.com/rudyatkinson/discord-macos-dpi).
- Proxy için [hufrea/byedpi](https://github.com/hufrea/byedpi).

## License

MIT
