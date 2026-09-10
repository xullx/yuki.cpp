# YUKI.CPP BACKEND ACTION LAYER
# Generated from the old controller.
# No TUI/menu rendering belongs here.

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$AudioExe = "C:\Yuki\bin\audio\llama-liquid-audio-server.exe"

$BrainExe = "C:\Yuki\bin\brain\llama.exe"

$BrainModel = "C:\Yuki\models\brain\LFM2.5-8B-A1B-Q4_K_M.gguf"

$AudioOut = "C:\Yuki\logs\audio-out.log"

$AudioErr = "C:\Yuki\logs\audio-err.log"

$VoiceTTSOut = "C:\Yuki\logs\voice-tts-out.log"
$VoiceTTSErr = "C:\Yuki\logs\voice-tts-err.log"

$TwitchTTSOut = "C:\Yuki\logs\twitch-tts-out.log"
$TwitchTTSErr = "C:\Yuki\logs\twitch-tts-err.log"

$BrainOut = "C:\Yuki\logs\brain-out.log"

$BrainErr = "C:\Yuki\logs\brain-err.log"

$TwitchScript = "C:\Yuki\src\yuki_twitch.py"

$TwitchConfig = "C:\Yuki\config\twitch.json"

$TwitchToken  = "C:\Yuki\config\twitch-token.json"

$TwitchOut = "C:\Yuki\logs\twitch-out.log"

$TwitchErr = "C:\Yuki\logs\twitch-err.log"

$VisualizerScript = "C:\Yuki\src\yuki_visualizer.py"

$VisualizerOut = "C:\Yuki\logs\visualizer-out.log"

$VisualizerErr = "C:\Yuki\logs\visualizer-err.log"

$VisualizerHost = "127.0.0.1"

$VisualizerPort = 8085

$VisualizerUrl = "http://127.0.0.1:8085/"

$YukiConfig   = "C:\Yuki\config\yuki.json"

$PythonExe = (
    & py -c "import sys; print(sys.executable)" 2>$null |
    Select-Object -First 1
)

$JP = "C:\Yuki\models\audio-jp"

$script:audioProc = $null
$script:voiceTtsProc = $null
$script:twitchTtsProc = $null
$script:brainProc = $null
$script:twitchProc = $null
$script:visualizerProc = $null
$script:BrainForceStarting = $false

function Get-AudioState {
    $proc = @(
        Get-CimInstance Win32_Process `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath -ieq $AudioExe -and
            $_.CommandLine -match `
                '(?:^|\s)--port(?:\s+|=)8083(?:\s|$)'
        }
    )

    $listener = Get-NetTCPConnection `
        -State Listen `
        -LocalPort 8083 `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($proc.Count -gt 0 -and $listener) {
        return "ready"
    }

    if ($proc.Count -gt 0) {
        return "starting"
    }

    return "stopped"
}


function Get-BrainState {
    if ($script:BrainForceStarting) {
        return "starting"
    }

    $proc = @(
        Get-CimInstance Win32_Process `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath -ieq $BrainExe -and
            $_.CommandLine -match `
                '(?:^|\s)--port(?:\s+|=)8084(?:\s|$)'
        }
    )

    $listener = Get-NetTCPConnection `
        -State Listen `
        -LocalPort 8084 `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($proc.Count -gt 0 -and $listener) {
        return "ready"
    }

    if ($proc.Count -gt 0) {
        return "starting"
    }

    return "stopped"
}


function Get-TwitchState {
    $proc = @(
        Get-CimInstance Win32_Process `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -like "*$TwitchScript*"
        }
    )

    if ($proc.Count -eq 0) {
        return "stopped"
    }

    if (Test-Path $TwitchOut) {
        $connected = Select-String `
            -Path $TwitchOut `
            -Pattern "Connected\. Chat messages:" `
            -Quiet `
            -ErrorAction SilentlyContinue

        if ($connected) {
            return "ready"
        }
    }

    return "starting"
}


function Get-VisualizerState {

    $proc = @(
        Get-CimInstance Win32_Process `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -like "*$VisualizerScript*"
        }
    )

    $listener = Get-NetTCPConnection `
        -State Listen `
        -LocalPort $VisualizerPort `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($proc.Count -gt 0 -and $listener) {
        return "ready"
    }

    if ($proc.Count -gt 0) {
        return "starting"
    }

    return "stopped"
}

function Wait-PortReady {
    param(
        [int]$Port,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds(
        $TimeoutSeconds
    )

    while ((Get-Date) -lt $deadline) {

        $listener = Get-NetTCPConnection `
            -State Listen `
            -LocalPort $Port `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($listener) {
            break
        }

        Start-Sleep -Milliseconds 250
    }

}


