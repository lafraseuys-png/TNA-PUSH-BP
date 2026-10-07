# Pre-build check: push notifications + this session's app files. Run in the project folder (e.g. C:\Apps\QCApp).
$root = (Get-Location).Path
$ok = 0; $bad = 0; $warn = 0
function Pass($m) { Write-Host "  [OK]   $m" -ForegroundColor Green; $script:ok++ }
function Fail($m) { Write-Host "  [FIX]  $m" -ForegroundColor Red; $script:bad++ }
function Warn($m) { Write-Host "  [?]    $m" -ForegroundColor Yellow; $script:warn++ }
function Has($file, $pattern) { (Test-Path $file) -and (Select-String -Path $file -Pattern $pattern -Quiet) }
Write-Host "`nChecking $root`n"

Write-Host "APP - push plugin"
$pkg = Join-Path $root 'package.json'
if (Has $pkg '"@capacitor/push-notifications"') { Pass 'package.json lists @capacitor/push-notifications' } else { Fail 'package.json has no @capacitor/push-notifications  ->  npm install @capacitor/push-notifications@^8' }
$pn = Join-Path $root 'node_modules\@capacitor\push-notifications\package.json'
if (Test-Path $pn) { $v = (Get-Content $pn -Raw | ConvertFrom-Json).version; $core = Join-Path $root 'node_modules\@capacitor\core\package.json'; $cv = if (Test-Path $core) { (Get-Content $core -Raw | ConvertFrom-Json).version } else { '?' }
    if ($v.Split('.')[0] -eq $cv.Split('.')[0]) { Pass "plugin installed: push-notifications $v (Capacitor core $cv)" } else { Fail "plugin $v does not match Capacitor core $cv  ->  npm install @capacitor/push-notifications@^$($cv.Split('.')[0])" } }
else { Fail 'plugin not in node_modules  ->  npm install @capacitor/push-notifications@^8' }
if (Has (Join-Path $root 'android\capacitor.settings.gradle') 'capacitor-push-notifications') { Pass 'android project includes the plugin (cap sync done)' } else { Fail 'android project does not include the plugin  ->  npx cap sync android' }
if (Has (Join-Path $root 'android\app\capacitor.build.gradle') 'capacitor-push-notifications') { Pass 'app build.gradle uses the plugin' } else { Fail 'app capacitor.build.gradle has no push plugin  ->  npx cap sync android' }

Write-Host "`nAPP - Firebase file"
$gs = Join-Path $root 'android\app\google-services.json'
$gsProject = $null
if (Test-Path $gs) {
    try { $g = Get-Content $gs -Raw | ConvertFrom-Json; $gsProject = $g.project_info.project_id
        $pkgs = @($g.client | ForEach-Object { $_.client_info.android_client_info.package_name })
        if ($pkgs -contains 'com.evofarmer.android') { Pass "google-services.json: project $gsProject, package com.evofarmer.android" } else { Fail "google-services.json is for $($pkgs -join ', ') - not com.evofarmer.android" }
    } catch { Fail 'google-services.json is not valid JSON - download it again' }
} else { Fail 'android\app\google-services.json missing' }
if (Has (Join-Path $root 'android\app\build.gradle') 'applicationId\s+"com\.evofarmer\.android"') { Pass 'applicationId is com.evofarmer.android' } else { Fail 'applicationId in android\app\build.gradle is not com.evofarmer.android' }
if (Has (Join-Path $root 'android\app\build.gradle') 'com\.google\.gms\.google-services') { Pass 'google-services plugin is applied in the build' } else { Fail 'android\app\build.gradle does not apply com.google.gms.google-services' }

Write-Host "`nAPP - Android permissions"
$man = Join-Path $root 'android\app\src\main\AndroidManifest.xml'
foreach ($p in 'POST_NOTIFICATIONS', 'SCHEDULE_EXACT_ALARM', 'RECEIVE_BOOT_COMPLETED') { if (Has $man $p) { Pass "manifest has $p" } else { Fail "manifest is missing $p (pull the latest code)" } }

