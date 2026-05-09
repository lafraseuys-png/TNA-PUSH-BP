<#
.SYNOPSIS
    TNA Africa SaaS Comprehensive Diagnostic & Debugger Tool
.DESCRIPTION
    A command-line interface to test Node.js ports, decode JWT tokens,
    verify MSSQL connectivity, and execute API endpoints directly.
#>

$ErrorActionPreference = "Stop"
Clear-Host

function Show-Menu {
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "    TNA Africa SaaS Diagnostic Tool       " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "1. Test Node.js Ports (3033, 3034)"
    Write-Host "2. Decode a JWT Token"
    Write-Host "3. Test MSSQL Database Connection"
    Write-Host "4. Test API Endpoint (GET/POST)"
    Write-Host "Q. Quit"
    Write-Host "------------------------------------------"
}

function Test-Ports {
    Write-Host "`nTesting standard SaaS ports..." -ForegroundColor Yellow
    $ports = @(3033, 3034, 8080, 8098)
    foreach ($port in $ports) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.Connect("127.0.0.1", $port)
            Write-Host "[OK] Port $port is LISTENING" -ForegroundColor Green
            $tcp.Close()
        } catch {
            Write-Host "[FAIL] Port $port is OFFLINE" -ForegroundColor Red
        }
    }
    Write-Host "Press any key to return..." ; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Decode-JWT {
    $token = Read-Host "`nPaste the JWT Token to decode"
    if ([string]::IsNullOrWhiteSpace($token)) { return }
    
    try {
        $parts = $token.Split('.')
        if ($parts.Length -ne 3) { throw "Invalid JWT format" }
        
        # Add padding if needed
        $payload = $parts[1]
        $pad = $payload.Length % 4
        if ($pad -ne 0) { $payload += '=' * (4 - $pad) }
        
        $decodedBytes = [System.Convert]::FromBase64String($payload)
        $decodedJson = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
        $obj = $decodedJson | ConvertFrom-Json
        
        Write-Host "`n--- TOKEN PAYLOAD ---" -ForegroundColor Cyan
        $obj | Format-List | Out-String | Write-Host
        
        if ($obj.exp) {
            $expiryDate = (New-Object System.DateTime(1970, 1, 1, 0, 0, 0, 0, [System.DateTimeKind]::Utc)).AddSeconds($obj.exp).ToLocalTime()
            $isExpired = $expiryDate -lt (Get-Date)
            Write-Host "Expiration Date: $expiryDate"
            if ($isExpired) { Write-Host "STATUS: EXPIRED" -ForegroundColor Red }
            else { Write-Host "STATUS: VALID" -ForegroundColor Green }
        }
    } catch {
        Write-Host "[ERROR] Failed to decode token: $_" -ForegroundColor Red
    }
    Write-Host "`nPress any key to return..." ; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Test-SQLConnection {
    $server = Read-Host "`nEnter SQL Server (default: localhost)"
    if ([string]::IsNullOrWhiteSpace($server)) { $server = "localhost" }
    
    $user = Read-Host "Enter DB User (default: sa)"
    if ([string]::IsNullOrWhiteSpace($user)) { $user = "sa" }
    
    $pass = Read-Host -AsSecureString "Enter DB Password"
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    
    $connString = "Server=$server;User Id=$user;Password=$password;TrustServerCertificate=True"
    
    Write-Host "`nAttempting to connect to Master Database..." -ForegroundColor Yellow
    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection($connString)
        $conn.Open()
        Write-Host "[OK] Connection Successful!" -ForegroundColor Green
        
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb')"
        $reader = $cmd.ExecuteReader()
        Write-Host "`nFound SaaS Tenant Databases:" -ForegroundColor Cyan
        while ($reader.Read()) { Write-Host " - " $reader["name"] }
        
        $conn.Close()
    } catch {
        Write-Host "[FAIL] SQL Connection Error: $_" -ForegroundColor Red
    }
    Write-Host "`nPress any key to return..." ; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Test-API {
    $url = Read-Host "`nEnter full API URL (e.g. http://localhost:3034/api/assets)"
    $method = Read-Host "Enter Method (GET/POST)"
    $token = Read-Host "Enter JWT Token (Leave blank for no auth)"
    
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($token)) {
        $headers.Add("Authorization", "Bearer $token")
    }

    try {
        Write-Host "`nExecuting $method request to $url..." -ForegroundColor Yellow
        if ($method.ToUpper() -eq "POST") {
            $body = Read-Host "Enter JSON body (e.g. {'categoryName':'Test'})"
            $headers.Add("Content-Type", "application/json")
            $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
        } else {
            $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        }
        
        Write-Host "`n[OK] API Response:" -ForegroundColor Green
        $response | ConvertTo-Json -Depth 3 | Write-Host
    } catch {
        Write-Host "`n[FAIL] Request Failed." -ForegroundColor Red
        Write-Host $_.Exception.Message
        if ($_.ErrorDetails.Message) { Write-Host "Details: " $_.ErrorDetails.Message }
    }
    Write-Host "`nPress any key to return..." ; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Main Loop
while ($true) {
    Show-Menu
    $selection = Read-Host "Select an option"
    switch ($selection) {
        '1' { Test-Ports }
        '2' { Decode-JWT }
        '3' { Test-SQLConnection }
        '4' { Test-API }
        'Q' { Exit }
        'q' { Exit }
        default { Write-Host "Invalid selection" -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
    Clear-Host
}