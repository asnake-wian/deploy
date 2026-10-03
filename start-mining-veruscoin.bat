@echo off
cd %~dp0
cls

:: Check if SRBMiner-MULTI.exe is already running
tasklist /FI "IMAGENAME eq SRBMiner-MULTI.exe" 2>NUL | find /I "SRBMiner-MULTI.exe" > NUL

:: If it is running, skip starting the miner
if %ERRORLEVEL%==0 (
    echo SRBMiner-MULTI is already running. Skipping startup.
) else (
    echo SRBMiner-MULTI is not running. Starting the miner.
    :: Update the worker name
    set workerName=%1

    if "%workerName%"=="" (
        set workerName=default_worker
    )

    :: Run the miner with CPU mining for Xelis
    start "" /min SRBMiner-MULTI.exe --algorithm-cpu xelishashv3 --pool stratum+tcp://de.vipor.net:5077 --wallet xel:46946gqfd5p5cuyn9wzqgte8ukuefezk0k2ks9yrvywxvjzd4dssq24x33l --password Null@1@2 --cpu-threads 3 --cpu-threads-priority 1 --cpu-threads-intensity 4 --disable-gpu --worker %COMPUTERNAME% --log-file log.txt --log-file-mode 1 --background
)

:: End the batch script
exit
