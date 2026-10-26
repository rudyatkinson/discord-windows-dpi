#Requires -Version 5.1
<#
  discord-dpi.ps1 - Discord DPI for Windows (service script)

  Routes only Discord's traffic through a local ByeDPI (ciadpi) SOCKS5 proxy.
  Windows counterpart of https://github.com/rudyatkinson/discord-macos-dpi

  Commands:
    watch           run the watchdog loop (used by the scheduled task)
    status          show proxy / task / Discord state
    repair          re-pick a strategy, restart the proxy and Discord
    diagnose        build a diagnostics zip on the Desktop
    uninstall       remove everything except Discord itself
    launch          relaunch Discord through the proxy
    pick-strategy   test strategies and save the first working one
    setup           (installer) register the scheduled task and Start Menu shortcuts
    stop            stop the task and the proxy
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('watch', 'status', 'repair', 'diagnose', 'uninstall', 'launch', 'pick-strategy', 'setup', 'stop')]
    [string]$Command = 'status',
    [switch]$Pause,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ---------------------------------------------------------------- constants

$Script:Version      = '1.0.0'
$Script:Root         = Join-Path $env:LOCALAPPDATA 'DiscordDPI'
$Script:Bin          = Join-Path $Script:Root 'bin\ciadpi.exe'
$Script:ScriptPath   = Join-Path $Script:Root 'discord-dpi.ps1'
$Script:LauncherVbs  = Join-Path $Script:Root 'run-hidden.vbs'
$Script:LogDir       = Join-Path $Script:Root 'logs'
$Script:WatchLog     = Join-Path $Script:LogDir 'watch.log'
$Script:ProxyOut     = Join-Path $Script:LogDir 'ciadpi.log'
$Script:ProxyErr     = Join-Path $Script:LogDir 'ciadpi.err.log'
$Script:StrategyFile = Join-Path $Script:Root 'strategy'
$Script:PidFile      = Join-Path $Script:Root 'ciadpi.pid'
$Script:WatchPidFile = Join-Path $Script:Root 'watch.pid'

$Script:Port      = 8881
$Script:TestPort  = 8882
$Script:DiagPort  = 8883
$Script:Proxy     = "socks5://127.0.0.1:$($Script:Port)"
$Script:ProxyFlag = "--proxy-server=$($Script:Proxy)"
$Script:TaskName  = 'DiscordDPI'
$Script:MenuDir   = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Discord DPI'
$Script:DiscordDir = Join-Path $env:LOCALAPPDATA 'Discord'
$Script:Curl      = Join-Path $env:SystemRoot 'System32\curl.exe'

$Script:Hosts = @('discord.com/api/v9/gateway', 'gateway.discord.gg', 'cdn.discordapp.com')

# Tried in order; the first one that reaches every host wins.
# ByeDPI's README recommends the first two on Windows. "--fake" can be unstable
# on Windows, so fake-based strategies come later. Add new ones as new lines.
# Avoid "--split 1" (no +s) and "--fake-tls-mod rand": both broke working hosts on Windows in testing.
$Script:Strategies = @(
    '--split 1+s --disorder 3+s'
    '--disorder 1 --fake -1'
    '--disorder 1'
    '--split 1+s'
    '--tlsrec 1+s'
    '--split 1+s --tlsrec 3+s'
    '--fake -1 --ttl 8'
    '--fake -1 --ttl 5'
    '--oob 1'
    '--disoob 1'
    '--disorder 1 --auto=torst --tlsrec 1+s'
)

# ---------------------------------------------------------------- language

$Script:Lang = 'en'
if ($env:DISCORD_DPI_LANG -match '^(tr|en)$') { $Script:Lang = $Matches[1] }
elseif ((Get-Culture).Name -like 'tr*') { $Script:Lang = 'tr' }

