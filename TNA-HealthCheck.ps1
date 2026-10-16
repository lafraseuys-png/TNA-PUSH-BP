<#
.SYNOPSIS
    TNA Africa - one-shot system health check (non-interactive, read-only).

.DESCRIPTION
    Run from the application folder (the one that holds server.js and secrets.env):

        powershell -ExecutionPolicy Bypass -File .\TNA-HealthCheck.ps1

    Prints [ OK ] / [WARN] / [FAIL] lines for:
      - git: current commit, behind the remote?, uncommitted files
      - node + the modules the server needs
      - pm2: every process, uptime, restarts, and whether the code on disk
        is newer than the running process (= restart needed)
      - port + HTTP: login page reachable, new leave endpoint present
      - database: master reachable, every active tenant reachable
      - build: obfuscated scripts on one page sharing a helper name
      - last errors in the pm2 error log
      - disk and memory
    Exit code = number of FAIL lines, so it can be used from a scheduler.
#>
param([string]$AppDir = $PSScriptRoot)

$ErrorActionPreference = 'Continue'
if (-not $AppDir) { $AppDir = (Get-Location).Path }
Set-Location $AppDir
$env:GIT_TERMINAL_PROMPT = '0'

$script:fail = 0; $script:warn = 0
function Pass($m) { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Warn($m) { $script:warn++; Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Fail($m) { $script:fail++; Write-Host "[FAIL] $m" -ForegroundColor Red }
function Info($m) { Write-Host "       $m" -ForegroundColor Gray }
function Head($m) { Write-Host ""; Write-Host "== $m ==" -ForegroundColor Cyan }
# Native commands via cmd so stderr never becomes a PowerShell error record
function Native($cmdLine) { $o = cmd /c "$cmdLine 2>nul"; if ($null -eq $o) { return '' } return (($o | ForEach-Object { "$_" }) -join "`n").Trim() }

Write-Host "TNA Africa Health Check - $(Get-Date -Format 'yyyy-MM-dd HH:mm')  ($env:COMPUTERNAME)" -ForegroundColor White

# ---------------------------------------------------------------- 1. folder + config
Head "Application folder"
Info $AppDir
if (Test-Path 'server.js') { Pass "server.js found" } else { Fail "server.js not found - run this from the TNA application folder" }

$cfg = @{}
if (Test-Path 'secrets.env') {
    Get-Content 'secrets.env' | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $v = $matches[2].Trim()
            # dotenv strips matching surrounding quotes - do the same
            if ($v.Length -ge 2 -and (($v[0] -eq '"' -and $v[-1] -eq '"') -or ($v[0] -eq "'" -and $v[-1] -eq "'"))) { $v = $v.Substring(1, $v.Length - 2) }
            $cfg[$matches[1]] = $v
        }
    }
    Pass "secrets.env read ($($cfg.Keys.Count) settings)"
    foreach ($k in 'DB_SERVER', 'DB_NAME', 'DB_USER', 'DB_PASSWORD', 'JWT_SECRET') {
        if (-not $cfg[$k]) { Fail "secrets.env is missing $k" }
    }
    if ($cfg['DB_SERVER']) { Info "Database: $($cfg['DB_SERVER'])  master DB: $($cfg['DB_NAME'])" }
} else {
    Fail "secrets.env not found"
}
$port = $cfg['PORT']

# ---------------------------------------------------------------- 2. git
Head "Git"
if (Test-Path '.git') {
    $head = Native 'git log -1 --format="%h | %ci | %s"'
    if ($head) { Pass "Current commit: $head" } else { Warn "git log failed" }
    $null = Native 'git fetch --quiet origin'
    $branch = Native 'git rev-parse --abbrev-ref HEAD'
    $behind = Native "git rev-list --count HEAD..origin/$branch"
    $ahead  = Native "git rev-list --count origin/$branch..HEAD"
    if ($behind -match '^\d+$') {
        if ([int]$behind -gt 0) { Warn "$behind commit(s) behind origin/$branch - run: git pull" } else { Pass "Up to date with origin/$branch" }
        if ([int]$ahead -gt 0) { Info "$ahead local commit(s) not pushed" }
    } else { Warn "Could not compare with origin (no network or credentials?)" }
    $dirty = Native 'git status --porcelain'
    if ($dirty) {
        $names = @($dirty -split "`n" | ForEach-Object { $_.Substring([Math]::Min(3, $_.Length)) })
        Warn "$($names.Count) file(s) changed locally and not committed: $(($names | Select-Object -First 5) -join ', ')$(if ($names.Count -gt 5) { ' ...' })"
    } else { Pass "No local changes" }
} else {
    Warn "Not a git folder - cannot tell which version is deployed"
}