function Wait-TwitchReady {
    param(
        [int]$TimeoutSeconds = 15
    )

    $deadline = (Get-Date).AddSeconds(
        $TimeoutSeconds
    )

    while ((Get-Date) -lt $deadline) {

        if ((Get-TwitchState) -eq "ready") {
            break
        }

        $proc = @(
            Get-CimInstance Win32_Process `
                -ErrorAction SilentlyContinue |
            Where-Object {
                $_.CommandLine -and
                $_.CommandLine -like "*$TwitchScript*"
            }
        )

        if ($proc.Count -eq 0) {
            break
        }

        Start-Sleep -Milliseconds 250
    }

}


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
        Write-Host "[AUDIO] already running PID $($existing.ProcessId)"

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

    Wait-PortReady 8083 45
}


function Get-LiquidAudioPortProcess {

    param(
        [Parameter(Mandatory)]
        [int]$Port
    )

    $PortPattern = (
        '(?:^|\s)--port(?:\s+|=)' +
        [regex]::Escape([string]$Port) +
        '(?:\s|$)'
    )

    return (
        Get-CimInstance Win32_Process `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath -ieq $AudioExe -and
            $_.CommandLine -match $PortPattern
        } |
        Select-Object -First 1
    )
}


function Start-LiquidAudioPort {

    param(
        [Parameter(Mandatory)]
        [int]$Port,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$OutLog,

        [Parameter(Mandatory)]
        [string]$ErrLog
    )


    $Existing =
        Get-LiquidAudioPortProcess `
            -Port $Port


    if ($Existing) {

        Write-Host (
            "[$Name] already running PID " +
            $Existing.ProcessId +
            " on $Port"
        )

        return (
            Get-Process `
                -Id $Existing.ProcessId `
                -ErrorAction SilentlyContinue
        )
    }


    $Listener =
        Get-NetTCPConnection `
            -State Listen `
            -LocalPort $Port `
            -ErrorAction SilentlyContinue |
        Select-Object -First 1


    if ($Listener) {

        Write-Host (
            "[$Name] REFUSED - port $Port belongs to PID " +
            $Listener.OwningProcess
        )

        return $null
    }


    Remove-Item `
        $OutLog,$ErrLog `
        -ErrorAction SilentlyContinue


    $LaunchArgs = @(
        "-m",
        "$JP\LFM2.5-Audio-1.5B-JP-F16.gguf",

        "-mm",
        "$JP\mmproj-LFM2.5-Audio-1.5B-JP-F16.gguf",

        "-mv",
        "$JP\vocoder-LFM2.5-Audio-1.5B-JP-F16.gguf",

        "--tts-speaker-file",
        "$JP\tokenizer-LFM2.5-Audio-1.5B-JP-F16.gguf",

        "-ngl", "99",
        "--mmproj-offload",

        "-t", "32",
        "-tb", "32",

        "--port", [string]$Port
    )


    $Proc = Start-Process `
        -FilePath $AudioExe `
        -ArgumentList $LaunchArgs `
        -WindowStyle Hidden `
        -RedirectStandardOutput $OutLog `
        -RedirectStandardError $ErrLog `
        -PassThru


    Write-Host (
        "[$Name] starting PID " +
        $Proc.Id +
        " on $Port"
    )


    Wait-PortReady `
        $Port `
        45


    $Listener =
        Get-NetTCPConnection `
            -State Listen `
            -LocalPort $Port `
            -ErrorAction SilentlyContinue |
        Select-Object -First 1


    if (!$Listener) {

        Write-Host (
            "[$Name] FAILED - $Port did not become ready"
        )

        return $null
    }


    return $Proc
}


function Stop-LiquidAudioPort {

    param(
        [Parameter(Mandatory)]
        [int]$Port,

        [Parameter(Mandatory)]
        [string]$Name
    )


    $PortPattern = (
        '(?:^|\s)--port(?:\s+|=)' +
        [regex]::Escape([string]$Port) +
        '(?:\s|$)'
    )


    $Processes = @(
        Get-CimInstance Win32_Process `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath -ieq $AudioExe -and
            $_.CommandLine -match $PortPattern
        }
    )


    foreach ($Proc in $Processes) {

        Stop-Process `
            -Id $Proc.ProcessId `
            -Force `
            -ErrorAction SilentlyContinue
    }


    Write-Host "[$Name] stopped"
}


function Start-VoiceTTS {

    $script:voiceTtsProc =
        Start-LiquidAudioPort `
            -Port 8086 `
            -Name "VOICE TTS" `
            -OutLog $VoiceTTSOut `
            -ErrLog $VoiceTTSErr
}


function Start-TwitchTTS {

    $script:twitchTtsProc =
        Start-LiquidAudioPort `
            -Port 8087 `
            -Name "TWITCH TTS" `
            -OutLog $TwitchTTSOut `
            -ErrLog $TwitchTTSErr
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
        Write-Host "[BRAIN] already running PID $($existing.ProcessId)"

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

    Wait-PortReady 8084 45
}


function Start-Twitch {

    if (!(Test-Path $TwitchScript)) {
        Write-Host "[TWITCH] REFUSED - script not found:"
        Write-Host "         $TwitchScript"
        return
    }

    if (!(Test-Path $TwitchConfig)) {
        Write-Host "[TWITCH] REFUSED - twitch.json missing"
        return
    }


    $Existing =
        Get-CimInstance Win32_Process `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -like "*$TwitchScript*"
        } |
        Select-Object -First 1


    # Twitch always owns TTS 8087.
    Start-TwitchTTS


    $TtsReady =
        Get-NetTCPConnection `
            -State Listen `
            -LocalPort 8087 `
            -ErrorAction SilentlyContinue |
        Select-Object -First 1


    if (!$TtsReady) {
        Write-Host "[TWITCH] REFUSED - TTS 8087 is unavailable"
        return
    }


    if ($Existing) {

        $script:twitchProc =
            Get-Process `
                -Id $Existing.ProcessId `
                -ErrorAction SilentlyContinue

        Write-Host (
            "[TWITCH] already running PID " +
            $Existing.ProcessId
        )

        return
    }


    Remove-Item `
        $TwitchOut,$TwitchErr `
        -ErrorAction SilentlyContinue


    # Twitch reasoning still uses the main YUKI brain.
    $env:YUKI_BRAIN_URL =
        "http://127.0.0.1:8084/v1"


    $script:twitchProc =
        Start-Process `
            $PythonExe `
            -ArgumentList @(
                "-u",
                $TwitchScript
            ) `
            -WorkingDirectory "C:\Yuki\src" `
            -WindowStyle Hidden `
            -RedirectStandardOutput $TwitchOut `
            -RedirectStandardError $TwitchErr `
            -PassThru


    Write-Host (
        "[TWITCH] starting PID " +
        $script:twitchProc.Id
    )


    Wait-TwitchReady 15
}


