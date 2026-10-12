#requires -version 5.1
<#
.SYNOPSIS
    Build Phase 1 (enter service mode) and Phase 3 (exit service mode) Loewenstein/
    Weinmann Prisma SD-update packages from a stock
    Update_weinmann_respiratory_device.zip.

.DESCRIPTION
    Windows PowerShell version of make_service_packages.sh. Uses only built-in
    PowerShell / .NET (no external tools):
      * System.IO.Compression  - extract / build zips (root-level entries)
      * Get-FileHash -Algorithm MD5

    Phase 1 (phase1_servicemode): after install, drops the developer/service markers
        /mnt/config/develop_servicesw_marker + /mnt/config/develop_marker
        so the device boots into the on-screen ServiceSW menu (device type /
        serials / clock changeable there).
    Phase 3 (phase3_exitservice): after install, removes those markers so the
        device returns to normal therapy boot.

    Only postUpdate.sh is modified; every other file (and its md5) is carried over
    unchanged. update.cks is regenerated with LOWERCASE md5s, LF line endings and
    NO BOM (CRLF / BOM would break the device's shell and md5 check). Each output
    is verified (every md5 re-checked) before finishing.

.PARAMETER SourceZip
    Path to the stock Update_weinmann_respiratory_device.zip.

.PARAMETER OutputDir
    Output directory (default .\service_packages).

.EXAMPLE
    .\make_service_packages.ps1 .\Update_weinmann_respiratory_device.zip
#>
param(
    [Parameter(Mandatory = $true, Position = 0)] [string] $SourceZip,
    [Parameter(Position = 1)] [string] $OutputDir = ".\service_packages"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# System.IO.Compression types (no-op / harmless on PowerShell 7 where already loaded)
try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop } catch { }
try { Add-Type -AssemblyName System.IO.Compression            -ErrorAction Stop } catch { }

$ZipName = 'Update_weinmann_respiratory_device.zip'

# ---- validate / resolve paths -------------------------------------------------
if (-not (Test-Path -LiteralPath $SourceZip -PathType Leaf)) { throw "Input zip not found: $SourceZip" }
$SourceZip = (Resolve-Path -LiteralPath $SourceZip).Path
if (-not [System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir = Join-Path (Get-Location).Path $OutputDir }
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wmpkg_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

# ---- helpers ------------------------------------------------------------------
function Get-Md5Lower([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash.ToLowerInvariant()
}

# Write text as pure-LF, no BOM (required by the device shell / md5 check).
function Write-TextLf([string] $Path, [string] $Text) {
    $lf = ($Text -replace "`r`n", "`n") -replace "`r", "`n"
    $enc = New-Object System.Text.UTF8Encoding($false)   # $false = no BOM
    [System.IO.File]::WriteAllText($Path, $lf, $enc)
}

function Add-MarkerLogic([string] $Work, [string] $Mode) {
    $pu = Join-Path $Work 'postUpdate.sh'
    $orig = [System.IO.File]::ReadAllText($pu)
    if ($Mode -eq 'enter') {
        $lines = @(
            '',
            '# --- custom: enter service mode on next boot (ServiceSW menu + USB console) ---',
            'if mountpoint -q /mnt/config 2>/dev/null || mount | grep -q '' /mnt/config ''; then',
            '  touch /mnt/config/develop_servicesw_marker',
            '  touch /mnt/config/develop_marker',
            '  sync',
            '  echo "custom: service-mode markers created"',
            'fi'
        )
    }
    else {
        $lines = @(
            '',
            '# --- custom: leave service mode / return to normal therapy boot ---',
            'if mountpoint -q /mnt/config 2>/dev/null || mount | grep -q '' /mnt/config ''; then',
            '  rm -f /mnt/config/develop_servicesw_marker /mnt/config/develop_marker',
            '  sync',
            '  echo "custom: service-mode markers removed"',
            'fi'
        )
    }
    $snippet = ($lines -join "`n") + "`n"
    Write-TextLf $pu ($orig + $snippet)
}

# Regenerate update.cks preserving the original file list & order. Returns file names.
function Update-Manifest([string] $Work) {
    $cks = Join-Path $Work 'update.cks'
    $names = New-Object System.Collections.Generic.List[string]
    $outLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in [System.IO.File]::ReadAllLines($cks)) {
        $t = $line.TrimEnd()
        if ($t.Length -eq 0) { continue }
        $sp = $t.IndexOf(' ')
        if ($sp -lt 0) { throw "Malformed manifest line: '$line'" }
        $name = $t.Substring($sp + 1).Trim()
        $fp = Join-Path $Work $name
        if (-not (Test-Path -LiteralPath $fp -PathType Leaf)) { throw "File listed in manifest is missing: $name" }
        $outLines.Add((Get-Md5Lower $fp) + ' ' + $name)
        $names.Add($name)
    }
    Write-TextLf $cks (($outLines -join "`n") + "`n")
    return $names.ToArray()
}

function New-RootZip([string] $Work, [string] $OutZip, [string[]] $Names) {
    if (Test-Path -LiteralPath $OutZip) { Remove-Item -LiteralPath $OutZip -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($OutZip, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($n in $Names) {
            $fp = Join-Path $Work $n
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $fp, $n, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    }
    finally { $zip.Dispose() }
}

function Test-Package([string] $OutZip) {
    $v = Join-Path $Tmp ("verify_" + [System.Guid]::NewGuid().ToString('N'))
    [System.IO.Compression.ZipFile]::ExtractToDirectory($OutZip, $v)
    foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $v 'update.cks'))) {
        $t = $line.TrimEnd()
        if ($t.Length -eq 0) { continue }
        $sp = $t.IndexOf(' ')
        $md5 = $t.Substring(0, $sp)
        $name = $t.Substring($sp + 1).Trim()
        $calc = Get-Md5Lower (Join-Path $v $name)
        if ($calc -ne $md5) { throw "VERIFY FAIL: $name manifest=$md5 calc=$calc" }
    }
}

function Build-Variant([string] $Label, [string] $Mode) {
    $work = Join-Path $Tmp $Label
    [System.IO.Compression.ZipFile]::ExtractToDirectory($SourceZip, $work)   # creates $work
    if (-not (Test-Path (Join-Path $work 'postUpdate.sh'))) { throw "postUpdate.sh not in package" }
    if (-not (Test-Path (Join-Path $work 'update.cks'))) { throw "update.cks not in package" }

    Add-MarkerLogic $work $Mode
    $names = Update-Manifest $work

    $outsub = Join-Path $OutputDir $Label
    New-Item -ItemType Directory -Force -Path $outsub | Out-Null
    $outzip = Join-Path $outsub $ZipName

    New-RootZip $work $outzip (@('update.cks') + $names)
    Test-Package $outzip
    Write-Host "  $Label -> $outzip  (verified OK)"
}

# ---- run ----------------------------------------------------------------------
try {
    Write-Host "Source : $SourceZip"
    Write-Host "Output : $OutputDir"
    Write-Host "Building packages..."
    Build-Variant "phase1_servicemode" "enter"
    Build-Variant "phase3_exitservice" "exit"
    Write-Host "Done."
    Write-Host ""
    Write-Host "Put the chosen zip on a FAT32 SD card at its ROOT (keep the exact name),"
    Write-Host "install it on the device (do NOT cut power), accept the update when asked."
    Write-Host "To go back to normal mode, insert SD card with phase 3 zip."
    Write-Host "  phase1_servicemode -> enters the on-screen ServiceSW menu"
    Write-Host "  phase3_exitservice -> returns to normal therapy boot"
}
finally {
    if (Test-Path -LiteralPath $Tmp) { Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