# ---------------------------------------------------------------- 3. node + modules
Head "Node.js"
$nodeV = Native 'node -v'
if ($nodeV) { Pass "node $nodeV" } else { Fail "node is not on the PATH" }
if (Test-Path 'node_modules') {
    $modCheck = Native 'node -e "[''mssql'',''express'',''node-cron'',''nodemailer'',''axios'',''jsonwebtoken''].forEach(m=>{try{require.resolve(m);console.log(''OK ''+m)}catch(e){console.log(''MISSING ''+m)}})"'
    $missing = @($modCheck -split "`n" | Where-Object { $_ -like 'MISSING*' })
    if ($missing.Count -eq 0) { Pass "Required modules present (mssql, express, node-cron, nodemailer, axios, jsonwebtoken)" }
    else { Fail "Missing modules: $(($missing | ForEach-Object { $_ -replace 'MISSING ','' }) -join ', ') - run: npm install" }
} else {
    Fail "node_modules folder missing - run: npm install"
}

# ---------------------------------------------------------------- 4. pm2
Head "PM2 processes"
$procs = @()
# pm2's JSON carries the whole process environment, which PowerShell 5.1 cannot
# parse (keys that differ only by case, e.g. username/USERNAME). node slims it first.
$pm2Js = Join-Path $env:TEMP 'tna_healthcheck_pm2.js'
@'
let s = ''; process.stdin.on('data', d => s += d).on('end', () => {
    const i = s.indexOf('['); if (i < 0) { console.log('[]'); return; }
    let a = []; try { a = JSON.parse(s.slice(i)); } catch (e) { console.log('[]'); return; }
    console.log(JSON.stringify(a.map(p => ({
        name: p.name, status: p.pm2_env.status, uptime: p.pm2_env.pm_uptime, restarts: p.pm2_env.restart_time,
        memory: p.monit ? p.monit.memory : 0, cwd: p.pm2_env.pm_cwd || '',
        port: (p.pm2_env.env && p.pm2_env.env.PORT) ? String(p.pm2_env.env.PORT) : '',
        errlog: p.pm2_env.pm_err_log_path || ''
    }))));
});
'@ | Set-Content -Path $pm2Js -Encoding ASCII
$jl = Native "pm2 jlist | node `"$pm2Js`""
Remove-Item $pm2Js -ErrorAction SilentlyContinue
if ($jl) {
    # PS 5.1 returns a JSON array as one Object[] - unwrap it so $p is a single process
    try { $parsed = ConvertFrom-Json -InputObject $jl; $procs = @($parsed | ForEach-Object { $_ }) } catch { $procs = @() }
}
# newest server-side code file (public/ is served from disk and never needs a restart)
$newestCode = $null
foreach ($d in '.', 'services', 'routes', 'utils', 'middleware', 'config') {
    if (Test-Path $d) {
        $f = Get-ChildItem -Path $d -Filter '*.js' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f -and ($null -eq $newestCode -or $f.LastWriteTime -gt $newestCode.LastWriteTime)) { $newestCode = $f }
    }
}
if ($procs.Count -eq 0) {
    Fail "pm2 reports no processes (or pm2 is not installed) - run: pm2 list"
} else {
    $appNorm = $AppDir.TrimEnd('\').ToLower()
    foreach ($p in $procs) {
        $started = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$p.uptime).LocalDateTime
        $mem = [math]::Round(($p.memory / 1MB), 0)
        $line = "$($p.name): $($p.status), since $($started.ToString('yyyy-MM-dd HH:mm')), restarts $($p.restarts), ${mem}MB"
        if ($p.status -eq 'online') { Pass $line } else { Fail $line }
        $isThisApp = ($p.cwd -and $p.cwd.TrimEnd('\').ToLower() -eq $appNorm)
        if ($isThisApp) {
            if (-not $port -and $p.port) { $port = $p.port }
            if ($newestCode -and $newestCode.LastWriteTime -gt $started) {
                Warn "Code on disk ($($newestCode.Name), $($newestCode.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))) is newer than the running process - run: pm2 restart $($p.name)"
            } else {
                Pass "Running process is current with the code on disk"
            }
            if ([int]$p.restarts -gt 20) { Warn "$($p.name) has restarted $($p.restarts) times - check the error log below" }
        }
    }
}

# ---------------------------------------------------------------- 5. port + http
Head "Web server"
if (-not $port) { $port = '3036'; Warn "PORT not found in secrets.env or pm2 - assuming $port" }
$tcp = New-Object System.Net.Sockets.TcpClient
try { $tcp.Connect('127.0.0.1', [int]$port); $tcp.Close(); Pass "Port $port is listening" } catch { Fail "Nothing is listening on port $port" }

$base = "http://localhost:$port"
try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri "$base/Login.html" -TimeoutSec 15
    if ($r.StatusCode -eq 200) { Pass "Login page responds (HTTP 200)" } else { Warn "Login page returned HTTP $($r.StatusCode)" }
} catch { Fail "Login page not reachable: $($_.Exception.Message)" }

# The Sage leave-day endpoint only exists in builds from 2026-10-15 onward.
# Unknown /api routes answer 404, so a 401/403 here proves the route is loaded in the running process.
try {
    $null = Invoke-WebRequest -UseBasicParsing -Uri "$base/api/sage/leave-days-pull" -Method Post -TimeoutSec 15
    Warn "Leave endpoint answered without a token - check authentication"
} catch {
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode.value__ }
    if ($code -eq 401 -or $code -eq 403) { Pass "Sage leave pull endpoint is live (HTTP $code without token, as expected)" }
    elseif ($code -eq 404) { Warn "Sage leave pull endpoint not found (HTTP 404) - old server code running: git pull + pm2 restart" }
    else { Warn "Leave endpoint check inconclusive: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------- 6. database
Head "Database"
if ($cfg['DB_SERVER'] -and (Test-Path 'node_modules\mssql')) {
    $dbJs = Join-Path $env:TEMP 'tna_healthcheck_db.js'
    @'
const path = require('path'); const fs = require('fs');
const app = process.argv[2];
const sql = require(path.join(app, 'node_modules', 'mssql'));
const env = {};
fs.readFileSync(path.join(app, 'secrets.env'), 'utf8').split(/\r?\n/).forEach(l => {
    const m = l.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/); if (!m) return;
    let v = m[2].trim(); if (v.length >= 2 && ((v[0] === '"' && v.slice(-1) === '"') || (v[0] === "'" && v.slice(-1) === "'"))) v = v.slice(1, -1); // dotenv strips quotes
    env[m[1]] = v;
});
const cfg = { server: env.DB_SERVER, port: env.DB_PORT ? parseInt(env.DB_PORT, 10) : 1433, user: env.DB_USER, password: env.DB_PASSWORD, database: env.DB_NAME,
              options: { encrypt: false, trustServerCertificate: true }, connectionTimeout: 10000, requestTimeout: 20000 };
(async () => {
    let master;
    try {
        master = await new sql.ConnectionPool(cfg).connect();
        const r = await master.request().query('SELECT DatabaseName, ISNULL(IsActive, 1) AS IsActive FROM Tenants WITH (NOLOCK)');
        console.log('MASTER OK ' + env.DB_NAME + ' tenants=' + r.recordset.length);
        let bad = 0;
        for (const t of r.recordset) {
            if (!t.IsActive) continue;
            let tp;
            try {
                tp = await new sql.ConnectionPool(Object.assign({}, cfg, { database: t.DatabaseName })).connect();
                let extra = '';
                try {
                    const c = await tp.request().query('SELECT (SELECT COUNT(*) FROM Employees WITH (NOLOCK)) AS Emps, (SELECT MAX(ClockTime) FROM ClockRecords WITH (NOLOCK)) AS LastPunch');
                    const x = c.recordset[0];
                    extra = ' employees=' + x.Emps + ' lastPunch=' + (x.LastPunch ? new Date(x.LastPunch).toISOString().slice(0, 16).replace('T', ' ') : 'none');
                } catch (e) { extra = ' (no T&A tables)'; }
                console.log('TENANT OK ' + t.DatabaseName + extra);
            } catch (e) { bad++; console.log('TENANT FAIL ' + t.DatabaseName + ' - ' + e.message); }
            finally { if (tp) { try { await tp.close(); } catch (e) {} } }
        }
        await master.close();
        process.exit(bad ? 2 : 0);
    } catch (e) { console.log('MASTER FAIL ' + e.message); process.exit(1); }
})();
'@ | Set-Content -Path $dbJs -Encoding ASCII
    $dbOut = Native "node `"$dbJs`" `"$AppDir`""
    foreach ($l in ($dbOut -split "`n")) {
        if ($l -like 'MASTER OK*')   { Pass ($l -replace '^MASTER OK ', 'Master database reachable: ') }
        elseif ($l -like 'MASTER FAIL*') { Fail ($l -replace '^MASTER FAIL ', 'Master database: ') }
        elseif ($l -like 'TENANT OK*')   { Pass ($l -replace '^TENANT OK ', 'Tenant ') }
        elseif ($l -like 'TENANT FAIL*') { Fail ($l -replace '^TENANT FAIL ', 'Tenant ') }
    }
    if (-not $dbOut) { Fail "Database check produced no output (node or mssql problem)" }
    Remove-Item $dbJs -ErrorAction SilentlyContinue
} else {
    Warn "Database check skipped (no DB_SERVER in secrets.env or mssql module missing)"
}