function Stop-Twitch {

    $Processes = @(
        Get-CimInstance Win32_Process `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -like "*$TwitchScript*"
        }
    )


    foreach ($Proc in $Processes) {

        Stop-Process `
            -Id $Proc.ProcessId `
            -Force `
            -ErrorAction SilentlyContinue
    }


    $script:twitchProc = $null


    Stop-LiquidAudioPort `
        -Port 8087 `
        -Name "TWITCH TTS"


    $script:twitchTtsProc = $null


    Write-Host "[TWITCH] stopped"
}


function Start-Visualizer {

    if (!(Test-Path $VisualizerScript)) {
        Write-Host "[VISUALIZER] REFUSED - server script not found:"
        Write-Host "             $VisualizerScript"
        return
    }

    $existing = Get-CimInstance `
        Win32_Process `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -like "*$VisualizerScript*"
        } |
        Select-Object -First 1

    if ($existing) {

        $script:visualizerProc = Get-Process `
            -Id $existing.ProcessId `
            -ErrorAction SilentlyContinue

        Write-Host "[VISUALIZER] already running PID $($existing.ProcessId)"
        return
    }

    $listener = Get-NetTCPConnection `
        -State Listen `
        -LocalPort $VisualizerPort `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($listener) {
        Write-Host "[VISUALIZER] REFUSED - port $VisualizerPort already belongs to PID $($listener.OwningProcess)"
        return
    }

    Remove-Item `
        $VisualizerOut,$VisualizerErr `
        -ErrorAction SilentlyContinue

    $script:visualizerProc = Start-Process `
        $PythonExe `
        -ArgumentList @(
            "-u",
            $VisualizerScript,
            "--host",
            $VisualizerHost,
            "--port",
            "$VisualizerPort"
        ) `
        -WorkingDirectory "C:\Yuki\src" `
        -WindowStyle Hidden `
        -RedirectStandardOutput $VisualizerOut `
        -RedirectStandardError $VisualizerErr `
        -PassThru

    Write-Host "[VISUALIZER] starting PID $($script:visualizerProc.Id)"

    Wait-PortReady `
        $VisualizerPort `
        15
}


