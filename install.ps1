<#
.SYNOPSIS
    Development install of the cockpit mods hook and of the cockpit cycles in DCS World
    (players use the Open Mod Manager packages built by tools\build_omm.py instead).

.DESCRIPTION
    Hook:
    - copies COCKPIT_MODS\_loader.lua into the DCS install;
    - adds one line to the shared kneeboard declaration, loaded by most modules, which runs
      the loader; the loader then runs each mod's file in COCKPIT_MODS.
    Cycles (needs the hook):
    - copies COCKPIT_CYCLES and COCKPIT_MODS\COCKPIT_CYCLES.lua.
    The key bindings are not installed here: they come from the Custom_Keybinds package
    (dcs-community-keybinds), through Quaggles' DCS Input Command Injector.

    The kneeboard file is saved as <file>.cockpit-mods.bak before it is changed; the backup
    is refreshed whenever the file is found without the hook (after a DCS update, say).
    A DCS update or repair overwrites the patched file: run this script again afterwards.
    After editing a mod, run it again and restart the mission: cockpit scripts are read at
    each mission start.

.PARAMETER Part
    Hook, Cycles, or both (the default).

.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -Part Hook
.EXAMPLE
    .\install.ps1 -Uninstall
.EXAMPLE
    .\install.ps1 -DcsPath "D:\DCS World"
