#Requires -Version 5.1
<#
  Discord DPI for Windows - installer

  Usage (PowerShell, no admin needed):
    irm https://raw.githubusercontent.com/bilal-arvis/discord-windows-dpi/main/install.ps1 | iex

  Re-run the same line to update. Set $env:DISCORD_DPI_LANG = 'tr' or 'en' to force the language.
  Windows counterpart of https://github.com/rudyatkinson/discord-macos-dpi
#>
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ---------------------------------------------------------------- constants

$Repo    = 'bilal-arvis/discord-windows-dpi'
$Branch  = 'main'
$RawBase = "https://raw.githubusercontent.com/$Repo/$Branch"
if ($env:DISCORD_DPI_SOURCE) { $RawBase = $env:DISCORD_DPI_SOURCE.TrimEnd('/') }   # testing: serve the repo locally

$Version   = '1.0.0'
$ByeTag    = 'v0.17.3'
$ByeZip    = 'byedpi-17.3-x86_64-w64.zip'
$ByeUrl    = "https://github.com/hufrea/byedpi/releases/download/$ByeTag/$ByeZip"
$ByeSha256 = '70D2C94147193CB915F9C6EB5144B8D404DACBCFA90BDA2383B6B211AFAFA456'

$Root       = Join-Path $env:LOCALAPPDATA 'DiscordDPI'
$BinDir     = Join-Path $Root 'bin'
$Bin        = Join-Path $BinDir 'ciadpi.exe'
$ScriptDest = Join-Path $Root 'discord-dpi.ps1'
$Tmp        = Join-Path $Root 'tmp'
$Curl       = Join-Path $env:SystemRoot 'System32\curl.exe'
$DiscordDir = Join-Path $env:LOCALAPPDATA 'Discord'
$TaskName   = 'DiscordDPI'
$PS51       = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Port       = 8881

# ---------------------------------------------------------------- language

$Lang = 'en'
if ($env:DISCORD_DPI_LANG -match '^(tr|en)$') { $Lang = $Matches[1] }
elseif ((Get-Culture).Name -like 'tr*') { $Lang = 'tr' }

