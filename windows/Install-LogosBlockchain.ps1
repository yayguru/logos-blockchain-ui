<#
.SYNOPSIS
  One-click setup of the Logos Blockchain node + UI (unofficial yayguru Windows build) in Logos Basecamp.

.DESCRIPTION
  1. Installs Logos Basecamp (official logos-co setup, sha256-pinned) if it is missing.
  2. Downloads blockchain_module and blockchain_ui (.lgx, sha256-pinned) from the yayguru prerelease.
  3. Unpacks them into a Basecamp user directory of their own, the same layout Basecamp's
     "Install Local Package" writes. Nothing is added to Basecamp's trusted keyring.
  4. Creates a desktop shortcut and starts Basecamp with that user directory.
  In the Blockchain app, "Quick start" then writes the node config and starts the node.
  From then on the module restarts the same node (and mining) by itself, also after
  updates of the UI ("Resume after restart", on by default).

  It never generates keys or configs itself, never touches another Basecamp user
  directory, and refuses to run while that Basecamp is open.

.PARAMETER UserDir   Basecamp user directory (default: %LOCALAPPDATA%\LogosBlockchain\basecamp).
.PARAMETER ModuleLgx Use this local blockchain_module .lgx instead of downloading (its sha256 must match).
.PARAMETER UiLgx     Use this local blockchain_ui .lgx instead of downloading (its sha256 must match).
.PARAMETER DryRun    Check and unpack into a temp folder only; change nothing.
.PARAMETER NoLaunch  Do not start Basecamp at the end.
.PARAMETER NoShortcut Do not create the desktop shortcut.
#>
[CmdletBinding()]
param(
  [string]$UserDir = (Join-Path $env:LOCALAPPDATA 'LogosBlockchain\basecamp'),
  [string]$ModuleLgx = '',
  [string]$UiLgx = '',
  [switch]$DryRun,
  [switch]$NoLaunch,
  [switch]$NoShortcut
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---- pinned artifacts (filled in per release) ----
$Release = '@RELEASE_TAG@'
$Packages = @(
  @{ Name = 'blockchain_module'; Kind = 'modules'; Url = '@MODULE_URL@'; Sha256 = '@MODULE_SHA@' },
  @{ Name = 'blockchain_ui';     Kind = 'plugins'; Url = '@UI_URL@';     Sha256 = '@UI_SHA@' }
)
$Basecamp = @{
  Url    = 'https://github.com/logos-co/logos-basecamp/releases/download/pre-release-4cea4bb-1433/logos-basecamp-0.4.0-rc.2-x86_64-setup.exe'
  Sha256 = 'd3d7170ac39e714ab1d64e7a76c71af9aa79553f05c48171b556f4e4d13a8ee1'
  Exe    = (Join-Path $env:LOCALAPPDATA 'Programs\LogosBasecamp\bin\LogosBasecamp.exe')
}

function Step([string]$s) { Write-Host ("==> " + $s) -ForegroundColor Cyan }
function Info([string]$s) { Write-Host ("    " + $s) }
function Fail([string]$s, [int]$code) { Write-Host ("ERROR: " + $s) -ForegroundColor Red; exit $code }
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() }

function Fetch([string]$url, [string]$sha, [string]$dest) {
  if (Test-Path -LiteralPath $dest) { if ((Sha $dest) -eq $sha) { return } ; Remove-Item -LiteralPath $dest -Force }
  Info ("download " + $url)
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
  $h = Sha $dest
  if ($h -ne $sha) { Remove-Item -LiteralPath $dest -Force; Fail ("sha256 mismatch for {0}: got {1}, expected {2}" -f $url, $h, $sha) 3 }
}

if (-not [Environment]::Is64BitOperatingSystem) { Fail 'Windows x64 is required.' 2 }
if ($Release -like '@*') { Fail 'This copy of the script has no pinned release. Use the one attached to a GitHub release.' 2 }
$UserDir = [IO.Path]::GetFullPath($UserDir)
$work = Join-Path $env:TEMP ('logos-blockchain-setup-' + $Release)
New-Item -ItemType Directory -Force -Path $work | Out-Null

Step "Logos Blockchain setup ($Release)$(if ($DryRun) { ' - dry run' })"
Info ("Basecamp user directory: " + $UserDir)

# ---- 1. Basecamp ----
Step 'Logos Basecamp'
if (Test-Path -LiteralPath $Basecamp.Exe) {
  Info ("found " + $Basecamp.Exe)
} elseif ($DryRun) {
  Info 'not installed; a real run would install the official 0.4.0-rc.2 setup'
} else {
  $setup = Join-Path $work 'logos-basecamp-setup.exe'
  Fetch $Basecamp.Url $Basecamp.Sha256 $setup
  Info 'running the official setup (silent)'
  $p = Start-Process -FilePath $setup -ArgumentList '/S' -Wait -PassThru
  if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $Basecamp.Exe)) { Fail ("Basecamp setup failed (exit {0}). Install it by hand from {1} and run this again." -f $p.ExitCode, $Basecamp.Url) 4 }
}

