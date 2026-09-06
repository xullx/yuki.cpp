chcp.com 65001 > $null
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding           = [System.Text.UTF8Encoding]::new($false)
$Host.UI.RawUI.WindowTitle = "YUKI.CPP CONTROL"

$AudioExe = "C:\Yuki\bin\audio\llama-liquid-audio-server.exe"
$BrainExe = "C:\Yuki\bin\brain\llama.exe"

$JP = "C:\Yuki\models\audio-jp"
$BrainModel = "C:\Yuki\models\brain\LFM2.5-8B-A1B-Q4_K_M.gguf"

$AudioOut = "C:\Yuki\logs\audio-out.log"
$AudioErr = "C:\Yuki\logs\audio-err.log"
$BrainOut = "C:\Yuki\logs\brain-out.log"
$BrainErr = "C:\Yuki\logs\brain-err.log"

$audioProc = $null
$brainProc = $null


function Start-Audio {
    # Find an existing YUKI audio server, even if it has not bound the port yet.
    $existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath -ieq $AudioExe -and
            $_.CommandLine -match '(?:^|\s)--port(?:\s+|=)8083(?:\s|$)'
        } |
        Select-Object -First 1

    if ($existing) {
        $script:audioProc = Get-Process -Id $existing.ProcessId -ErrorAction SilentlyContinue
        Write-Host "[AUDIO] adopting existing PID $($existing.ProcessId)"
        return
    }

    # Refuse to collide with anything else already listening on 8083.
    $listener = Get-NetTCPConnection -State Listen -LocalPort 8083 -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($listener) {
        Write-Host "[AUDIO] REFUSED - port 8083 already belongs to PID $($listener.OwningProcess)"
        return
    }

    Remove-Item $AudioOut,$AudioErr -ErrorAction SilentlyContinue

    $args = @(
        "-m", "$JP\LFM2.5-Audio-1.5B-JP-F16.gguf",
        "-mm", "$JP\mmproj-LFM2.5-Audio-1.5B-JP-F16.gguf",
        "-mv", "$JP\vocoder-LFM2.5-Audio-1.5B-JP-F16.gguf",
        "--tts-speaker-file", "$JP\tokenizer-LFM2.5-Audio-1.5B-JP-F16.gguf",
        "-ngl", "99",
        "--mmproj-offload",
        "-t", "32",
        "-tb", "32",
        "--port", "8083"
    )

    $script:audioProc = Start-Process `
        $AudioExe `
        -ArgumentList $args `
        -WindowStyle Hidden `
        -RedirectStandardOutput $AudioOut `
        -RedirectStandardError $AudioErr `
        -PassThru

    Write-Host "[AUDIO] starting PID $($audioProc.Id)"
}


function Start-Brain {
    # Find an existing YUKI brain server, even if it has not bound the port yet.
    $existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath -ieq $BrainExe -and
            $_.CommandLine -match '(?:^|\s)--port(?:\s+|=)8084(?:\s|$)'
        } |
        Select-Object -First 1

    if ($existing) {
        $script:brainProc = Get-Process -Id $existing.ProcessId -ErrorAction SilentlyContinue
        Write-Host "[BRAIN] adopting existing PID $($existing.ProcessId)"
        return
    }

    # Refuse to collide with anything else already listening on 8084.
    $listener = Get-NetTCPConnection -State Listen -LocalPort 8084 -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($listener) {
        Write-Host "[BRAIN] REFUSED - port 8084 already belongs to PID $($listener.OwningProcess)"
        return
    }

    Remove-Item $BrainOut,$BrainErr -ErrorAction SilentlyContinue

    $args = @(
        "serve",
        "-m", $BrainModel,
        "-ngl", "99",
        "-t", "32",
        "-tb", "32",
        "-c", "4096",
        "-np", "1",
        "--port", "8084"
    )

    $script:brainProc = Start-Process `
        $BrainExe `
        -ArgumentList $args `
        -WorkingDirectory "C:\Yuki\bin\brain" `
        -WindowStyle Hidden `
        -RedirectStandardOutput $BrainOut `
        -RedirectStandardError $BrainErr `
        -PassThru

    Write-Host "[BRAIN] starting PID $($brainProc.Id)"
}


function Stop-All {
    if ($audioProc -and !$audioProc.HasExited) {
        Stop-Process -Id $audioProc.Id -Force
    }

    if ($brainProc -and !$brainProc.HasExited) {
        Stop-Process -Id $brainProc.Id -Force
    }

    Write-Host "[YUKI] servers stopped"
}


function Status {
    Write-Host ""
    Write-Host "YUKI.CPP STATUS"
    Write-Host "-----------------"

    foreach ($port in 8083,8084) {
        $ok = Test-NetConnection 127.0.0.1 -Port $port `
            -WarningAction SilentlyContinue

        Write-Host "Port $port : $($ok.TcpTestSucceeded)"
    }

    $audio = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath -ieq $AudioExe -and
            $_.CommandLine -match '(?:^|\s)--port(?:\s+|=)8083(?:\s|$)'
        })

    $brain = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath -ieq $BrainExe -and
            $_.CommandLine -match '(?:^|\s)--port(?:\s+|=)8084(?:\s|$)'
        })

    Write-Host "Audio processes : $($audio.Count)  PID(s): $($audio.ProcessId -join ', ')"
    Write-Host "Brain processes : $($brain.Count)  PID(s): $($brain.ProcessId -join ', ')"

    if ($audio.Count -gt 1 -or $brain.Count -gt 1) {
        Write-Host "WARNING: duplicate YUKI server detected"
    }

    Write-Host ""
}


