$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ============================================================
# YUKI.CPP CONTROLLER
#
# Responsibilities:
#   - read menu/action definitions from JSON
#   - maintain menu state
#   - handle keyboard navigation
#   - render complete screens
#   - dispatch actions
#
# It does NOT contain:
#   - service implementations
#   - Voice implementation
#   - Text implementation
#   - hard-coded menu/submenu definitions
# ============================================================


$MenuPath    = "C:\Yuki\config\controller-menu.json"
$ActionsPath = "C:\Yuki\launch\yuki-actions.ps1"
$ModeFile    = "C:\Yuki\state\mode.txt"

$esc = [char]27


# ============================================================
# UTF-8
#
# Prevent ◇ ◆ ○ etc. becoming ?
# ============================================================

$Utf8 = [System.Text.UTF8Encoding]::new($false)

[Console]::OutputEncoding = $Utf8
$OutputEncoding = $Utf8


# ============================================================
# ACTION LAYER
# ============================================================

if (!(Test-Path $ActionsPath)) {
    throw "YUKI action layer missing: $ActionsPath"
}

. $ActionsPath


# ============================================================
# MODE STATE
# ============================================================

function Set-YukiMode {

    param(
        [ValidateSet(
            "CONTROL",
            "TEXT",
            "VOICE"
        )]
        [string]$Mode
    )

    $dir = Split-Path $ModeFile -Parent

    if (!(Test-Path $dir)) {
        New-Item `
            -ItemType Directory `
            -Force `
            -Path $dir |
            Out-Null
    }

    Set-Content `
        -Path $ModeFile `
        -Value $Mode `
        -Encoding ASCII
}


# ============================================================
# JSON
# ============================================================

function Get-YukiConfig {

    if (!(Test-Path $MenuPath)) {
        throw "Controller menu JSON missing: $MenuPath"
    }

    try {

        return (
            Get-Content `
                -Path $MenuPath `
                -Raw `
                -Encoding UTF8 |
            ConvertFrom-Json
        )
    }
    catch {

        throw (
            "Could not read controller JSON: " +
            $_.Exception.Message
        )
    }
}


function Get-YukiMenu {

    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $property =
        $Config.menus.PSObject.Properties[$Name]

    if (!$property) {
        throw "Unknown menu: $Name"
    }

    return $property.Value
}


function Get-YukiAction {

    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $property =
        $Config.actions.PSObject.Properties[$Name]

    if (!$property) {
        throw "Unknown action: $Name"
    }

    return $property.Value
}


function Test-YukiConfig {

    param(
        [Parameter(Mandatory)]
        [object]$Config
    )


    # --------------------------------------------------------
    # Root
    # --------------------------------------------------------

    if (!$Config.root) {
        throw "controller-menu.json has no root menu."
    }

    $rootName = [string]$Config.root

    if (
        !$Config.menus.PSObject.Properties[$rootName]
    ) {
        throw "Root menu does not exist: $rootName"
    }


    # --------------------------------------------------------
    # Menus
    # --------------------------------------------------------

    foreach (
        $menuProperty in
        $Config.menus.PSObject.Properties
    ) {

        $menuName = [string]$menuProperty.Name
        $menu     = $menuProperty.Value


        if (!$menu.title) {
            throw "Menu '$menuName' has no title."
        }


        foreach ($item in @($menu.items)) {

            $type   = [string]$item.type
            $target = [string]$item.target


            switch ($type) {

                "menu" {

                    if (
                        !$Config.menus.
                            PSObject.
                            Properties[$target]
                    ) {

                        throw (
                            "Menu '$menuName' references " +
                            "missing submenu '$target'."
                        )
                    }
                }


                "action" {

                    if (
                        !$Config.actions.
                            PSObject.
                            Properties[$target]
                    ) {

                        throw (
                            "Menu '$menuName' references " +
                            "missing action '$target'."
                        )
                    }
                }


                "help" {
                }


                "quit" {

                    if ($menuName -ne $rootName) {

                        throw (
                            "Quit may only exist in the " +
                            "root menu. Found in '$menuName'."
                        )
                    }
                }


                default {

                    throw (
                        "Unknown item type '$type' " +
                        "in menu '$menuName'."
                    )
                }
            }
        }
    }


    # --------------------------------------------------------
    # Actions
    # --------------------------------------------------------

    foreach (
        $actionProperty in
        $Config.actions.PSObject.Properties
    ) {

        $actionName = [string]$actionProperty.Name
        $action     = $actionProperty.Value
        $kind       = [string]$action.kind


        switch ($kind) {

            "mode" {

                if (!$action.runner) {

                    throw (
                        "Mode action '$actionName' " +
                        "has no runner."
                    )
                }

                if (!$action.mode) {

                    throw (
                        "Mode action '$actionName' " +
                        "has no mode."
                    )
                }

                if (
                    @("TEXT","VOICE") -notcontains
                    ([string]$action.mode)
                ) {

                    throw (
                        "Invalid mode '$($action.mode)' " +
                        "for action '$actionName'."
                    )
                }
            }


            "log" {

                if (
                    !$action.title -or
                    !$action.paths
                ) {

                    throw (
                        "Log action '$actionName' " +
                        "is incomplete."
                    )
                }
            }


            "backend" {

                if (!$action.target) {

                    throw (
                        "Backend action '$actionName' " +
                        "has no target."
                    )
                }
            }


            default {

                throw (
                    "Unknown action kind '$kind' " +
                    "for '$actionName'."
                )
            }
        }
    }
}


# ============================================================
# INPUT
#
# Controller policy:
#
#   ↑ ↓       navigate
#   Enter     select
#   Esc       ONLY back key
#   H         help
#
#   Q         nothing special
#   ←         nothing special
#   Ctrl+C    nothing special
#
# Quit occurs ONLY through root-menu Quit.
# ============================================================

function Read-YukiKey {

    $key = [Console]::ReadKey($true)


    switch ($key.Key) {

        "UpArrow" {
            return "UP"
        }


        "DownArrow" {
            return "DOWN"
        }


        "PageUp" {
            return "PAGEUP"
        }


        "PageDown" {
            return "PAGEDOWN"
        }


        "Home" {
            return "HOME"
        }


        "End" {
            return "END"
        }


        "Escape" {
            return "BACK"
        }


        "Enter" {
            return "ENTER"
        }
    }


    # H is the only letter with controller meaning.
    # Q deliberately has no meaning.

    if (
        $key.KeyChar.ToString().
            ToLowerInvariant() -eq "h"
    ) {
        return "HELP"
    }


    return "NONE"
}


# ============================================================
# RENDERER
#
# Deliberately simple:
#
# 1. Build COMPLETE frame in memory.
# 2. Move cursor HOME.
# 3. Write COMPLETE frame ONCE.
# 4. Clear remainder of each line.
# 5. Clear anything below frame.
#
# No LastFrame.
# No SetCursorPosition.
# No differential repainting.
# ============================================================

function Write-YukiScreen {

    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Lines,

        [switch]$ClearFirst
    )


    $builder =
        [System.Text.StringBuilder]::new()


    if ($ClearFirst) {

        [void]$builder.Append(
            "$esc[2J$esc[H"
        )
    }
    else {

        [void]$builder.Append(
            "$esc[H"
        )
    }


    foreach ($line in @($Lines)) {

        [void]$builder.Append(
            [string]$line
        )

        # Clear anything left from the previous frame
        # on this physical terminal row.
        [void]$builder.Append(
            "$esc[K"
        )

        [void]$builder.Append(
            "`r`n"
        )
    }


    # Clear any old rows below the new frame.
    [void]$builder.Append(
        "$esc[J"
    )


    # ONE console write per frame.
    [Console]::Write(
        $builder.ToString()
    )
}


# ============================================================
# CANONICAL MENU FOOTER
# ============================================================

function Get-YukiFooter {

    param(
        [ValidateSet("Menu","Session")]
        [string]$Context
    )

    switch ($Context) {

        "Menu" {

            return (
                "$esc[90m↑/↓ navigate" +
                "  •  Enter confirm" +
                "  •  Esc back" +
                "  •  H help$esc[0m"
            )
        }

        "Session" {

            return (
                "$esc[90mEsc back$esc[0m"
            )
        }
    }
}


function Get-YukiMenuFooter {

    return (
        Get-YukiFooter `
            -Context "Menu"
    )
}


# ============================================================
# MENU
# ============================================================

function Show-YukiMenu {

    param(
        [Parameter(Mandatory)]
        [object]$Menu,

        [Parameter(Mandatory)]
        [int]$Selected
    )


    $lines =
        [System.Collections.Generic.List[string]]::new()


    $lines.Add(
        "$esc[96m◇  YUKI.CPP$esc[0m"
    )

    $lines.Add("")


    $lines.Add(
        "$esc[90m│$esc[0m  $($Menu.title)"
    )

    $lines.Add(
        "$esc[90m│$esc[0m"
    )


    for (
        $i = 0;
        $i -lt $Menu.items.Count;
        $i++
    ) {

        $item = $Menu.items[$i]


        if ($i -eq $Selected) {

            $line =
                "$esc[96m◆$esc[0m  " +
                "$esc[97m$($item.label)$esc[0m"
        }
        else {

            $line =
                "$esc[90m○  $($item.label)$esc[0m"
        }


        if ($item.hint) {

            $line +=
                "  $esc[90m$($item.hint)$esc[0m"
        }


        $lines.Add($line)
    }


    $lines.Add("")

    $lines.Add(
        (Get-YukiMenuFooter)
    )


    Write-YukiScreen `
        -Lines $lines
}


# ============================================================
# HELP
#
# Only Esc leaves Help.
# ============================================================

function Show-YukiHelp {

    $first = $true


    while ($true) {

        $lines = @(

            "$esc[96m◇  YUKI.CPP / HELP$esc[0m",
            "",
            "$esc[90m│$esc[0m  Navigation",
            "$esc[90m│$esc[0m",
            "   ↑ / ↓     navigate",
            "   Enter     select",
            "   Esc       back",
            "   H         help",
            "",
            "   Quit is available only",
            "   as an option in the main menu.",
            "",
            "$esc[90mEsc = back$esc[0m"
        )


        Write-YukiScreen `
            -Lines $lines `
            -ClearFirst:$first


        $first = $false


        $key =
            Read-YukiKey


        if ($key -eq "BACK") {
            return
        }
    }
}


# ============================================================
# MESSAGE
#
# Only Esc leaves the screen.
# ============================================================

function Show-YukiMessage {

    param(
        [string]$Title,

        [object[]]$Content
    )


    $first = $true


    while ($true) {

        $lines =
            [System.Collections.Generic.List[string]]::new()


        $lines.Add(
            "$esc[96m◇  YUKI.CPP / $Title$esc[0m"
        )

        $lines.Add("")

        $lines.Add(
            "$esc[90m│$esc[0m"
        )


        if (@($Content).Count -eq 0) {

            $lines.Add(
                "$esc[90m│$esc[0m  Complete."
            )
        }
        else {

            foreach ($entry in @($Content)) {

                $text =
                    [string]$entry


                foreach (
                    $line in
                    ($text -split "`r?`n")
                ) {

                    $lines.Add(
                        "$esc[90m│$esc[0m  $line"
                    )
                }
            }
        }


        $lines.Add("")

        $lines.Add(
            "$esc[90mEsc = back" +
            "  •  H help$esc[0m"
        )


        Write-YukiScreen `
            -Lines $lines `
            -ClearFirst:$first


        $first = $false


        $key =
            Read-YukiKey


        switch ($key) {

            "BACK" {
                return
            }


            "HELP" {
                Show-YukiHelp
                $first = $true
            }
        }
    }
}


# ============================================================
# LOG VIEWER
# ============================================================

function Get-YukiLogLines {

    param(
        [string[]]$Paths
    )


    $result =
        [System.Collections.Generic.List[string]]::new()


    foreach ($path in $Paths) {

        $result.Add(
            "──────── $(Split-Path $path -Leaf) ────────"
        )


        if (!(Test-Path $path)) {

            $result.Add(
                "[file not found]"
            )

            $result.Add("")

            continue
        }


        $content = @(

            Get-Content `
                -Path $path `
                -Encoding UTF8 `
                -Tail 500 `
                -ErrorAction SilentlyContinue
        )


        if ($content.Count -eq 0) {

            $result.Add(
                "[no output]"
            )
        }
        else {

            foreach ($line in $content) {

                $result.Add(
                    [string]$line
                )
            }
        }


        $result.Add("")
    }


    return @($result)
}


function Show-YukiLogViewer {

    param(
        [string]$Title,

        [string[]]$Paths
    )


    $offset = 0
    $first  = $true


    while ($true) {

        $all =
            @(
                Get-YukiLogLines `
                    -Paths $Paths
            )


        try {

            $height =
                [Console]::WindowHeight
        }
        catch {

            $height = 30
        }


        $pageSize =
            [Math]::Max(
                5,
                $height - 7
            )


        $maxTop =
            [Math]::Max(
                0,
                $all.Count - $pageSize
            )


        $offset =
            [Math]::Max(
                0,
                [Math]::Min(
                    $maxTop,
                    $offset
                )
            )


        $top =
            $maxTop - $offset


        $lines =
            [System.Collections.Generic.List[string]]::new()


        $lines.Add(
            "$esc[96m◇  YUKI.CPP / LOGS / " +
            "$($Title.ToUpperInvariant())$esc[0m"
        )

        $lines.Add("")


        $lines.Add(
            "$esc[90m↑/↓ scroll" +
            "  •  PgUp/PgDn" +
            "  •  Home/End" +
            "  •  Esc back" +
            "  •  H help$esc[0m"
        )

        $lines.Add("")


        $end =
            [Math]::Min(
                $all.Count,
                $top + $pageSize
            )


        for (
            $i = $top;
            $i -lt $end;
            $i++
        ) {

            $lines.Add(
                [string]$all[$i]
            )
        }


        Write-YukiScreen `
            -Lines $lines `
            -ClearFirst:$first


        $first = $false


        $key =
            Read-YukiKey


        switch ($key) {

            "UP" {

                $offset =
                    [Math]::Min(
                        $maxTop,
                        $offset + 1
                    )
            }


            "DOWN" {

                $offset =
                    [Math]::Max(
                        0,
                        $offset - 1
                    )
            }


            "PAGEUP" {

                $offset =
                    [Math]::Min(
                        $maxTop,
                        $offset + $pageSize
                    )
            }


            "PAGEDOWN" {

                $offset =
                    [Math]::Max(
                        0,
                        $offset - $pageSize
                    )
            }


            "HOME" {
                $offset = $maxTop
            }


            "END" {
                $offset = 0
            }


            "BACK" {
                return
            }


            "HELP" {

                Show-YukiHelp

                $first = $true
            }
        }
    }
}