function Stop-Visualizer {

    $processes = @(
        Get-CimInstance `
            Win32_Process `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -like "*$VisualizerScript*"
        }
    )

    foreach ($proc in $processes) {

        Stop-Process `
            -Id $proc.ProcessId `
            -Force `
            -ErrorAction SilentlyContinue
    }

    $script:visualizerProc = $null

    Write-Host "[VISUALIZER] stopped"
}


function Open-Visualizer {

    $listener = Get-NetTCPConnection `
        -State Listen `
        -LocalPort $VisualizerPort `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (!$listener) {
        Write-Host "[VISUALIZER] not running on port $VisualizerPort"
        return
    }

    Start-Process $VisualizerUrl

    Write-Host "[VISUALIZER] opened $VisualizerUrl"
}

function Show-Config {
    Write-Host ""
    Write-Host "YUKI.CPP CONFIG"
    Write-Host "-----------------"

    Write-Host ""
    Write-Host "YUKI:"
    Write-Host "  $YukiConfig"

    if (Test-Path $YukiConfig) {
        Get-Content $YukiConfig -Encoding UTF8
    }
    else {
        Write-Host "  MISSING"
    }

    Write-Host ""
    Write-Host "TWITCH:"
    Write-Host "  $TwitchConfig"

    if (Test-Path $TwitchConfig) {
        Get-Content $TwitchConfig -Encoding UTF8
    }
    else {
        Write-Host "  MISSING"
    }

    Write-Host ""
    Write-Host "TWITCH TOKEN:"
    Write-Host "  $TwitchToken"

    if (Test-Path $TwitchToken) {
        $item = Get-Item $TwitchToken

        Write-Host "  Present      : True"
        Write-Host "  Last modified: $($item.LastWriteTime)"
        Write-Host "  Token hidden : True"
    }
    else {
        Write-Host "  Present      : False"
    }

    Write-Host ""
}


function Stop-All {

    Stop-Visualizer
    Stop-Twitch


    Stop-LiquidAudioPort `
        -Port 8086 `
        -Name "VOICE TTS"


    Stop-LiquidAudioPort `
        -Port 8083 `
        -Name "ASR"


    $script:voiceTtsProc = $null
    $script:audioProc = $null


    $Brains = @(
        Get-CimInstance Win32_Process `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath -ieq $BrainExe -and
            $_.CommandLine -match `
                '(?:^|\s)--port(?:\s+|=)8084(?:\s|$)'
        }
    )


    foreach ($Proc in $Brains) {

        Stop-Process `
            -Id $Proc.ProcessId `
            -Force `
            -ErrorAction SilentlyContinue
    }


    $script:brainProc = $null


    Write-Host "[YUKI] all services stopped"
}


function Write-StatusLight {
    param(
        [bool]$Online,
        [string]$Name,
        [string]$Detail
    )

    if ($Online) {
        Write-Host "●" -ForegroundColor Green -NoNewline
    }
    else {
        Write-Host "●" -ForegroundColor Red -NoNewline
    }

    Write-Host " $Name" -NoNewline

    if ($Detail) {
        Write-Host "  $Detail"
    }
    else {
        Write-Host ""
    }
}


function Status {

    Write-Host ""
    Write-Host "YUKI.CPP STATUS"
    Write-Host "-----------------"


    $AsrOnline = [bool](
        Get-NetTCPConnection `
            -State Listen `
            -LocalPort 8083 `
            -ErrorAction SilentlyContinue
    )

    $BrainOnline = [bool](
        Get-NetTCPConnection `
            -State Listen `
            -LocalPort 8084 `
            -ErrorAction SilentlyContinue
    )

    $VisualizerOnline = [bool](
        Get-NetTCPConnection `
            -State Listen `
            -LocalPort $VisualizerPort `
            -ErrorAction SilentlyContinue
    )

    $VoiceTTSOnline = [bool](
        Get-NetTCPConnection `
            -State Listen `
            -LocalPort 8086 `
            -ErrorAction SilentlyContinue
    )

    $TwitchTTSOnline = [bool](
        Get-NetTCPConnection `
            -State Listen `
            -LocalPort 8087 `
            -ErrorAction SilentlyContinue
    )


    $Twitch = @(
        Get-CimInstance Win32_Process `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -like "*$TwitchScript*"
        }
    )


    $TwitchOnline =
        $Twitch.Count -gt 0


    Write-StatusLight `
        $AsrOnline `
        "ASR       " `
        "8083"

    Write-StatusLight `
        $BrainOnline `
        "BRAIN     " `
        "8084"

    Write-StatusLight `
        $VisualizerOnline `
        "VISUALIZER" `
        "$VisualizerPort"

    Write-StatusLight `
        $VoiceTTSOnline `
        "VOICE TTS " `
        "8086"

    Write-StatusLight `
        $TwitchTTSOnline `
        "TWITCH TTS" `
        "8087"

    Write-StatusLight `
        $TwitchOnline `
        "TWITCH    " `
        "reader"


    Write-Host ""

    if ($TwitchOnline) {
        Write-Host (
            "Twitch PID    : " +
            ($Twitch.ProcessId -join ", ")
        )
    }

    Write-Host (
        "Twitch config : " +
        (Test-Path $TwitchConfig)
    )

    Write-Host (
        "Twitch token  : " +
        (Test-Path $TwitchToken)
    )

    Write-Host ""
}


function Set-YukiEchoMode {

    param(
        [ValidateSet("off","brief","full")]
        [string]$Mode
    )

    if (Test-Path $YukiConfig) {

        $raw = Get-Content `
            $YukiConfig `
            -Raw `
            -Encoding UTF8

        if ([string]::IsNullOrWhiteSpace($raw)) {
            $config = [pscustomobject]@{}
        }
        else {
            $config = $raw | ConvertFrom-Json
        }
    }
    else {
        $config = [pscustomobject]@{}
    }


    if ($config.PSObject.Properties["echo_mode"]) {
        $config.echo_mode = $Mode
    }
    else {

        $config |
            Add-Member `
                -NotePropertyName "echo_mode" `
                -NotePropertyValue $Mode
    }


    $config |
        ConvertTo-Json -Depth 100 |
        Set-Content `
            $YukiConfig `
            -Encoding UTF8

    Write-Output "Echo mode: $Mode"
}