$M = @{
    en = @{
        header        = 'Discord DPI for Windows v{0} - installer'
        intro         = 'Routes only Discord through a local DPI-bypass proxy. No admin rights, no system proxy change, no VPN.'
        need64        = 'A 64-bit Windows is required.'
        arm64         = 'Windows on ARM detected: the x64 ByeDPI build will run under emulation (untested).'
        nocurl        = 'curl.exe was not found in System32. Windows 10 1803 or newer is required.'
        discord_ok    = 'Discord found.'
        discord_dl    = 'Discord is not installed; downloading the official installer...'
        discord_inst  = 'Installing Discord (a Discord window will open; you can close it)...'
        discord_fail  = 'Discord could not be installed. Install it from https://discord.com/download and re-run this command.'
        stop_old      = 'Stopping the previous Discord DPI service...'
        bye_dl        = 'Downloading ByeDPI {0}...'
        bye_sha_bad   = 'ByeDPI download is corrupt (SHA256 mismatch). Aborting.'
        bye_ok        = 'ByeDPI verified and installed.'
        bye_run_fail  = 'ciadpi.exe does not start. Windows Defender may have blocked it; see the README.'
        script_local  = 'Using the local discord-dpi.ps1.'
        script_dl     = 'Downloading discord-dpi.ps1...'
        pick          = 'Testing bypass strategies (this takes up to a minute)...'
        pick_ok       = 'Working strategy: {0}'
        pick_none     = 'No strategy works on this network. Installed anyway, but ByeDPI is not enough here; a VPN or WARP is needed.'
        setup         = 'Registering the background task and Start Menu shortcuts...'
        starting      = 'Starting the service and relaunching Discord through the proxy...'
        verify_ok     = 'Discord is reachable through the proxy (HTTP {0}).'
        verify_bad    = 'Discord is not reachable through the proxy yet (HTTP {0}). The service keeps retrying; use "Discord DPI - Report a problem" in the Start Menu if it stays broken.'
        done          = 'Done. Discord DPI starts automatically at logon.'
        hint_menu     = 'Start Menu > Discord DPI: Status, Report a problem, Repair, Uninstall.'
        hint_cmd      = 'Command line: powershell -File "{0}" status | repair | diagnose | uninstall'
        hint_voice    = 'Note: voice channels use UDP and are not affected by this tool.'
    }
    tr = @{
        header        = 'Discord DPI for Windows v{0} - kurulum'
        intro         = 'Sadece Discord trafiğini yerel bir DPI-bypass proxy''sinden geçirir. Yönetici hakkı, sistem proxy''si ve VPN gerekmez.'
        need64        = '64-bit Windows gerekli.'
        arm64         = 'ARM Windows tespit edildi: x64 ByeDPI emülasyonla çalışacak (test edilmedi).'
        nocurl        = 'System32 içinde curl.exe bulunamadı. Windows 10 1803 veya daha yenisi gerekli.'
        discord_ok    = 'Discord bulundu.'
        discord_dl    = 'Discord kurulu değil; resmi kurulum dosyası indiriliyor...'
        discord_inst  = 'Discord kuruluyor (bir Discord penceresi açılacak; kapatabilirsiniz)...'
        discord_fail  = 'Discord kurulamadı. https://discord.com/download adresinden kurup bu komutu tekrar çalıştırın.'
        stop_old      = 'Önceki Discord DPI servisi durduruluyor...'
        bye_dl        = 'ByeDPI {0} indiriliyor...'
        bye_sha_bad   = 'ByeDPI indirmesi bozuk (SHA256 uyuşmuyor). İptal edildi.'
        bye_ok        = 'ByeDPI doğrulandı ve kuruldu.'
        bye_run_fail  = 'ciadpi.exe başlamıyor. Windows Defender engellemiş olabilir; README''ye bakın.'
        script_local  = 'Yerel discord-dpi.ps1 kullanılıyor.'
        script_dl     = 'discord-dpi.ps1 indiriliyor...'
        pick          = 'Bypass stratejileri deneniyor (bir dakika kadar sürebilir)...'
        pick_ok       = 'Çalışan strateji: {0}'
        pick_none     = 'Bu ağda hiçbir strateji çalışmıyor. Yine de kuruldu ama ByeDPI burada yetmiyor; VPN veya WARP gerekiyor.'
        setup         = 'Arka plan görevi ve Başlat Menüsü kısayolları kaydediliyor...'
        starting      = 'Servis başlatılıyor ve Discord proxy üzerinden yeniden açılıyor...'
        verify_ok     = 'Discord proxy üzerinden erişilebilir (HTTP {0}).'
        verify_bad    = 'Discord henüz proxy üzerinden erişilemiyor (HTTP {0}). Servis denemeye devam eder; düzelmezse Başlat Menüsü''nden "Discord DPI - Sorun bildir"i kullanın.'
        done          = 'Tamam. Discord DPI oturum açılışında otomatik başlar.'
        hint_menu     = 'Başlat Menüsü > Discord DPI: Durum, Sorun bildir, Onar, Kaldır.'
        hint_cmd      = 'Komut satırı: powershell -File "{0}" status | repair | diagnose | uninstall'
        hint_voice    = 'Not: ses kanalları UDP kullanır ve bu araçtan etkilenmez.'
    }
}
function Say([string]$key, [string]$color = 'Gray') {
    $s = $M[$Lang][$key]; if (-not $s) { $s = $M['en'][$key] }
    if ($args.Count -gt 0) { $s = $s -f $args }
    Write-Host $s -ForegroundColor $color
}
function Fail([string]$key) { Say $key 'Red'; exit 1 }
function Step([string]$key) { Write-Host ''; Write-Host "==> " -NoNewline -ForegroundColor Cyan; Say $key 'White' @args }

function Get-Download([string]$url, [string]$dest) {
    & $Curl -fL --retry 3 -m 300 -s -S -o $dest $url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $dest)) { throw "download failed: $url (curl exit $LASTEXITCODE)" }
}

function Test-PortOpen([int]$port) {
    $c = New-Object System.Net.Sockets.TcpClient
    try { $ar = $c.BeginConnect('127.0.0.1', $port, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(500, $false)) { $c.EndConnect($ar); return $true } } catch { } finally { $c.Close() }
    return $false
}

# ---------------------------------------------------------------- 0. header

Write-Host ''
Say 'header' 'Cyan' $Version
Say 'intro'

# ---------------------------------------------------------------- 1. checks

if (-not [Environment]::Is64BitOperatingSystem) { Fail 'need64' }
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { Say 'arm64' 'Yellow' }
if (-not (Test-Path $Curl)) { Fail 'nocurl' }

foreach ($d in @($Root, $BinDir, $Tmp, (Join-Path $Root 'logs'))) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

# ---------------------------------------------------------------- 2. discord