$Script:M = @{
    en = @{
        status_title     = 'Discord DPI status'
        task             = 'Scheduled task'
        task_missing     = 'not installed'
        proxy            = 'Proxy (ciadpi)'
        proxy_running    = 'running, PID {0}, listening on 127.0.0.1:{1}'
        proxy_stopped    = 'not running'
        strategy         = 'Strategy'
        discord          = 'Discord'
        discord_proxied  = 'running through the proxy'
        discord_noproxy  = 'running WITHOUT the proxy (the watchdog will relaunch it)'
        discord_closed   = 'not running'
        reach            = 'Discord reachable via proxy'
        yes              = 'yes'
        no               = 'no'
        repair_start     = 'Testing strategies, this takes up to a minute...'
        repair_found     = 'Working strategy: {0}'
        repair_none      = 'No strategy works on this network. ByeDPI is not enough here; use a VPN or WARP.'
        repair_restart   = 'Restarting proxy and Discord...'
        repair_done      = 'Repair finished.'
        diag_start       = 'Collecting diagnostics (about a minute)...'
        diag_done        = 'Diagnostics written to: {0}'
        diag_hint        = 'Attach this zip when reporting a problem. It contains no Discord account data and no public IP.'
        uninst_confirm   = 'This removes Discord DPI (Discord itself stays). Continue? [y/N]'
        uninst_cancel    = 'Cancelled.'
        uninst_done      = 'Discord DPI removed. Discord was restarted without the proxy.'
        pause            = 'Press any key to close...'
        launch_done      = 'Discord relaunched through the proxy.'
        launch_fail      = 'Could not start Discord. Is it installed?'
        pick_testing     = 'Testing: {0}'
        setup_done       = 'Scheduled task and Start Menu shortcuts installed.'
        sc_diag          = 'Discord DPI - Report a problem'
        sc_repair        = 'Discord DPI - Repair'
        sc_uninstall     = 'Discord DPI - Uninstall'
        sc_status        = 'Discord DPI - Status'
        sum_no_internet  = 'RESULT: No internet connection (or a sign-in page is required). This is not a Discord DPI problem; it resolves once you are online.'
        sum_broken       = 'RESULT: Broken install or the background task is not running. Re-run the install command.'
        sum_port_busy    = 'RESULT: Port {0} is used by another program ({1}). Quit that program, then run Repair.'
        sum_stale        = 'RESULT: The selected strategy fails but another one works. Run Repair (the service also switches within 5 minutes).'
        sum_none         = 'RESULT: No strategy works on this network. ByeDPI is not enough here; a VPN or WARP is needed.'
        sum_fine         = 'RESULT: Discord is reachable through the proxy. The problem is elsewhere (e.g. voice channels use UDP, which this tool does not fix).'
    }
    tr = @{
        status_title     = 'Discord DPI durumu'
        task             = 'Zamanlanmış görev'
        task_missing     = 'kurulu değil'
        proxy            = 'Proxy (ciadpi)'
        proxy_running    = 'çalışıyor, PID {0}, 127.0.0.1:{1} dinliyor'
        proxy_stopped    = 'çalışmıyor'
        strategy         = 'Strateji'
        discord          = 'Discord'
        discord_proxied  = 'proxy üzerinden çalışıyor'
        discord_noproxy  = 'proxy OLMADAN çalışıyor (watchdog yeniden başlatacak)'
        discord_closed   = 'çalışmıyor'
        reach            = 'Discord proxy üzerinden erişilebilir'
        yes              = 'evet'
        no               = 'hayır'
        repair_start     = 'Stratejiler deneniyor, bir dakika kadar sürebilir...'
        repair_found     = 'Çalışan strateji: {0}'
        repair_none      = 'Bu ağda hiçbir strateji çalışmıyor. ByeDPI burada yetmiyor; VPN veya WARP kullanın.'
        repair_restart   = 'Proxy ve Discord yeniden başlatılıyor...'
        repair_done      = 'Onarım tamamlandı.'
        diag_start       = 'Tanılama toplanıyor (yaklaşık bir dakika)...'
        diag_done        = 'Tanılama dosyası: {0}'
        diag_hint        = 'Sorun bildirirken bu zip dosyasını ekleyin. İçinde Discord hesap verisi ve açık IP adresi yoktur.'
        uninst_confirm   = 'Discord DPI kaldırılacak (Discord silinmez). Devam? [e/H]'
        uninst_cancel    = 'İptal edildi.'
        uninst_done      = 'Discord DPI kaldırıldı. Discord proxy olmadan yeniden başlatıldı.'
        pause            = 'Kapatmak için bir tuşa basın...'
        launch_done      = 'Discord proxy üzerinden yeniden başlatıldı.'
        launch_fail      = 'Discord başlatılamadı. Kurulu mu?'
        pick_testing     = 'Deneniyor: {0}'
        setup_done       = 'Zamanlanmış görev ve Başlat Menüsü kısayolları kuruldu.'
        sc_diag          = 'Discord DPI - Sorun bildir'
        sc_repair        = 'Discord DPI - Onar'
        sc_uninstall     = 'Discord DPI - Kaldır'
        sc_status        = 'Discord DPI - Durum'
        sum_no_internet  = 'SONUÇ: İnternet yok (veya bir giriş sayfası gerekiyor). Bu Discord DPI sorunu değil; çevrimiçi olunca düzelir.'
        sum_broken       = 'SONUÇ: Kurulum bozuk veya arka plan görevi çalışmıyor. Kurulum komutunu yeniden çalıştırın.'
        sum_port_busy    = 'SONUÇ: {0} portunu başka bir program kullanıyor ({1}). O programı kapatıp Onar''ı çalıştırın.'
        sum_stale        = 'SONUÇ: Seçili strateji çalışmıyor ama başka biri çalışıyor. Onar''ı çalıştırın (servis de 5 dakika içinde kendisi değiştirir).'
        sum_none         = 'SONUÇ: Bu ağda hiçbir strateji çalışmıyor. ByeDPI burada yetmiyor; VPN veya WARP gerekiyor.'
        sum_fine         = 'SONUÇ: Discord proxy üzerinden erişilebilir. Sorun başka yerde (ör. ses kanalları UDP kullanır, bu araç onu düzeltmez).'
    }
}
function T([string]$key) {
    $s = $Script:M[$Script:Lang][$key]
    if (-not $s) { $s = $Script:M['en'][$key] }
    if ($args.Count -gt 0) { return ($s -f $args) }
    return $s
}

