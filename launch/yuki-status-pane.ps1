$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

chcp.com 65001 > $null

[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding           = [System.Text.UTF8Encoding]::new($false)

$Host.UI.RawUI.WindowTitle = "YUKI STATUS"

$AudioExe     = "C:\Yuki\bin\audio\llama-liquid-audio-server.exe"
$BrainExe     = "C:\Yuki\bin\brain\llama.exe"
$TwitchScript = "C:\Yuki\src\yuki_twitch.py"
$TwitchOut    = "C:\Yuki\logs\twitch-out.log"

$ModeFile = "C:\Yuki\state\mode.txt"

$esc = [char]27

# RX 6800 physical VRAM.
$VramTotalGB = 16.0

$script:LastGpuUpdate = [datetime]::MinValue
$script:CachedGpu = $null

$script:LastAudioState  = "stopped"
$script:LastBrainState  = "stopped"
$script:LastTwitchState = "stopped"

$script:AudioGraceUntil  = [datetime]::MinValue
$script:BrainGraceUntil  = [datetime]::MinValue
$script:TwitchGraceUntil = [datetime]::MinValue


function Get-AudioRawState {
    $proc = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath -ieq $AudioExe
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


function Get-BrainRawState {
    $proc = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
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


function Get-TwitchRawState {
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


function Apply-RestartGrace {
    param(
        [string]$Name,
        [string]$Current,
        [string]$Previous
    )

    $now = Get-Date

    switch ($Name) {
        "audio" {
            if ($Previous -eq "ready" -and $Current -eq "stopped") {
                $script:AudioGraceUntil = $now.AddSeconds(8)
            }

            if (
                $Current -eq "stopped" -and
                $now -lt $script:AudioGraceUntil
            ) {
                return "starting"
            }
        }

        "brain" {
            if ($Previous -eq "ready" -and $Current -eq "stopped") {
                $script:BrainGraceUntil = $now.AddSeconds(8)
            }

            if (
                $Current -eq "stopped" -and
                $now -lt $script:BrainGraceUntil
            ) {
                return "starting"
            }
        }

        "twitch" {
            if ($Previous -eq "ready" -and $Current -eq "stopped") {
                $script:TwitchGraceUntil = $now.AddSeconds(8)
            }

            if (
                $Current -eq "stopped" -and
                $now -lt $script:TwitchGraceUntil
            ) {
                return "starting"
            }
        }
    }

    return $Current
}


function Get-GpuStats {
    $now = Get-Date

    if (
        $script:CachedGpu -and
        ($now - $script:LastGpuUpdate).TotalSeconds -lt 2
    ) {
        return $script:CachedGpu
    }

    $name = "RX 6800"
    $usage = 0
    $vramUsed = 0.0

    try {
        $gpu = Get-CimInstance Win32_VideoController |
            Where-Object {
                $_.Name -match "RX\s*6800|Radeon.*6800"
            } |
            Select-Object -First 1

        if ($gpu) {
            $name = (
                $gpu.Name `
                -replace '^AMD Radeon\s*', '' `
                -replace '^Radeon\s*', ''
            )
        }
    }
    catch {}


    # Windows GPU engine counters.
    try {
        $samples = (
            Get-Counter `
                '\GPU Engine(*)\Utilization Percentage' `
                -ErrorAction Stop
        ).CounterSamples

        $threeD = @(
            $samples |
            Where-Object {
                $_.InstanceName -match 'engtype_3D'
            }
        )

        if ($threeD.Count -eq 0) {
            $threeD = @($samples)
        }

        $sum = (
            $threeD |
            Measure-Object `
                -Property CookedValue `
                -Sum
        ).Sum

        if ($null -ne $sum) {
            $usage = [Math]::Round(
                [Math]::Min(
                    100,
                    [Math]::Max(0, $sum)
                )
            )
        }
    }
    catch {}


    # Dedicated GPU memory currently allocated.
    try {
        $mem = (
            Get-Counter `
                '\GPU Adapter Memory(*)\Dedicated Usage' `
                -ErrorAction Stop
        ).CounterSamples

        $maxBytes = (
            $mem |
            Measure-Object `
                -Property CookedValue `
                -Maximum
        ).Maximum

        if ($null -ne $maxBytes) {
            $vramUsed = [Math]::Round(
                $maxBytes / 1GB,
                1
            )
        }
    }
    catch {}


    $script:CachedGpu = [PSCustomObject]@{
        Name     = $name
        Usage    = [int]$usage
        VramUsed = $vramUsed
    }

    $script:LastGpuUpdate = $now

    return $script:CachedGpu
}


function Get-Bar {
    param(
        [int]$Percent,
        [int]$Width = 8
    )

    $filled = [Math]::Round(
        ($Percent / 100.0) * $Width
    )

    $filled = [Math]::Max(
        0,
        [Math]::Min($Width, $filled)
    )

    return (
        ("█" * $filled) +
        ("░" * ($Width - $filled))
    )
}


function Get-StateText {
    param(
        [string]$State,
        [string]$ReadyText,
        [string]$StartingText = "STARTING",
        [string]$StoppedText = "STOPPED",

        [ValidateSet("red","dim")]
        [string]$StoppedColor = "red"
    )

    $reset  = "$esc[0m"
    $green  = "$esc[92m"
    $yellow = "$esc[93m"
    $red    = "$esc[91m"
    $dim    = "$esc[90m"

    switch ($State) {

        "ready" {
            return "${green}${ReadyText}${reset}"
        }

        "starting" {
            return "${yellow}${StartingText}${reset}"
        }

        default {

            if ($StoppedColor -eq "dim") {
                return "${dim}${StoppedText}${reset}"
            }

            return "${red}${StoppedText}${reset}"
        }
    }
}


function Get-OverallDot {
    param(
        [string[]]$CoreStates
    )

    $reset  = "$esc[0m"
    $green  = "$esc[92m"
    $yellow = "$esc[93m"
    $red    = "$esc[91m"


    if ($CoreStates -contains "stopped") {
        return "$red●$reset"
    }


    if ($CoreStates -contains "starting") {
        return "$yellow●$reset"
    }


    return "$green●$reset"
}


# Dedicated pane: cursor isn't useful.
Write-Host "$esc[?25l" -NoNewline

try {
    while ($true) {

        $audioRaw  = Get-AudioRawState
        $brainRaw  = Get-BrainRawState
        $twitchRaw = Get-TwitchRawState

        $audio = Apply-RestartGrace `
            "audio" `
            $audioRaw `
            $script:LastAudioState

        $brain = Apply-RestartGrace `
            "brain" `
            $brainRaw `
            $script:LastBrainState

        $twitch = Apply-RestartGrace `
            "twitch" `
            $twitchRaw `
            $script:LastTwitchState

        $script:LastAudioState  = $audioRaw
        $script:LastBrainState  = $brainRaw
        $script:LastTwitchState = $twitchRaw

        $gpu = Get-GpuStats
        $bar = Get-Bar $gpu.Usage 8

        $overall = Get-OverallDot `
            -CoreStates @(
                $audio,
                $brain
            )

        $audioText = Get-StateText `
            $audio `
            "READY"

        $brainText = Get-StateText `
            $brain `
            "READY"

        $twitchText = Get-StateText `
            -State $twitch `
            -ReadyText "CONNECTED" `
            -StartingText "CONNECTING" `
            -StoppedText "OFF" `
            -StoppedColor "dim"

        $cyan = "$esc[96m"
        $dim  = "$esc[90m"
        $reset = "$esc[0m"

        # YUKI MODE STATE
        $mode = "CONTROL"

        if (Test-Path $ModeFile) {

            $modeText = Get-Content `
                $ModeFile `
                -Raw `
                -ErrorAction SilentlyContinue

            if ($modeText) {
                $mode = (
                    $modeText.Trim().ToUpperInvariant()
                )
            }
        }

        $line1 = (
            "${cyan}YUKI${reset}  $overall" +
            "    " +
            "${dim}MODE${reset} " +
            "${cyan}$mode${reset}"
        )

        $line2 = (
            "AUDIO $audioText ${dim}8083${reset}" +
            "    " +
            "BRAIN $brainText ${dim}8084${reset}" +
            "    " +
            "TWITCH $twitchText"
        )

        $line3 = (
            "GPU $($gpu.Name)  " +
            "$cyan$bar$reset " +
            "$($gpu.Usage)%" +
            "    " +
            "VRAM $($gpu.VramUsed) / $VramTotalGB GB"
        )

        # Redraw only this tiny dedicated pane.
        Write-Host `
            "$esc[H$esc[2K$line1" `
            -NoNewline

        Write-Host `
            "`n$esc[2K$line2" `
            -NoNewline

        Write-Host `
            "`n$esc[2K$line3" `
            -NoNewline

        Start-Sleep -Milliseconds 500
    }
}
finally {
    Write-Host "$esc[?25h" -NoNewline
}