$UpdateExe = Join-Path $DiscordDir 'Update.exe'
if (Test-Path $UpdateExe) { Say 'discord_ok' 'Green' }
else {
    Step 'discord_dl'
    $setup = Join-Path $Tmp 'DiscordSetup.exe'
    Get-Download 'https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x64' $setup
    Say 'discord_inst'
    Start-Process -FilePath $setup -ArgumentList '-s' -Wait
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline -and -not (Test-Path $UpdateExe)) { Start-Sleep 2 }
    if (-not (Test-Path $UpdateExe)) { Fail 'discord_fail' }
    Say 'discord_ok' 'Green'
}

# ---------------------------------------------------------------- 3. stop previous install (so files can be replaced)

$oldTask = $null
try { $oldTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch { }
$oldWatch = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*discord-dpi.ps1*watch*' })
if ($oldTask -or $oldWatch.Count -or (Get-Process ciadpi -ErrorAction SilentlyContinue)) {
    Step 'stop_old'
    if ($oldTask) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }
    foreach ($w in $oldWatch) { Stop-Process -Id $w.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-Process ciadpi -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Root*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
}

# ---------------------------------------------------------------- 4. byedpi

Step 'bye_dl' $ByeTag
$zip = Join-Path $Tmp $ByeZip
Get-Download $ByeUrl $zip
$hash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
if ($hash -ne $ByeSha256) { Remove-Item $zip -Force -ErrorAction SilentlyContinue; Fail 'bye_sha_bad' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $entry = $archive.Entries | Where-Object { $_.Name -eq 'ciadpi.exe' } | Select-Object -First 1
    if (-not $entry) { throw 'ciadpi.exe missing from archive' }
    if (Test-Path $Bin) { Remove-Item $Bin -Force }
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $Bin, $true)
} finally { $archive.Dispose() }
Unblock-File -Path $Bin -ErrorAction SilentlyContinue
Remove-Item $zip -Force -ErrorAction SilentlyContinue

# sanity run: ciadpi prints its usage on -h
$help = & $Bin -h 2>&1 | Out-String
if (-not ($help -match '--ip|--split|--port')) { Fail 'bye_run_fail' }
Say 'bye_ok' 'Green'

# ---------------------------------------------------------------- 5. service script

$localScript = $null
if ($PSScriptRoot) { $localScript = Join-Path $PSScriptRoot 'discord-dpi.ps1' }
if ($localScript -and (Test-Path $localScript)) {
    Say 'script_local'
    Copy-Item $localScript $ScriptDest -Force
} else {
    Step 'script_dl'
    Get-Download "$RawBase/discord-dpi.ps1" $ScriptDest
}
Unblock-File -Path $ScriptDest -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 6. strategy

Step 'pick'
$env:DISCORD_DPI_LANG = $Lang
$strategy = & $PS51 -NoProfile -ExecutionPolicy Bypass -File $ScriptDest pick-strategy 2>&1 | Where-Object { $_ -is [string] -and $_ -like '--*' } | Select-Object -Last 1
if ($strategy) { Say 'pick_ok' 'Green' $strategy } else { Say 'pick_none' 'Yellow' }

# ---------------------------------------------------------------- 7. task + shortcuts

Step 'setup'
& $PS51 -NoProfile -ExecutionPolicy Bypass -File $ScriptDest setup
if ($LASTEXITCODE -ne 0) { throw "setup failed (exit $LASTEXITCODE)" }

# ---------------------------------------------------------------- 8. start + verify

Step 'starting'
Start-ScheduledTask -TaskName $TaskName
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline -and -not (Test-PortOpen $Port)) { Start-Sleep 1 }
$code = '000'
for ($attempt = 1; $attempt -le 3 -and $code -eq '000'; $attempt++) {
    if ($attempt -gt 1) { Start-Sleep 3 }
    if (-not (Test-PortOpen $Port)) { continue }
    $out = & $Curl --ssl-no-revoke -s -o NUL -m 10 -x "socks5h://127.0.0.1:$Port" -w '%{http_code}' 'https://discord.com/api/v9/gateway' 2>$null
    if ("$out".Trim()) { $code = "$out".Trim() }
}
if ($code -eq '200') { Say 'verify_ok' 'Green' $code } else { Say 'verify_bad' 'Yellow' $code }

Set-Content -Path (Join-Path $Root 'VERSION') -Value $Version -Encoding ASCII
Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Say 'done' 'Green'
Say 'hint_menu'
Say 'hint_cmd' 'Gray' $ScriptDest
Say 'hint_voice' 'DarkGray'
Write-Host ''