# ---------------------------------------------------------------- logging

function Ensure-Dirs {
    foreach ($d in @($Script:Root, $Script:LogDir)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

function Limit-Log([string]$path) {
    try {
        if (-not (Test-Path $path)) { return }
        $f = Get-Item $path
        if ($f.Length -le 1MB) { return }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $keep = 256KB
        $tail = New-Object byte[] $keep
        [Array]::Copy($bytes, $bytes.Length - $keep, $tail, 0, $keep)
        [System.IO.File]::WriteAllBytes("$path.1", $tail)
        [System.IO.File]::WriteAllText($path, '')
    } catch { }
}

function Log([string]$msg) {
    Ensure-Dirs
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { [System.IO.File]::AppendAllText($Script:WatchLog, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8) } catch { }
    if ($Command -ne 'watch') { Write-Host $line -ForegroundColor DarkGray }
}

# ---------------------------------------------------------------- helpers

function Test-PortOpen([int]$port, [int]$timeoutMs = 500) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($timeoutMs, $false)) { return $false }
        $c.EndConnect($ar)
        return $true
    } catch { return $false } finally { $c.Close() }
}

function Wait-Port([int]$port, [int]$seconds = 10) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-PortOpen $port) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return (Test-PortOpen $port)
}

function Get-PortOwner([int]$port) {
    try {
        $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop | Select-Object -First 1
        if ($c) { return (Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue) }
    } catch { }
    return $null
}

function Test-Online {
    $out = & $Script:Curl -s -m 5 'http://www.msftconnecttest.com/connecttest.txt' 2>$null
    return ("$out" -match 'Microsoft Connect Test')
}

function Get-HttpCode([int]$port, [string]$h, [int]$timeout) {
    # --ssl-no-revoke: Windows curl (Schannel) otherwise fails with CRYPT_E_REVOCATION_OFFLINE when the
    # OCSP/CRL servers are unreachable, which looks exactly like a block. Chain validation stays on.
    $out = & $Script:Curl --ssl-no-revoke -s -o NUL -m $timeout -x "socks5h://127.0.0.1:$port" -w '%{http_code}' "https://$h" 2>$null
    $code = "$out".Trim()
    if (-not $code) { $code = '000' }
    return $code
}

function Get-NetSignature {
    try {
        $parts = foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($ni.OperationalStatus -ne 'Up' -or $ni.NetworkInterfaceType -eq 'Loopback') { continue }
            $p = $ni.GetIPProperties()
            $ips = ($p.UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.Address.ToString() }) -join ','
            $gw  = ($p.GatewayAddresses | ForEach-Object { $_.Address.ToString() }) -join ','
            $dns = ($p.DnsAddresses | ForEach-Object { $_.ToString() }) -join ','
            "$($ni.Id)|$ips|$gw|$dns"
        }
        return ($parts -join ';')
    } catch { return '' }
}

# ---------------------------------------------------------------- strategy

function Get-CurrentStrategy {
    $s = ''
    if (Test-Path $Script:StrategyFile) {
        $s = Get-Content $Script:StrategyFile -Raw -ErrorAction SilentlyContinue
        if ($s) { $s = $s.Trim() }
    }
    if ($Script:Strategies -contains $s) { return $s }
    return $Script:Strategies[0]
}