Write-Host "`nAPP - the new phone files (www and the copy inside the APK)"
$assets = Join-Path $root 'android\app\src\main\assets\public'
foreach ($f in 'push-notifications.js', 'clock-reminder-setup.js', 'clock-reminders.js', 'club-auto-approve.js', 'club-inputs-summary.js', 'category-distribution.js') {
    $w = Join-Path $root "www\$f"; $a = Join-Path $assets $f
    if (-not (Test-Path $w)) { Fail "www\$f missing (pull the latest code)"; continue }
    if (-not (Test-Path $a)) { Fail "$f is not in the APK files yet  ->  npx cap sync android"; continue }
    if ((Get-FileHash $w).Hash -eq (Get-FileHash $a).Hash) { Pass "$f is in the APK files (up to date)" } else { Fail "$f in the APK files is older than www  ->  npx cap sync android" }
}
foreach ($f in 'push-notifications.js', 'clock-reminder-setup.js', 'club-auto-approve.js', 'club-inputs-summary.js') { if (Has (Join-Path $root 'www\index.html') ([regex]::Escape($f))) { Pass "index.html loads $f" } else { Fail "index.html does not load $f (pull the latest code)" } }
$mj = Join-Path $root 'www\mobile.js'
if (Test-Path $mj) { $m = Select-String -Path $mj -Pattern 'APP_BUILD_VERSION\s*=\s*"([^"]+)"' | Select-Object -First 1; if ($m) { Warn "app version will be $($m.Matches[0].Groups[1].Value) - bump it if an APK with this number was already handed out" } }

Write-Host "`nSERVER (only if this folder is also the live server)"
$key = Join-Path $root 'firebase-service-account.json'
if (Test-Path $key) {
    try { $k = Get-Content $key -Raw | ConvertFrom-Json
        if ($k.type -eq 'service_account' -and $k.private_key -match 'BEGIN PRIVATE KEY' -and $k.client_email) { Pass "firebase-service-account.json is a valid key for project $($k.project_id)" } else { Fail 'firebase-service-account.json is not a service-account key - generate a new private key' }
        if ($gsProject -and $k.project_id -ne $gsProject) { Fail "the server key is for $($k.project_id) but the app is for $gsProject - they must be the same project" } elseif ($gsProject) { Pass 'server key and app are the same Firebase project' }
    } catch { Fail 'firebase-service-account.json is not valid JSON (empty?) - generate a new private key' }
} else { Warn 'no firebase-service-account.json next to server.js (fine if the live server is another machine, or FIREBASE_KEY_FILE is set in secrets.env)' }
$envf = Join-Path $root 'secrets.env'
if (Has $envf '^\s*FIREBASE_KEY_FILE\s*=') { $line = (Select-String -Path $envf -Pattern '^\s*FIREBASE_KEY_FILE\s*=\s*(.+)$' | Select-Object -First 1).Matches[0].Groups[1].Value.Trim(); if (Test-Path $line) { Pass "secrets.env points to $line (exists)" } else { Fail "secrets.env points to $line but that file does not exist" } }
foreach ($f in 'utils\fcm.js', 'services\notifScheduler_services.js', 'utils\vendor_qrcode_generator.js', 'logic_login_details.js') { if (Test-Path (Join-Path $root $f)) { Pass "$f present" } else { Fail "$f missing (pull the latest code)" } }
if (Has (Join-Path $root 'server.js') 'notifScheduler_services') { Pass 'server.js starts the notification scheduler' } else { Fail 'server.js does not start the scheduler (pull the latest code)' }
if (Has (Join-Path $root '.gitignore') 'firebase-service-account') { Pass '.gitignore keeps the key out of git' } else { Fail '.gitignore does not exclude firebase-service-account*.json (pull the latest code)' }

Write-Host "`n$ok OK, $bad to fix, $warn to check" -ForegroundColor $(if ($bad) { 'Red' } else { 'Green' })
if (-not $bad) { Write-Host "Ready: build the APK, and restart the server (look for '[FCM] push ready' in the log).`n" -ForegroundColor Green }