# ---------------------------------------------------------------- 7. build integrity
Head "Build integrity (obfuscated scripts)"
if (Test-Path 'public') {
    $scanJs = Join-Path $env:TEMP 'tna_healthcheck_scan.js'
    @'
// Two obfuscated scripts on one page must never share a global helper name.
// The helper names sit in the first few hundred characters of each file.
const fs = require('fs'); const path = require('path');
const PUB = path.join(process.argv[2], 'public');
function resolve(src) { src = src.split('?')[0].replace(/^\//, ''); for (const p of [path.join(PUB, src), path.join(PUB, 'js', src)]) if (fs.existsSync(p)) return p; return null; }
const headNames = {}; let unprefixed = 0, obfuscated = 0;
function names(f) {
    if (headNames[f]) return headNames[f];
    const head = fs.readFileSync(f, 'utf8').slice(0, 600);
    const set = new Set();
    if (/^\s*(const|var|let|function)\s+_/.test(head)) {
        obfuscated++;
        if (!/_[0-9a-f]{6}_0x/.test(head)) unprefixed++;
        for (const m of head.matchAll(/\b(_[0-9a-f]{6}_0x[0-9a-f]+|_0x[0-9a-f]{4,6})\b/g)) set.add(m[1]);
    }
    headNames[f] = set; return set;
}
let collisions = 0;
for (const page of fs.readdirSync(PUB).filter(f => f.endsWith('.html'))) {
    const html = fs.readFileSync(path.join(PUB, page), 'utf8');
    const files = [...html.matchAll(/<script[^>]+src="([^"]+)"/g)].map(m => m[1]).filter(s => !/^https?:/.test(s)).map(resolve).filter(Boolean);
    const owner = {};
    for (const f of files) for (const n of names(f)) {
        if (owner[n] && owner[n] !== f) { collisions++; console.log('COLLISION ' + page + ': ' + n + ' in ' + path.basename(owner[n]) + ' and ' + path.basename(f)); }
        else owner[n] = f;
    }
}
console.log('SUMMARY obfuscated=' + obfuscated + ' unprefixed=' + unprefixed + ' collisions=' + collisions);
'@ | Set-Content -Path $scanJs -Encoding ASCII
    $scanOut = Native "node `"$scanJs`" `"$AppDir`""
    $coll = @($scanOut -split "`n" | Where-Object { $_ -like 'COLLISION*' })
    $sum = ($scanOut -split "`n" | Where-Object { $_ -like 'SUMMARY*' } | Select-Object -First 1)
    if ($coll.Count -gt 0) {
        Fail "$($coll.Count) script name collision(s) - pages will throw 'reading charAt' errors; rebuild those files with the current builder"
        $coll | ForEach-Object { Info ($_ -replace '^COLLISION ', '') }
    } else { Pass "No script name collisions on any page" }
    if ($sum -match 'obfuscated=(\d+) unprefixed=(\d+)') {
        if ([int]$matches[2] -gt 0) { Info "$($matches[2]) of $($matches[1]) obfuscated scripts come from the pre-2026-10-15 builder (no collision guard); a full rebuild will replace them" }
        else { Pass "All $($matches[1]) obfuscated scripts use collision-proof names" }
    }
    Remove-Item $scanJs -ErrorAction SilentlyContinue
} else {
    Warn "public folder not found - build check skipped"
}

# ---------------------------------------------------------------- 8. logs
Head "Recent errors (pm2 error log)"
$shown = $false
foreach ($p in $procs) {
    if (-not ($p.cwd -and $p.cwd.TrimEnd('\').ToLower() -eq $AppDir.TrimEnd('\').ToLower())) { continue }
    $log = $p.errlog
    if ($log -and (Test-Path $log)) {
        $shown = $true
        $tail = Get-Content $log -Tail 300 -ErrorAction SilentlyContinue
        $errs = @($tail | Where-Object { $_ -match 'Error|ECONN|ETIMEDOUT|ENOTFOUND|Invalid column|Cannot read|is not defined|Login failed' })
        $size = [math]::Round(((Get-Item $log).Length / 1MB), 1)
        if ($errs.Count -eq 0) { Pass "$($p.name): no errors in the last 300 log lines (${size}MB)" }
        else {
            Warn "$($p.name): $($errs.Count) error line(s) in the last 300 log lines (${size}MB) - last ones:"
            $errs | Select-Object -Last 6 | ForEach-Object { Info ($_.Substring(0, [Math]::Min(160, $_.Length))) }
        }
        if ($size -gt 500) { Warn "$($p.name): error log is ${size}MB - run: pm2 flush" }
    }
}
if (-not $shown) { Info "No pm2 error log found for this folder" }

# ---------------------------------------------------------------- 9. system
Head "System"
$drive = (Get-Item $AppDir).PSDrive
$freeGB = [math]::Round($drive.Free / 1GB, 1)
if ($freeGB -lt 2) { Fail "Only ${freeGB}GB free on drive $($drive.Name):" } elseif ($freeGB -lt 10) { Warn "${freeGB}GB free on drive $($drive.Name):" } else { Pass "${freeGB}GB free on drive $($drive.Name):" }
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $freeMemGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1); $totMemGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    if ($freeMemGB -lt 1) { Warn "Memory: ${freeMemGB}GB free of ${totMemGB}GB" } else { Pass "Memory: ${freeMemGB}GB free of ${totMemGB}GB" }
    $up = (Get-Date) - $os.LastBootUpTime
    Info "Windows up for $([int]$up.TotalDays) day(s) $($up.Hours)h"
} catch { Info "Memory check unavailable" }

# ---------------------------------------------------------------- summary
Write-Host ""
$colour = 'Green'; if ($script:warn -gt 0) { $colour = 'Yellow' }; if ($script:fail -gt 0) { $colour = 'Red' }
Write-Host "RESULT: $($script:fail) failed, $($script:warn) warning(s)" -ForegroundColor $colour
exit $script:fail
