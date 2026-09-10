$statusProfile = "YUKI STATUS"
$control = "C:\Yuki\launch\yuki-control-pane.ps1"

if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
    throw "Windows Terminal wt.exe not found."
}

function Show-Help {
    Write-Host ""
    Write-Host "YUKI TERMINAL"
    Write-Host "============="
    Write-Host "help = show this help"
    Write-Host ""
}

if ($args.Count -gt 0 -and $args[0] -eq "help") {
    Show-Help
    return
}

if ($env:WT_SESSION) {
    $windowTarget = "0"
}
else {
    $windowTarget = "new"
}

& wt.exe `
    -w $windowTarget `
    new-tab `
    -p $statusProfile `
    --title "YUKI.CPP" `
    --suppressApplicationTitle `
    `; split-pane `
    -H `
    --size 0.88 `
    --title "YUKI CONTROL" `
    --suppressApplicationTitle `
    pwsh.exe -NoLogo -NoExit -File $control