function Start-Ciadpi([int]$port, [string]$strategy, [string]$outLog, [string]$errLog) {
    if (-not (Test-Path $Script:Bin)) { return $null }
    # -I 0.0.0.0: IPv4 only. ciadpi has no happy-eyeballs fallback, so a machine with a global IPv6
    # address but no working IPv6 route would otherwise time out on every dual-stack host.
    $argLine = "-i 127.0.0.1 -p $port -I 0.0.0.0 -c 512 $strategy"
    try {
        $p = Start-Process -FilePath $Script:Bin -ArgumentList $argLine -NoNewWindow -PassThru `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog
        return $p
    } catch { Log "ciadpi start failed: $_"; return $null }
}

function Stop-Pid($p) {
    if (-not $p) { return }
    try { if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit(3000) | Out-Null } } catch { }
}

# Runs one strategy on a throw-away port. Returns host->code plus Passed.
function Test-Strategy([int]$port, [string]$strategy, [switch]$Fast, [int]$timeout = 6) {
    $tmpOut = Join-Path $env:TEMP "ciadpi-test-$port.log"
    $tmpErr = Join-Path $env:TEMP "ciadpi-test-$port.err"
    $result = [ordered]@{}
    $passed = $true
    $p = Start-Ciadpi -port $port -strategy $strategy -outLog $tmpOut -errLog $tmpErr
    try {
        if (-not $p -or -not (Wait-Port $port 10)) {
            foreach ($h in $Script:Hosts) { $result[$h] = 'NOPROXY' }
            $passed = $false
        } else {
            foreach ($h in $Script:Hosts) {
                $code = Get-HttpCode -port $port -h $h -timeout $timeout
                # One retry: a transient DNS timeout on the resolver side also shows up as 000.
                if ($code -eq '000') { Start-Sleep -Milliseconds 500; $code = Get-HttpCode -port $port -h $h -timeout $timeout }
                $result[$h] = $code
                if ($code -eq '000') { $passed = $false; if ($Fast) { break } }
            }
        }
    } finally { Stop-Pid $p }
    $result['Passed'] = $passed
    return $result
}

function Select-Strategy([int]$port = 8882, [switch]$Quiet) {
    foreach ($s in $Script:Strategies) {
        if (-not $Quiet) { Write-Host (T 'pick_testing' $s) }
        $r = Test-Strategy -port $port -strategy $s -Fast
        if ($r.Passed) {
            Ensure-Dirs
            [System.IO.File]::WriteAllText($Script:StrategyFile, $s)
            Log "strategy selected: $s"
            return $s
        }
    }
    return $null
}

# ---------------------------------------------------------------- proxy

function Get-ProxyProcess {
    try {
        if (Test-Path $Script:PidFile) {
            $id = [int]((Get-Content $Script:PidFile -Raw).Trim())
            $p = Get-Process -Id $id -ErrorAction SilentlyContinue
            if ($p -and $p.ProcessName -eq 'ciadpi') { return $p }
        }
    } catch { }
    $owner = Get-PortOwner $Script:Port
    if ($owner -and $owner.ProcessName -eq 'ciadpi') { return $owner }
    return $null
}

function Start-Proxy {
    Ensure-Dirs
    $owner = Get-PortOwner $Script:Port
    if ($owner -and $owner.ProcessName -ne 'ciadpi') {
        Log "port $($Script:Port) busy: $($owner.ProcessName) (PID $($owner.Id))"
        return $false
    }
    foreach ($f in @($Script:ProxyOut, $Script:ProxyErr)) { Limit-Log $f }
    $p = Start-Ciadpi -port $Script:Port -strategy (Get-CurrentStrategy) -outLog $Script:ProxyOut -errLog $Script:ProxyErr
    if (-not $p) { return $false }
    [System.IO.File]::WriteAllText($Script:PidFile, "$($p.Id)")
    if (-not (Wait-Port $Script:Port 10)) { Stop-Pid $p; return $false }
    return $true
}

function Stop-Proxy {
    $p = Get-ProxyProcess
    if ($p) { Stop-Pid $p }
    # Stray instances that lost their pid file
    Get-Process ciadpi -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Script:Bin } | ForEach-Object { Stop-Pid $_ }
    Remove-Item $Script:PidFile -ErrorAction SilentlyContinue
}

function Test-Probe([int]$timeout = 8) {
    foreach ($h in $Script:Hosts) {
        if ((Get-HttpCode -port $Script:Port -h $h -timeout $timeout) -eq '000') { return $false }
    }
    return $true
}

# ---------------------------------------------------------------- discord

function Get-DiscordState {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='Discord.exe'" -ErrorAction SilentlyContinue)
    $proxied = @($procs | Where-Object { $_.CommandLine -like "*$($Script:ProxyFlag)*" })
    $minimized = @($procs | Where-Object { $_.CommandLine -like '*--start-minimized*' })
    return [pscustomobject]@{
        Running   = ($procs.Count -gt 0)
        HasProxy  = ($proxied.Count -gt 0)
        Minimized = ($minimized.Count -gt 0)
    }
}

function Stop-Discord {
    Get-Process Discord -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process Discord -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return (-not (Get-Process Discord -ErrorAction SilentlyContinue))
}

function Get-DiscordExe {
    $dirs = Get-ChildItem -Path $Script:DiscordDir -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'Discord.exe') }
    $best = $dirs | Sort-Object { try { [version]($_.Name -replace '^app-', '') } catch { [version]'0.0' } } -Descending | Select-Object -First 1
    if ($best) { return (Join-Path $best.FullName 'Discord.exe') }
    return $null
}

# $extra: additional Discord flags (e.g. --start-minimized).
function Start-Discord([string[]]$extra = @(), [switch]$NoProxy) {
    $flags = @()
    if (-not $NoProxy) { $flags += $Script:ProxyFlag }
    $flags += $extra
    $update = Join-Path $Script:DiscordDir 'Update.exe'
    $exe = Get-DiscordExe
    try {
        if ($exe) {
            # Direct launch keeps the flags visible on the main process command line.
            if ($flags.Count -gt 0) { Start-Process -FilePath $exe -ArgumentList $flags -WorkingDirectory (Split-Path $exe) | Out-Null }
            else { Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) | Out-Null }
            return $true
        }
        if (Test-Path $update) {
            $a = @('--processStart', 'Discord.exe')
            if ($flags.Count -gt 0) { $a += @('--process-start-args', ($flags -join ' ')) }
            Start-Process -FilePath $update -ArgumentList $a | Out-Null
            return $true
        }
    } catch { Log "discord launch failed: $_" }
    return $false
}

function Restart-DiscordProxied {
    $st = Get-DiscordState
    $extra = @(); if ($st.Minimized) { $extra += '--start-minimized' }
    if ($st.Running) { Stop-Discord | Out-Null }
    return (Start-Discord -extra $extra)
}

# ---------------------------------------------------------------- health / watch

$Script:LastPick = [datetime]::MinValue
$Script:NoStrategyLogged = $false
$Script:LastOnline = $true

function Invoke-HealthCheck([switch]$Forced) {
    $ok = Test-Probe
    if (-not $ok) { Start-Sleep 3; $ok = Test-Probe }
    if ($ok) { $Script:LastOnline = $true; $Script:NoStrategyLogged = $false; return $true }

    $online = Test-Online
    $Script:LastOnline = $online
    if (-not $online) { Log 'offline (captive portal or no internet)'; return $false }
    if (-not $Forced -and ((Get-Date) - $Script:LastPick).TotalSeconds -lt 300) { return $false }

    Log 'discord unreachable through proxy; re-picking strategy'
    $old = Get-CurrentStrategy
    $new = Select-Strategy -port $Script:TestPort -Quiet
    $Script:LastPick = Get-Date
    if ($new) {
        if ($new -ne $old) { Log "strategy changed: '$old' -> '$new'" } else { Log 'same strategy works on the test port; restarting proxy' }
        Stop-Proxy
        Start-Proxy | Out-Null
        $Script:NoStrategyLogged = $false
        return $true
    }
    if (-not $Script:NoStrategyLogged) {
        Log 'no strategy works on this network (ByeDPI is not enough here; VPN/WARP needed)'
        $Script:NoStrategyLogged = $true
    }
    return $false
}

function Invoke-Watch {
    $mutex = New-Object System.Threading.Mutex($false, 'Local\DiscordDPI.watch')
    if (-not $mutex.WaitOne(0, $false)) { return }
    Ensure-Dirs
    try { [System.IO.File]::WriteAllText($Script:WatchPidFile, "$PID") } catch { }
    Log "watch start v$($Script:Version) (strategy: $(Get-CurrentStrategy))"

    $nextCheck = Get-Date
    $forced = $true
    $lastSig = Get-NetSignature
    $lastNetPoll = Get-Date
    $wasRunning = $false
    $relaunchFails = 0
    $backoffUntil = [datetime]::MinValue

    while ($true) {
        try {
            $now = Get-Date

            # 1. keep the proxy alive
            if (-not (Get-ProxyProcess)) {
                if (Start-Proxy) { Log "proxy started on 127.0.0.1:$($Script:Port) ($(Get-CurrentStrategy))" }
                else { Log 'proxy start failed; retrying in 30s'; Start-Sleep 30; continue }
            }

            # 2. network change -> forced check
            if (($now - $lastNetPoll).TotalSeconds -ge 10) {
                $sig = Get-NetSignature; $lastNetPoll = $now
                if ($sig -ne $lastSig) { $lastSig = $sig; Log 'network change -> forced check'; $forced = $true; $nextCheck = $now }
            }

            # 3. discord closed -> open transition
            $st = Get-DiscordState
            if ($st.Running -and -not $wasRunning) { Log 'discord started'; $forced = $true; $nextCheck = $now }
            $wasRunning = $st.Running

            # 4. scheduled health check
            if ($now -ge $nextCheck -and ($forced -or $st.Running)) {
                Invoke-HealthCheck -Forced:$forced | Out-Null
                $forced = $false
                $interval = 60; if (-not $Script:LastOnline) { $interval = 15 }
                $nextCheck = (Get-Date).AddSeconds($interval)
            }

            # 5. discord running without the proxy -> relaunch
            if ($st.Running -and -not $st.HasProxy) {
                if ($now -ge $backoffUntil) {
                    Log 'discord running without proxy -> relaunch'
                    if (Restart-DiscordProxied) {
                        Start-Sleep 5
                        if ((Get-DiscordState).HasProxy) { $relaunchFails = 0; Log 'discord relaunched through proxy' } else { $relaunchFails++ }
                    } else { $relaunchFails++ }
                    if ($relaunchFails -ge 3) {
                        Log 'relaunch failed 3 times; waiting 60s'
                        $backoffUntil = (Get-Date).AddSeconds(60); $relaunchFails = 0
                    }
                }
            } elseif ($st.HasProxy) { $relaunchFails = 0 }

            Limit-Log $Script:WatchLog
        } catch { Log "watch error: $_" }
        Start-Sleep 2
    }
}

# ---------------------------------------------------------------- setup (task + shortcuts)

function Get-TaskInfo { try { return (Get-ScheduledTask -TaskName $Script:TaskName -ErrorAction Stop) } catch { return $null } }

function Install-Task {
    Ensure-Dirs
    $psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$($Script:ScriptPath)"" watch"
    # The wscript launcher avoids the console flash at logon; falls back to powershell.exe if WSH is unavailable.
    # Wait=True keeps wscript alive for the lifetime of the watch loop, so the task shows "Running"
    # and Stop-ScheduledTask / Stop-Task can end it.
    $vbs = 'CreateObject("WScript.Shell").Run "powershell.exe ' + ($psArgs -replace '"', '""') + '", 0, True'
    [System.IO.File]::WriteAllText($Script:LauncherVbs, $vbs, [System.Text.Encoding]::ASCII)

    $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    if (Test-Path $wscript) { $action = New-ScheduledTaskAction -Execute $wscript -Argument "//B //Nologo ""$($Script:LauncherVbs)""" }
    else { $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs }

    $user = "$env:USERDOMAIN\$env:USERNAME"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1) `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -MultipleInstances IgnoreNew -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $Script:TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
}

function Install-Shortcuts {
    if (-not (Test-Path $Script:MenuDir)) { New-Item -ItemType Directory -Path $Script:MenuDir -Force | Out-Null }
    $icon = Join-Path $Script:DiscordDir 'app.ico'
    $ws = New-Object -ComObject WScript.Shell
    $items = @(
        @{ name = (T 'sc_status');    cmd = 'status' }
        @{ name = (T 'sc_diag');      cmd = 'diagnose' }
        @{ name = (T 'sc_repair');    cmd = 'repair' }
        @{ name = (T 'sc_uninstall'); cmd = 'uninstall' }
    )
    Get-ChildItem $Script:MenuDir -Filter '*.lnk' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $i = 0
    foreach ($it in $items) {
        # WScript.Shell mangles non-ANSI characters in the path (Kaldır -> Kaldir), so save under an
        # ASCII name and rename with .NET afterwards.
        $tmp = Join-Path $Script:MenuDir "shortcut-$i.lnk"; $i++
        $lnk = $ws.CreateShortcut($tmp)
        $lnk.TargetPath = 'powershell.exe'
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File ""$($Script:ScriptPath)"" $($it.cmd) -Pause"
        $lnk.WorkingDirectory = $Script:Root
        if (Test-Path $icon) { $lnk.IconLocation = $icon }
        $lnk.Save()
        Move-Item -LiteralPath $tmp -Destination (Join-Path $Script:MenuDir "$($it.name).lnk") -Force
    }
}

function Stop-Watch {
    # Kill the watch loop by pid file, then any stray "discord-dpi.ps1 watch" powershell (older versions).
    try {
        if (Test-Path $Script:WatchPidFile) {
            $id = [int]((Get-Content $Script:WatchPidFile -Raw).Trim())
            if ($id -ne $PID) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
        }
    } catch { }
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*discord-dpi.ps1*watch*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Remove-Item $Script:WatchPidFile -ErrorAction SilentlyContinue
}

function Stop-Task {
    if (Get-TaskInfo) { try { Stop-ScheduledTask -TaskName $Script:TaskName -ErrorAction SilentlyContinue } catch { } }
    Stop-Watch
}

# ---------------------------------------------------------------- commands

function Show-Status {
    Write-Host ''
    Write-Host (T 'status_title') -ForegroundColor Cyan
    $t = Get-TaskInfo
    $tState = if ($t) { "$($t.State)" } else { T 'task_missing' }
    Write-Host ("  {0,-36} {1}" -f ((T 'task') + ':'), $tState)
    $p = Get-ProxyProcess
    $pState = if ($p) { T 'proxy_running' $p.Id $Script:Port } else { T 'proxy_stopped' }
    Write-Host ("  {0,-36} {1}" -f ((T 'proxy') + ':'), $pState)
    Write-Host ("  {0,-36} {1}" -f ((T 'strategy') + ':'), (Get-CurrentStrategy))
    $st = Get-DiscordState
    $dState = if (-not $st.Running) { T 'discord_closed' } elseif ($st.HasProxy) { T 'discord_proxied' } else { T 'discord_noproxy' }
    Write-Host ("  {0,-36} {1}" -f ((T 'discord') + ':'), $dState)
    $reach = if ($p -and (Test-Probe)) { T 'yes' } else { T 'no' }
    Write-Host ("  {0,-36} {1}" -f ((T 'reach') + ':'), $reach)
    Write-Host ''
}

function Invoke-Repair {
    Write-Host (T 'repair_start')
    Stop-Task
    Stop-Proxy
    $s = Select-Strategy -port $Script:DiagPort
    if ($s) { Write-Host (T 'repair_found' $s) -ForegroundColor Green } else { Write-Host (T 'repair_none') -ForegroundColor Yellow }
    Write-Host (T 'repair_restart')
    if (Get-TaskInfo) { Start-ScheduledTask -TaskName $Script:TaskName } else { Start-Proxy | Out-Null }
    Wait-Port $Script:Port 15 | Out-Null
    Restart-DiscordProxied | Out-Null
    Write-Host (T 'repair_done')
    Show-Status
}

function Invoke-Diagnose {
    Write-Host (T 'diag_start')
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $work = Join-Path $env:TEMP "DiscordDPI-diagnostics-$stamp"
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $desktop = [Environment]::GetFolderPath('Desktop')
    $zip = Join-Path $desktop "DiscordDPI-diagnostics-$stamp.zip"

    # --- facts
    $online = Test-Online
    $task = Get-TaskInfo
    $taskOk = ($null -ne $task) -and ($task.State -eq 'Running')
    $binOk = Test-Path $Script:Bin
    $owner = Get-PortOwner $Script:Port
    $portBusy = ($null -ne $owner) -and ($owner.ProcessName -ne 'ciadpi')
    $current = Get-CurrentStrategy
    $live = $false
    if ($owner -and -not $portBusy) { $live = Test-Probe }

    # --- per-strategy table (uses the diag port, does not touch the live proxy)
    $lines = @('strategy | ' + ($Script:Hosts -join ' | ') + ' | passed')
    $results = @{}
    if ($online) {
        foreach ($s in $Script:Strategies) {
            $r = Test-Strategy -port $Script:DiagPort -strategy $s
            $results[$s] = $r.Passed
            $codes = foreach ($h in $Script:Hosts) { $r[$h] }
            $lines += ('{0} | {1} | {2}' -f $s, ($codes -join ' | '), $r.Passed)
        }
    }
    $anyWorks = @($results.Values | Where-Object { $_ }).Count -gt 0
    $currentWorks = ($results[$current] -eq $true)
    $lines | Set-Content (Join-Path $work 'strategies.txt') -Encoding UTF8

    # --- summary
    if (-not $online)                     { $verdict = T 'sum_no_internet' }
    elseif (-not $taskOk -or -not $binOk) { $verdict = T 'sum_broken' }
    elseif ($portBusy)                    { $verdict = T 'sum_port_busy' $Script:Port $owner.ProcessName }
    elseif ($live)                        { $verdict = T 'sum_fine' }
    elseif (-not $anyWorks)               { $verdict = T 'sum_none' }
    else                                  { $verdict = T 'sum_stale' }

    $ownerText = 'none'; if ($owner) { $ownerText = "$($owner.ProcessName) (PID $($owner.Id))" }
    $taskText = 'missing'; if ($task) { $taskText = "$($task.State)" }
    $arch = 'x86'; if ([Environment]::Is64BitOperatingSystem) { $arch = 'x64' }
    $sum = @(
        $verdict
        ''
        "Discord DPI version : $($Script:Version)"
        "Language            : $($Script:Lang)"
        "Windows             : $([Environment]::OSVersion.VersionString) ($arch)"
        "PowerShell          : $($PSVersionTable.PSVersion)"
        "Online              : $online"
        "Task                : $taskText"
        "ciadpi.exe present  : $binOk"
        "Port $($Script:Port) owner     : $ownerText"
        "Selected strategy   : $current"
        "Selected works (test): $currentWorks"
        "Live proxy reaches Discord : $live"
        "Any strategy works  : $anyWorks"
        "Discord             : $((Get-DiscordState) | ConvertTo-Json -Compress)"
    )
    $sum | Set-Content (Join-Path $work 'summary.txt') -Encoding UTF8

    # --- network (no public IP)
    $net = @()
    $org = & $Script:Curl -s -m 5 'https://ipinfo.io/org' 2>$null
    $net += "ISP/org: $org"
    $net += ''
    foreach ($h in @('discord.com', 'gateway.discord.gg', 'cdn.discordapp.com')) {
        try {
            $a = (Resolve-DnsName $h -Type A -ErrorAction Stop | Where-Object { $_.Type -eq 'A' } | ForEach-Object { $_.IPAddress }) -join ', '
            $net += "DNS $h -> $a"
        } catch { $net += "DNS $h -> FAILED ($_)" }
    }
    $net += ''
    $net += 'Adapters (up):'
    $adapters = @()
    try { $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }) } catch { }
    foreach ($ad in $adapters) { $net += "  $($ad.Name) | $($ad.InterfaceDescription)" }
    $vpnPat = 'TAP|WireGuard|Wintun|Cloudflare|WARP|OpenVPN|NordLynx|ExpressVPN|Proton|Surfshark|TunnelBear|Mullvad|ZeroTier|Tailscale|Hamachi|Radmin'
    $vpnAdapters = @($adapters | Where-Object { $_.InterfaceDescription -match $vpnPat } | ForEach-Object { $_.Name })
    $vpnProcs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'warp|openvpn|wireguard|nordvpn|expressvpn|protonvpn|surfshark|tunnelbear|mullvad|zerotier|tailscale|hamachi|goodbyedpi|winws|zapret' } | Select-Object -ExpandProperty ProcessName -Unique)
    $net += ''
    $vt = 'none'; if ($vpnAdapters.Count) { $vt = $vpnAdapters -join ', ' }
    $pt = 'none'; if ($vpnProcs.Count) { $pt = $vpnProcs -join ', ' }
    $net += "VPN-like adapters: $vt"
    $net += "VPN/DPI-like processes: $pt"
    $net += ''
    $inet = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    $net += "System proxy (WinINET): enable=$($inet.ProxyEnable) server=$($inet.ProxyServer)"
    $net | Set-Content (Join-Path $work 'network.txt') -Encoding UTF8

    # --- task
    $tl = @()
    if ($task) {
        $tl += ($task | Select-Object TaskName, State | Format-List | Out-String)
        try { $tl += (Get-ScheduledTaskInfo -TaskName $Script:TaskName | Select-Object LastRunTime, LastTaskResult, NextRunTime, NumberOfMissedRuns | Format-List | Out-String) } catch { }
        $tl += ($task.Actions | Format-List | Out-String)
    } else { $tl += 'task missing' }
    $tl | Set-Content (Join-Path $work 'task.txt') -Encoding UTF8

    # --- logs (tail)
    foreach ($f in @($Script:WatchLog, $Script:ProxyOut, $Script:ProxyErr)) {
        if (Test-Path $f) { Get-Content $f -Tail 200 -ErrorAction SilentlyContinue | Set-Content (Join-Path $work (Split-Path $f -Leaf)) -Encoding UTF8 }
    }

    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $work '*') -DestinationPath $zip -Force
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host $verdict -ForegroundColor Cyan
    Write-Host ''
    Write-Host (T 'diag_done' $zip) -ForegroundColor Green
    Write-Host (T 'diag_hint')
    return $zip
}

