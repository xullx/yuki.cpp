$ErrorActionPreference = "Stop"

$PythonExe    = "C:\Python\Python312\python.exe"
$VoiceScript = "C:\Yuki\src\yuki_voice.py"
$StdinSink   = "C:\Yuki\state\voice-stdin.txt"

$proc = $null


if (!(Test-Path $VoiceScript)) {
    throw "Voice client not found: $VoiceScript"
}


Set-Content `
    -Path $StdinSink `
    -Value "" `
    -Encoding ASCII


try {

    # Python does not own terminal keyboard input.
    $proc = Start-Process `
        $PythonExe `
        -ArgumentList @(
            "-u",
            $VoiceScript
        ) `
        -WorkingDirectory "C:\Yuki\src" `
        -RedirectStandardInput $StdinSink `
        -NoNewWindow `
        -PassThru


    while (!$proc.HasExited) {

        try {

            if ([Console]::KeyAvailable) {

                $key =
                    [Console]::ReadKey($true)


                # Esc is the ONLY way back.
                if (
                    $key.Key -eq
                    [ConsoleKey]::Escape
                ) {

                    Stop-Process `
                        -Id $proc.Id `
                        -Force `
                        -ErrorAction SilentlyContinue

                    break
                }

                # Everything else is ignored.
                # Q has no special meaning.
            }
        }
        catch {
        }


        Start-Sleep `
            -Milliseconds 25


        try {
            $proc.Refresh()
        }
        catch {
            break
        }
    }
}
finally {

    if (
        $proc -and
        !$proc.HasExited
    ) {

        Stop-Process `
            -Id $proc.Id `
            -Force `
            -ErrorAction SilentlyContinue
    }


    try {

        while ([Console]::KeyAvailable) {
            [void][Console]::ReadKey($true)
        }
    }
    catch {
    }
}