# ============================================================
# MODE RUNNER
# ============================================================

function Enter-YukiSessionScreen {

    param(
        [ValidateSet("TEXT","VOICE")]
        [string]$Name,

        [bool]$ShowCursor
    )


    try {
        $height = [Console]::WindowHeight
    }
    catch {
        $height = 30
    }


    $bodyTop = 6

    $footerRow = [Math]::Max(
        8,
        $height
    )

    $bodyBottom = [Math]::Max(
        $bodyTop,
        $footerRow - 2
    )


    $footer =
        Get-YukiFooter `
            -Context "Session"


    $builder =
        [System.Text.StringBuilder]::new()


    # Reset any previous scroll region.
    [void]$builder.Append(
        "${esc}[r"
    )

    # Fresh complete session screen.
    [void]$builder.Append(
        "${esc}[2J${esc}[H"
    )


    # Shared YUKI header.
    [void]$builder.Append(
        "${esc}[96m◇  YUKI.CPP / $Name${esc}[0m"
    )


    # Shared section structure.
    [void]$builder.Append(
        "${esc}[3;1H"
    )

    [void]$builder.Append(
        "${esc}[90m│${esc}[0m  Session"
    )

    [void]$builder.Append(
        "${esc}[4;1H"
    )

    [void]$builder.Append(
        "${esc}[90m│${esc}[0m"
    )


    # Shared helper bar at the bottom.
    [void]$builder.Append(
        "${esc}[${footerRow};1H"
    )

    [void]$builder.Append(
        $footer
    )

    [void]$builder.Append(
        "${esc}[K"
    )


    # Only the body region scrolls.
    # Header and helper bar stay fixed.
    [void]$builder.Append(
        "${esc}[${bodyTop};${bodyBottom}r"
    )

    [void]$builder.Append(
        "${esc}[${bodyTop};1H"
    )


    if ($ShowCursor) {

        [void]$builder.Append(
            "${esc}[?25h"
        )
    }
    else {

        [void]$builder.Append(
            "${esc}[?25l"
        )
    }


    [Console]::Write(
        $builder.ToString()
    )
}


function Exit-YukiSessionScreen {

    # Reset terminal scrolling region first.
    [Console]::Write(
        "${esc}[r" +
        "${esc}[?25l" +
        "${esc}[2J" +
        "${esc}[H"
    )
}


function Invoke-YukiModeRunner {

    param(
        [string]$Runner,
        [string]$Name,

        [ValidateSet("TEXT","VOICE")]
        [string]$Mode
    )


    if (!(Test-Path $Runner)) {

        Show-YukiMessage `
            -Title "ERROR" `
            -Content @(
                "$Name runner not found:",
                $Runner
            )

        return
    }


    # Controller owns mode.txt.
    Set-YukiMode $Mode


    Enter-YukiSessionScreen `
        -Name $Mode `
        -ShowCursor ($Mode -eq "TEXT")


    try {

        # Runner owns behavior only.
        # It must not draw YUKI headers/footers.
        & $Runner
    }
    catch {

        Exit-YukiSessionScreen

        Show-YukiMessage `
            -Title "ERROR" `
            -Content @(
                $_.Exception.Message
            )
    }
    finally {

        Set-YukiMode "CONTROL"

        Exit-YukiSessionScreen
    }
}


# ============================================================
# BACKEND
# ============================================================

function Invoke-YukiBackend {

    param(
        [string]$Name,
        [string]$Target
    )


    try {

        $raw = @(

            & {

                Invoke-YukiBackendAction `
                    -Action $Target

            } *>&1
        )


        $visible =
            [System.Collections.Generic.List[object]]::new()


        foreach ($entry in $raw) {

            # Hide internal structured completion objects.
            if (
                $entry -and
                $entry.PSObject.Properties["Kind"]
            ) {
                continue
            }


            $visible.Add($entry)
        }


        Show-YukiMessage `
            -Title $Name.ToUpperInvariant() `
            -Content @($visible)
    }
    catch {

        Show-YukiMessage `
            -Title "ERROR" `
            -Content @(
                $_.Exception.Message
            )
    }
}