function Invoke-Uninstall {
    if (-not $Force) {
        $ans = Read-Host -Prompt (T 'uninst_confirm')
        if ($ans -notmatch '^(y|e|yes|evet)$') { Write-Host (T 'uninst_cancel'); return }
    }
    Stop-Task
    try { Unregister-ScheduledTask -TaskName $Script:TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    Stop-Proxy
    $st = Get-DiscordState
    if ($st.Running -and $st.HasProxy) {
        $extra = @(); if ($st.Minimized) { $extra += '--start-minimized' }
        Stop-Discord | Out-Null
        Start-Discord -extra $extra -NoProxy | Out-Null
    }
    Remove-Item $Script:MenuDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $Script:Root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $env:TEMP 'ciadpi-test-*') -Force -ErrorAction SilentlyContinue
    Write-Host (T 'uninst_done') -ForegroundColor Green
}

# ---------------------------------------------------------------- main

switch ($Command) {
    'watch'         { Invoke-Watch }
    'status'        { Show-Status }
    'repair'        { Invoke-Repair }
    'diagnose'      { Invoke-Diagnose | Out-Null }
    'uninstall'     { Invoke-Uninstall }
    'launch'        { if (Restart-DiscordProxied) { Write-Host (T 'launch_done') } else { Write-Host (T 'launch_fail') -ForegroundColor Red } }
    'pick-strategy' { $s = Select-Strategy; if ($s) { Write-Output $s } else { exit 2 } }
    'setup'         { Install-Task; Install-Shortcuts; Write-Host (T 'setup_done') }
    'stop'          { Stop-Task; Stop-Proxy }
}

if ($Pause) {
    Write-Host ''
    Write-Host (T 'pause')
    try { [void][Console]::ReadKey($true) } catch { }
}