# ---- 2. refuse while this Basecamp runs ----
$running = @(Get-CimInstance Win32_Process -Filter "Name='LogosBasecamp.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and ($_.CommandLine -replace '/', '\').ToLower().Contains($UserDir.ToLower()) })
if ($running.Count -gt 0 -and -not $DryRun) { Fail 'Basecamp is running with this user directory. Close it (File > Quit) and run the setup again.' 5 }

# ---- 3. packages ----
Step 'Packages'
$stage = Join-Path $work 'stage'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path -LiteralPath $tar)) { Fail 'tar.exe is missing (Windows 10 1803 or newer is required).' 2 }
foreach ($pkg in $Packages) {
  $file = Join-Path $work ($pkg.Name + '.lgx')
  $local = if ($pkg.Name -eq 'blockchain_module') { $ModuleLgx } else { $UiLgx }
  if ($local) {
    if ((Sha $local) -ne $pkg.Sha256) { Fail ("{0} does not match the pinned sha256 {1}" -f $local, $pkg.Sha256) 3 }
    Copy-Item -LiteralPath $local -Destination $file -Force
  } else {
    Fetch $pkg.Url $pkg.Sha256 $file
  }
  $x = Join-Path $stage $pkg.Name
  New-Item -ItemType Directory -Force -Path $x | Out-Null
  & $tar -xzf $file -C $x
  if ($LASTEXITCODE -ne 0) { Fail ("could not unpack " + $file) 6 }
  $m = Get-Content -LiteralPath (Join-Path $x 'manifest.json') -Raw | ConvertFrom-Json
  if ($m.name -ne $pkg.Name) { Fail ("{0}: manifest names {1}" -f $file, $m.name) 6 }
  $variant = Join-Path $x 'variants\windows-x86_64'
  if (-not (Test-Path -LiteralPath $variant)) { Fail ("{0} has no windows-x86_64 variant" -f $file) 6 }
  # The installed layout: variant files at the top, plus manifest, signature, assets.
  $out = Join-Path $stage ($pkg.Name + '.installed')
  New-Item -ItemType Directory -Force -Path $out | Out-Null
  Copy-Item -Path (Join-Path $variant '*') -Destination $out -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $x 'manifest.json'), (Join-Path $x 'manifest.sig') -Destination $out -Force
  if (Test-Path -LiteralPath (Join-Path $x 'assets')) { Copy-Item -LiteralPath (Join-Path $x 'assets') -Destination $out -Recurse -Force }
  Set-Content -LiteralPath (Join-Path $out 'variant') -Value 'windows-x86_64' -NoNewline -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $out '.lgpm-source') -Value ('file:///' + ($file -replace '\\', '/')) -NoNewline -Encoding ASCII
  $pkg.Staged = $out
  Info ("{0} {1} ({2}) verified and unpacked" -f $m.name, $m.version, $pkg.Sha256.Substring(0, 12))
}

if ($DryRun) {
  Step 'Dry run: nothing was changed'
  foreach ($pkg in $Packages) { Info ("would install {0} -> {1}" -f $pkg.Staged, (Join-Path (Join-Path $UserDir $pkg.Kind) $pkg.Name)) }
  exit 0
}

# ---- 4. install ----
Step 'Install'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($pkg in $Packages) {
  $dest = Join-Path (Join-Path $UserDir $pkg.Kind) $pkg.Name
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  if (Test-Path -LiteralPath $dest) {
    # Outside modules\ and plugins\: Basecamp would load a copy left in there.
    $bak = Join-Path $UserDir ("backups\{0}-{1}" -f $pkg.Name, $stamp)
    New-Item -ItemType Directory -Force -Path (Split-Path $bak) | Out-Null
    Move-Item -LiteralPath $dest -Destination $bak
    Info ("previous {0} kept as {1}" -f $pkg.Name, $bak)
  }
  Copy-Item -LiteralPath $pkg.Staged -Destination $dest -Recurse
  Info ("installed " + $dest)
}

# ---- 5. shortcut + launch ----
if (-not $NoShortcut) {
  $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Logos Blockchain.lnk'
  $sh = New-Object -ComObject WScript.Shell
  $s = $sh.CreateShortcut($lnk)
  $s.TargetPath = $Basecamp.Exe
  $s.Arguments = ('--user-dir "{0}"' -f $UserDir)
  $s.WorkingDirectory = Split-Path $Basecamp.Exe
  $s.Description = 'Logos Basecamp with the Logos Blockchain node (unofficial Windows build)'
  $s.Save()
  Info ("shortcut " + $lnk)
}
Step 'Done'
Info 'Open the Blockchain app in Basecamp and press Quick start: it writes the node config and starts the node.'
Info 'After that the node (and mining, once you start it) comes back by itself when Basecamp or the UI restarts.'
if (-not $NoLaunch) { Start-Process -FilePath $Basecamp.Exe -ArgumentList ('--user-dir "{0}"' -f $UserDir) }
exit 0