Start-Audio
Start-Brain

Write-Host ""
Write-Host "YUKI.CPP CONTROL"
Write-Host "=================="
Write-Host "bridge         = start YUKI voice assistant"
Write-Host "text           = start YUKI text chat"
Write-Host "echo-off       = no spoken confirmation"
Write-Host "echo-brief     = brief confirmation"
Write-Host "echo-full      = repeat ASR transcript"
Write-Host "echo-status    = show current echo mode"
Write-Host "tts-test       = test fresh Japanese TTS"
Write-Host "audio          = last audio log"
Write-Host "brain          = last brain log"
Write-Host "status         = server status"
Write-Host "restart-audio  = restart 8083"
Write-Host "restart-brain  = restart 8084"
Write-Host "stop           = stop both"
Write-Host "quit           = stop both and exit"
Write-Host ""

while ($true) {
    $cmd = (Read-Host "YUKI").Trim().ToLower()

    switch ($cmd) {

        "echo-off" {
            '{"echo_mode":"off"}' | Set-Content "C:\Yuki\config\yuki.json" -Encoding UTF8
            Write-Host "[ECHO] off"
        }

        "echo-brief" {
            '{"echo_mode":"brief"}' | Set-Content "C:\Yuki\config\yuki.json" -Encoding UTF8
            Write-Host "[ECHO] brief"
        }

        "echo-full" {
            '{"echo_mode":"full"}' | Set-Content "C:\Yuki\config\yuki.json" -Encoding UTF8
            Write-Host "[ECHO] full"
        }

        "echo-status" {
            $cfg = Get-Content "C:\Yuki\config\yuki.json" -Raw | ConvertFrom-Json
            Write-Host "[ECHO] $($cfg.echo_mode)"
        }

        "bridge" {
            py "C:\Yuki\app\yuki_bridge.py"
        }

        "text" {
            py "C:\Yuki\app\yuki_text.py"
        }

        "tts-test" {
            py "C:\Yuki\app\tts_test.py"
        }

        "audio" {
            Get-Content $AudioErr -Encoding UTF8 -Tail 30 -ErrorAction SilentlyContinue
            Get-Content $AudioOut -Encoding UTF8 -Tail 30 -ErrorAction SilentlyContinue
        }

        "brain" {
            Get-Content $BrainErr -Encoding UTF8 -Tail 30 -ErrorAction SilentlyContinue
            Get-Content $BrainOut -Encoding UTF8 -Tail 30 -ErrorAction SilentlyContinue
        }

        "status" {
            Status
        }

        "restart-audio" {
            if ($audioProc -and !$audioProc.HasExited) {
                Stop-Process $audioProc.Id -Force
            }
            Start-Sleep 1
            Start-Audio
        }

        "restart-brain" {
            if ($brainProc -and !$brainProc.HasExited) {
                Stop-Process $brainProc.Id -Force
            }
            Start-Sleep 1
            Start-Brain
        }

        "stop" {
            Stop-All
        }

        "quit" {
            Stop-All
            return
        }

        default {
            Write-Host "Unknown command."
        }
    }
}