function Start-YukiCore {

    Start-Audio
    Start-VoiceTTS
    Start-Brain
}


function Invoke-YukiBackendAction {

    param(
        [Parameter(Mandatory)]
        [string]$Action
    )


    switch ($Action) {

        "visualizer-start" {
            Start-Visualizer
        }


        "visualizer-restart" {

            Stop-Visualizer

            Start-Sleep `
                -Milliseconds 500

            Start-Visualizer
        }


        "visualizer-stop" {
            Stop-Visualizer
        }


        "visualizer-open" {
            Open-Visualizer
        }



        "twitch-start" {
            Start-Twitch
        }


        "twitch-restart" {

            Stop-Twitch

            Start-Sleep `
                -Milliseconds 500

            Start-Twitch
        }


        "twitch-stop" {
            Stop-Twitch
        }


        "status" {
            Status
        }


        "restart-audio" {

            Stop-LiquidAudioPort `
                -Port 8086 `
                -Name "VOICE TTS"

            Stop-LiquidAudioPort `
                -Port 8083 `
                -Name "ASR"


            Start-Sleep `
                -Milliseconds 500


            Start-Audio
            Start-VoiceTTS
        }


        "restart-brain" {

            Get-CimInstance `
                Win32_Process `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.ExecutablePath -and
                    $_.ExecutablePath -ieq $BrainExe
                } |
                ForEach-Object {

                    Stop-Process `
                        -Id $_.ProcessId `
                        -Force `
                        -ErrorAction SilentlyContinue
                }


            Start-Sleep `
                -Milliseconds 500

            Start-Brain
        }


        "stop-all" {
            Stop-All
        }


        "echo-off" {
            Set-YukiEchoMode "off"
        }


        "echo-brief" {
            Set-YukiEchoMode "brief"
        }


        "echo-full" {
            Set-YukiEchoMode "full"
        }


        "config-yuki" {

            if (Test-Path $YukiConfig) {

                Get-Content `
                    $YukiConfig `
                    -Raw `
                    -Encoding UTF8
            }
            else {
                Write-Output "YUKI config not found."
            }
        }


        "config-twitch" {

            if (Test-Path $TwitchConfig) {

                Get-Content `
                    $TwitchConfig `
                    -Raw `
                    -Encoding UTF8
            }
            else {
                Write-Output "Twitch config not found."
            }
        }


        "tts-test" {

            $testScript = "C:\Yuki\tools\tts_test.py"

            if (!(Test-Path $testScript)) {
                throw "TTS test not found: $testScript"
            }

            & $PythonExe `
                $testScript
        }


        default {
            throw "Unknown backend action: $Action"
        }
    }


    return [pscustomobject]@{
        Kind   = "complete"
        Target = $Action
    }
}
