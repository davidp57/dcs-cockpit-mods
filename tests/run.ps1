<#
.SYNOPSIS
    Off-game check of the hook and of the cycles device (tests\simulate.lua), with and
    without lfs. Needs a Lua 5.1 interpreter with lfs (ZeroBrane Studio's, by default) and
    the AH-64D scripts of a DCS install.
#>
param(
    [string]$Lua = "D:\dev\ZeroBraneStudio\bin\lua.exe",
    [string]$DcsPath = "C:\jeux\DCS World"
)

$ErrorActionPreference = "Stop"

$work = Join-Path ([System.IO.Path]::GetTempPath()) "cockpit-mods-test"
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
$cockpit = Join-Path $work "Cockpit"
New-Item -ItemType Directory -Force -Path $cockpit | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot "..\hook\mod\Scripts\Aircrafts\_Common\Cockpit\*") -Destination $cockpit -Recurse -Force
Copy-Item -Path (Join-Path $PSScriptRoot "..\cycles\mod\Scripts\Aircrafts\_Common\Cockpit\*") -Destination $cockpit -Recurse -Force

$luaDir = Split-Path $Lua
$env:LUA_CPATH = (Join-Path $luaDir "clibs\?.dll") + ";;"
$scripts = (Join-Path $DcsPath "Mods\aircraft\AH-64D\Cockpit\Scripts\") -replace "\\", "/"
$cockpitArg = ($cockpit -replace "\\", "/") + "/"
$simulate = Join-Path $PSScriptRoot "simulate.lua"

$failed = $false
foreach ($mode in @("lfs", "nolfs")) {
    Write-Host "=== $mode ==="
    & $Lua $simulate $cockpitArg $scripts $mode
    if ($LASTEXITCODE -ne 0) { $failed = $true }
}
Remove-Item -LiteralPath $work -Recurse -Force
if ($failed) { throw "Some checks failed." }
Write-Host "Both runs passed."