# ============================================================
# ACTION ROUTER
#
# Menu knows only action ID.
# JSON action definition decides what it means.
# ============================================================

function Invoke-YukiAction {

    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$Name
    )


    $definition =
        Get-YukiAction `
            -Config $Config `
            -Name $Name


    $kind =
        [string]$definition.kind


    switch ($kind) {

        # ----------------------------------------------------
        # MODE
        # ----------------------------------------------------

        "mode" {

            Invoke-YukiModeRunner `
                -Runner ([string]$definition.runner) `
                -Name $Name `
                -Mode ([string]$definition.mode)

            return
        }


        # ----------------------------------------------------
        # LOG
        # ----------------------------------------------------

        "log" {

            Show-YukiLogViewer `
                -Title ([string]$definition.title) `
                -Paths ([string[]]@($definition.paths))

            return
        }


        # ----------------------------------------------------
        # BACKEND
        # ----------------------------------------------------

        "backend" {

            Invoke-YukiBackend `
                -Name $Name `
                -Target ([string]$definition.target)

            return
        }
    }
}


# ============================================================
# CONTROLLER STATE MACHINE
# ============================================================

function Start-YukiController {

    $config =
        Get-YukiConfig


    Test-YukiConfig `
        -Config $config


    $rootMenu =
        [string]$config.root


    $currentMenu =
        $rootMenu


    # Stack contains previous MENU NAMES only.
    $history =
        [System.Collections.Generic.Stack[string]]::new()


    # Remember cursor position separately per menu.
    $selection = @{}


    $oldCtrlC =
        [Console]::TreatControlCAsInput


    try {

        # Ctrl+C becomes ordinary input instead of
        # terminating the controller.
        [Console]::TreatControlCAsInput =
            $true


        Set-YukiMode "CONTROL"


        # Alternate screen is entered ONCE.
        [Console]::Write(
            "$esc[?1049h" +
            "$esc[?25l" +
            "$esc[2J" +
            "$esc[H"
        )


        $clearNext = $false


        while ($true) {

            # ------------------------------------------------
            # STATE -> MENU
            # ------------------------------------------------

            $menu =
                Get-YukiMenu `
                    -Config $config `
                    -Name $currentMenu


            if (
                !$selection.ContainsKey(
                    $currentMenu
                )
            ) {

                $selection[$currentMenu] = 0
            }


            $selected =
                [int]$selection[$currentMenu]


            if (
                $selected -lt 0 -or
                $selected -ge $menu.items.Count
            ) {

                $selected = 0

                $selection[$currentMenu] =
                    0
            }


            # ------------------------------------------------
            # BUILD + WRITE COMPLETE FRAME
            # ------------------------------------------------

            if ($clearNext) {

                [Console]::Write(
                    "$esc[2J$esc[H"
                )

                $clearNext = $false
            }


            Show-YukiMenu `
                -Menu $menu `
                -Selected $selected


            # ------------------------------------------------
            # ONE KEY
            # ------------------------------------------------

            $key =
                Read-YukiKey


            # ------------------------------------------------
            # KEY -> NEW STATE
            # ------------------------------------------------

            switch ($key) {

                "UP" {

                    $selected--


                    if ($selected -lt 0) {

                        $selected =
                            $menu.items.Count - 1
                    }


                    $selection[$currentMenu] =
                        $selected
                }


                "DOWN" {

                    $selected++


                    if (
                        $selected -ge
                        $menu.items.Count
                    ) {

                        $selected = 0
                    }


                    $selection[$currentMenu] =
                        $selected
                }


                # --------------------------------------------
                # ESC = ONLY BACK
                # --------------------------------------------

                "BACK" {

                    if ($history.Count -gt 0) {

                        $currentMenu =
                            $history.Pop()
                    }

                    # Esc on root intentionally does nothing.
                }


                # --------------------------------------------
                # HELP
                # --------------------------------------------

                "HELP" {

                    Show-YukiHelp

                    $clearNext = $true
                }


                # --------------------------------------------
                # SELECT
                # --------------------------------------------

                "ENTER" {

                    $item =
                        $menu.items[$selected]


                    $type =
                        [string]$item.type


                    switch ($type) {

                        # ------------------------------------
                        # SUBMENU
                        # ------------------------------------

                        "menu" {

                            $history.Push(
                                $currentMenu
                            )


                            $currentMenu =
                                [string]$item.target
                        }


                        # ------------------------------------
                        # ACTION
                        # ------------------------------------

                        "action" {

                            Invoke-YukiAction `
                                -Config $config `
                                -Name (
                                    [string]$item.target
                                )


                            $clearNext = $true
                        }


                        # ------------------------------------
                        # HELP ITEM
                        # ------------------------------------

                        "help" {

                            Show-YukiHelp

                            $clearNext = $true
                        }


                        # ------------------------------------
                        # QUIT
                        #
                        # Valid only in root menu because
                        # JSON validation enforces it.
                        # ------------------------------------

                        "quit" {

                            if (
                                $currentMenu -eq
                                $rootMenu
                            ) {
                                return
                            }
                        }
                    }
                }
            }
        }
    }
    finally {

        Set-YukiMode "CONTROL"


        # Restore cursor + original terminal buffer.
        [Console]::Write(
            "$esc[?25h" +
            "$esc[?1049l"
        )


        [Console]::TreatControlCAsInput =
            $oldCtrlC
    }
}



# Start required local services.
# Twitch remains manual.
Start-YukiCore

Start-YukiController