#>
param(
    [string]$DcsPath = "C:\jeux\DCS World",
    [ValidateSet("Hook", "Cycles")]
    [string[]]$Part = @("Hook", "Cycles"),
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$Marker       = "COCKPIT-MODS"
$LegacyMarker = "IFR-CURTAIN"
$BackupExt    = ".cockpit-mods.bak"
$Cockpit      = Join-Path $DcsPath "Scripts\Aircrafts\_Common\Cockpit"
$DeclareFile  = Join-Path $Cockpit "KNEEBOARD\declare_kneeboard_device.lua"
$ModsFolder   = Join-Path $Cockpit "COCKPIT_MODS"
$Loader       = Join-Path $ModsFolder "_loader.lua"
$HookSource   = Join-Path $PSScriptRoot "hook\mod\Scripts\Aircrafts\_Common\Cockpit\COCKPIT_MODS\_loader.lua"
$CyclesSource = Join-Path $PSScriptRoot "cycles\mod\Scripts\Aircrafts\_Common\Cockpit"
$CyclesFolder = Join-Path $Cockpit "COCKPIT_CYCLES"
$CyclesDeclare = Join-Path $ModsFolder "COCKPIT_CYCLES.lua"

# Same line as tools\build_omm.py, HOOK_LINE.
$HookLine = 'do local ok, err = pcall(dofile, LockOn_Options.common_script_path.."COCKPIT_MODS/_loader.lua") if not ok then print("COCKPIT_MODS: hook failed: "..tostring(err)) end end'

$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

# Reads a file as UTF-8, remembering whether it starts with a byte order mark.
# Refuses a file that is not valid UTF-8 rather than rewriting it with replaced characters.
function Read-Text([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $start = if ($bom) { 3 } else { 0 }
    try {
        $text = $Utf8Strict.GetString($bytes, $start, $bytes.Length - $start)
    }
    catch {
        throw "Not valid UTF-8, left untouched: $Path"
    }
    return @{ Text = $text; Bom = $bom }
}

function Write-Text([string]$Path, [string]$Text, [bool]$Bom) {
    $encoding = New-Object System.Text.UTF8Encoding($Bom)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Get-Newline([string]$Text) {
    if ($Text.Contains("`r`n")) { return "`r`n" }
    return "`n"
}

function Test-Block([string]$Text, [string]$Name = $Marker) {
    return $Text.Contains("-- $Name BEGIN")
}

# Removes every block between the BEGIN and END markers, markers included, even when the
# block ends the file without a final newline.
function Remove-Block([string]$Text) {
    $pattern = "(?ms)^[ \t]*-- $Marker BEGIN.*?-- $Marker END[ \t]*(\r?\n|\z)"
    return [regex]::Replace($Text, $pattern, "")
}

# Appends the block at the end of the file.
function Set-Block([string]$Path, [string[]]$Lines) {
    $file = Read-Text $Path
    if (Test-Block $file.Text $LegacyMarker) {
        throw "The IFR curtain is installed the old way (its own line in $Path). Run the IFR curtain's install.ps1 -Uninstall first, then this script, then the curtain's install.ps1 again."
    }
    if (-not (Test-Block $file.Text)) {
        # The file is as DCS shipped it: (re)take the backup from it.
        Copy-Item -LiteralPath $Path -Destination ($Path + $BackupExt) -Force
    }
    $text = Remove-Block $file.Text
    $nl = Get-Newline $text
    if (-not $text.EndsWith("`n")) { $text += $nl }
    $text += "-- $Marker BEGIN$nl" + (($Lines | ForEach-Object { $_ + $nl }) -join "") + "-- $Marker END$nl"
    Write-Text $Path $text $file.Bom
    Write-Host "Patched: $Path"
}

function Clear-Block([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $file = Read-Text $Path
    if (-not (Test-Block $file.Text)) { return }
    $clean = Remove-Block $file.Text
    $backup = $Path + $BackupExt
    if (Test-Path -LiteralPath $backup) {
        # Installing may have added a final newline the original did not have: when only
        # trailing whitespace differs from the backup, put the backup back as it was.
        $original = Read-Text $backup
        if ($clean.TrimEnd() -ceq $original.Text.TrimEnd()) {
            Copy-Item -LiteralPath $backup -Destination $Path -Force
            Remove-Item -LiteralPath $backup -Force
            Write-Host "Restored: $Path"
            return
        }
    }
    Write-Text $Path $clean $file.Bom
    Write-Host "Cleaned: $Path"
}

function Remove-IfPresent([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
        Write-Host "Removed: $Path"
    }
}

if (-not (Test-Path -LiteralPath $DeclareFile)) {
    throw "DCS not found: $DeclareFile does not exist. Pass -DcsPath."
}

if ($Uninstall) {
    if ($Part -contains "Cycles") {
        Remove-IfPresent $CyclesDeclare
        Remove-IfPresent $CyclesFolder
    }
    if ($Part -contains "Hook") {
        Clear-Block $DeclareFile
        Remove-IfPresent $Loader
        if (Test-Path -LiteralPath $ModsFolder) {
            $left = @(Get-ChildItem -LiteralPath $ModsFolder)
            if ($left.Count -eq 0) {
                Remove-IfPresent $ModsFolder
            }
            else {
                Write-Host "Left in place, still used by other mods (no longer loaded without the hook): $(($left | ForEach-Object Name) -join ', ')"
            }
        }
    }
    Write-Host "Removed: $($Part -join ', ')."
    return
}

if ($Part -contains "Hook") {
    New-Item -ItemType Directory -Force -Path $ModsFolder | Out-Null
    Copy-Item -LiteralPath $HookSource -Destination $Loader -Force
    Write-Host "Copied: $Loader"
    Set-Block $DeclareFile @($HookLine)
}

if ($Part -contains "Cycles") {
    if (-not (Test-Path -LiteralPath $Loader)) {
        throw "The cockpit mods hook is not installed: run .\install.ps1 -Part Hook first (or install the Cockpit_Mods_Hook package)."
    }
    Remove-IfPresent $CyclesFolder
    Copy-Item -LiteralPath (Join-Path $CyclesSource "COCKPIT_CYCLES") -Destination $CyclesFolder -Recurse
    Write-Host "Copied: $CyclesFolder"
    Copy-Item -LiteralPath (Join-Path $CyclesSource "COCKPIT_MODS\COCKPIT_CYCLES.lua") -Destination $CyclesDeclare -Force
    Write-Host "Copied: $CyclesDeclare"
}

Write-Host "Installed: $($Part -join ', ') (key bindings: Custom_Keybinds package, through Quaggles' injector)."
