<#
.SYNOPSIS
  One-time setup of WallStreetPro on Windows.

.DESCRIPTION
  1. Checks the prerequisites: git, Node.js, Python, Claude Code, TradingView Desktop.
  2. Clones the third-party TradingView MCP server and installs its dependencies.
  3. Registers that server with Claude Code, under the name "tradingview", for this folder.
  4. Creates a Python virtual environment for the backtest and installs requirements.txt.
  5. Creates current_state.md and trade_log.md from the example templates.

  It is safe to run again: every step checks before it acts, and nothing that
  already exists is overwritten.

.PARAMETER McpPath
  Where the TradingView MCP server lives or should be cloned.
  Default: %USERPROFILE%\tradingview-mcp-jackson, or TV_MCP_REPO if it is set.

.PARAMETER SkipMcp
  Do not clone or register the MCP server.

.PARAMETER SkipBacktest
  Do not create the Python environment for the backtest.

.PARAMETER DryRun
  Print what would be done without changing anything.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File setup.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File setup.ps1 -McpPath D:\tools\tradingview-mcp -SkipBacktest
#>
param(
    [string]$McpPath = $(if ($env:TV_MCP_REPO) { $env:TV_MCP_REPO } else { Join-Path $env:USERPROFILE 'tradingview-mcp-jackson' }),
    [switch]$SkipMcp,
    [switch]$SkipBacktest,
    [switch]$DryRun
)

# ASCII-only on purpose: PowerShell 5.1 parses a BOM-less script as ANSI.
# 'Continue' on purpose: with 'Stop', PowerShell 5.1 turns the first stderr line
# of a native command into a terminating error. Failures are checked by exit code.
$ErrorActionPreference = 'Continue'

$Root       = $PSScriptRoot
$McpRepoUrl = 'https://github.com/LewisWJackson/tradingview-mcp-jackson.git'
$McpName    = 'tradingview'   # .claude/settings.json allows mcp__tradingview__*, so the name is fixed
$DefaultMcp = Join-Path $env:USERPROFILE 'tradingview-mcp-jackson'
$Problems   = New-Object System.Collections.Generic.List[string]

function Write-Step($text) { Write-Host ''; Write-Host $text -ForegroundColor Cyan }
function Write-Ok($text)   { Write-Host "  [ok]   $text" -ForegroundColor Green }
function Write-Skip($text) { Write-Host "  [skip] $text" -ForegroundColor DarkGray }
function Write-Do($text)   { Write-Host "  [run]  $text" -ForegroundColor Yellow }
function Write-Bad($text)  { Write-Host "  [miss] $text" -ForegroundColor Red; $script:Problems.Add($text) }

# Looks on PATH first, then in the usual install folders, because a terminal
# opened before an install does not see the new PATH yet.
function Find-Tool($name, [string[]]$fallbacks) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source -and $cmd.Source -notmatch '\\WindowsApps\\') { return $cmd.Source }
    foreach ($pattern in $fallbacks) {
        $hit = Get-Item -Path $pattern -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Find-TradingView {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'TradingView\TradingView.exe'),
        (Join-Path $env:ProgramFiles 'TradingView\TradingView.exe')
    )
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'TradingView\TradingView.exe') }
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    try {
        $pkg = Get-AppxPackage -Name '*TradingView*' -ErrorAction Stop | Select-Object -First 1
        if ($pkg) { return (Join-Path $pkg.InstallLocation 'TradingView.exe') }
    } catch { }
    return $null
}

Write-Host ''
Write-Host ' WallStreetPro setup' -ForegroundColor White
Write-Host " Project folder: $Root"
if ($DryRun) { Write-Host ' DRY RUN: nothing will be changed' -ForegroundColor Yellow }

# ---------------------------------------------------------------- 1. prerequisites
Write-Step '[1/5] Prerequisites'

$git = Find-Tool 'git' @("$env:ProgramFiles\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")
if ($git) { Write-Ok "git: $git" } else { Write-Bad 'git not found. Install it from https://git-scm.com/download/win' }

$node = Find-Tool 'node' @("$env:ProgramFiles\nodejs\node.exe")
$npm  = $null
if ($node) {
    $nodeVer = (& $node --version) -replace '^v', ''
    $nodeMajor = 0
    [void][int]::TryParse(($nodeVer -split '\.')[0], [ref]$nodeMajor)
    if ($nodeMajor -ge 18) { Write-Ok "Node.js $nodeVer" } else { Write-Bad "Node.js $nodeVer is too old. The MCP server needs 18 or later: https://nodejs.org/" }
    $npm = Find-Tool 'npm.cmd' @((Join-Path (Split-Path $node -Parent) 'npm.cmd'))
} else {
    Write-Bad 'Node.js not found. Install the LTS version from https://nodejs.org/'
}

$claude = Find-Tool 'claude' @("$env:USERPROFILE\.local\bin\claude.exe", "$env:APPDATA\npm\claude.cmd")
if ($claude) { Write-Ok "Claude Code: $claude" }
else { Write-Bad 'Claude Code not found. Install it (npm install -g @anthropic-ai/claude-code), run "claude" once to log in, then run this setup again.' }

$python = $null
if (-not $SkipBacktest) {
    $python = Find-Tool 'python' @("$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe", "$env:ProgramFiles\Python3*\python.exe")
    if ($python) {
        $pyVer = (& $python --version 2>&1 | Out-String).Trim()
        Write-Ok "$pyVer"
    } else {
        Write-Bad 'Python 3 not found. It is only needed for the backtest: https://www.python.org/downloads/ (or re-run with -SkipBacktest)'
    }
}

$tv = Find-TradingView
if ($tv) { Write-Ok "TradingView Desktop: $tv" }
else { Write-Bad 'TradingView Desktop not found. Install it from https://www.tradingview.com/desktop/ and log in once.' }

# ---------------------------------------------------------------- 2. MCP server
Write-Step '[2/5] TradingView MCP server (third party, not part of this repo)'
$serverJs = Join-Path $McpPath 'src\server.js'

if ($SkipMcp) {
    Write-Skip 'skipped (-SkipMcp)'
} else {
    if (Test-Path -LiteralPath $serverJs) {
        Write-Ok "already cloned at $McpPath"
    } elseif (-not $git) {
        Write-Bad "cannot clone the MCP server without git. Target: $McpPath"
    } else {
        Write-Do "git clone $McpRepoUrl `"$McpPath`""
        if (-not $DryRun) {
            & $git clone --depth 1 $McpRepoUrl $McpPath
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $serverJs)) { Write-Bad "git clone failed. Clone $McpRepoUrl by hand into $McpPath" }
        }
    }

    if ((Test-Path -LiteralPath $serverJs) -or $DryRun) {
        if (Test-Path -LiteralPath (Join-Path $McpPath 'node_modules')) {
            Write-Ok 'dependencies already installed'
        } elseif (-not $npm) {
            Write-Bad "npm not found. Run 'npm install' inside $McpPath"
        } else {
            Write-Do "npm install (in $McpPath)"
            if (-not $DryRun) {
                Push-Location $McpPath
                & $npm install --no-fund --no-audit
                $code = $LASTEXITCODE
                Pop-Location
                if ($code -ne 0) { Write-Bad "npm install failed in $McpPath" }
            }
        }
    }

    # WALLSTREETPRO_START.bat reads TV_MCP_REPO and falls back to the default folder.
    if ($McpPath.TrimEnd('\') -ne $DefaultMcp.TrimEnd('\') -and $env:TV_MCP_REPO -ne $McpPath) {
        Write-Do "set user environment variable TV_MCP_REPO=$McpPath"
        if (-not $DryRun) { [Environment]::SetEnvironmentVariable('TV_MCP_REPO', $McpPath, 'User') }
    }
}

# ---------------------------------------------------------------- 3. Claude Code registration
Write-Step "[3/5] Register the MCP server with Claude Code as `"$McpName`""
if ($SkipMcp) {
    Write-Skip 'skipped (-SkipMcp)'
} elseif (-not $claude) {
    Write-Skip 'Claude Code is missing, see step 1'
} elseif (-not $node) {
    Write-Skip 'Node.js is missing, see step 1'
} elseif (-not (Test-Path -LiteralPath $serverJs) -and -not $DryRun) {
    Write-Skip 'the MCP server is not on disk, see step 2'
} else {
    # Local scope: the registration is private to you and applies to this folder only.
    Push-Location $Root
    $current = (& $claude mcp get $McpName 2>$null | Out-String)
    $found = ($LASTEXITCODE -eq 0)
    if ($found -and $current -match [regex]::Escape($serverJs)) {
        Write-Ok 'already registered and pointing at this server'
    } elseif ($found) {
        Write-Bad "a server named `"$McpName`" is already registered with other settings. Review it with: claude mcp get $McpName   (to replace it: claude mcp remove $McpName, then run this setup again)"
    } else {
        Write-Do "claude mcp add $McpName --scope local -- node `"$serverJs`""
        if (-not $DryRun) {
            & $claude mcp add $McpName --scope local -- node $serverJs
            if ($LASTEXITCODE -ne 0) { Write-Bad "claude mcp add failed. Run it by hand from ${Root}: claude mcp add $McpName -- node `"$serverJs`"" }
            else { Write-Ok 'registered' }
        }
    }
    Pop-Location
}

# ---------------------------------------------------------------- 4. backtest environment
Write-Step '[4/5] Python environment for the backtest'
$venvPy = Join-Path $Root 'backtest\.venv\Scripts\python.exe'
if ($SkipBacktest) {
    Write-Skip 'skipped (-SkipBacktest)'
} elseif (-not $python) {
    Write-Skip 'Python is missing, see step 1'
} else {
    if (Test-Path -LiteralPath $venvPy) {
        Write-Ok 'virtual environment already exists at backtest\.venv'
    } else {
        Write-Do 'python -m venv backtest\.venv'
        if (-not $DryRun) {
            & $python -m venv (Join-Path $Root 'backtest\.venv')
            if ($LASTEXITCODE -ne 0) { Write-Bad 'could not create the virtual environment' }
        }
    }
    if ((Test-Path -LiteralPath $venvPy) -or $DryRun) {
        Write-Do 'pip install -r requirements.txt'
        if (-not $DryRun) {
            & $venvPy -m pip install --quiet --disable-pip-version-check -r (Join-Path $Root 'requirements.txt')
            if ($LASTEXITCODE -ne 0) { Write-Bad 'pip install failed. Check the network connection and run this setup again.' }
            else { Write-Ok 'yfinance, pandas and numpy installed' }
        }
    }
}

# ---------------------------------------------------------------- 5. state files
Write-Step '[5/5] Personal state files (gitignored, created from the templates)'
foreach ($pair in @(@('current_state.example.md', 'current_state.md'), @('trade_log.example.md', 'trade_log.md'))) {
    $from = Join-Path $Root $pair[0]
    $to   = Join-Path $Root $pair[1]
    if (Test-Path -LiteralPath $to) {
        Write-Ok "$($pair[1]) already exists, left untouched"
    } elseif (-not (Test-Path -LiteralPath $from)) {
        Write-Bad "template $($pair[0]) is missing from the repo"
    } else {
        Write-Do "copy $($pair[0]) -> $($pair[1])"
        if (-not $DryRun) { Copy-Item -LiteralPath $from -Destination $to }
    }
}

# ---------------------------------------------------------------- summary
Write-Host ''
if ($Problems.Count -eq 0 -and $DryRun) {
    Write-Host ' Dry run finished: nothing was changed. Run it again without -DryRun.' -ForegroundColor Yellow
} elseif ($Problems.Count -eq 0) {
    Write-Host ' Setup complete.' -ForegroundColor Green
} else {
    Write-Host " Setup finished with $($Problems.Count) item(s) to fix:" -ForegroundColor Yellow
    foreach ($p in $Problems) { Write-Host "   - $p" -ForegroundColor Yellow }
    Write-Host ' Fix them and run this setup again. Steps already done are skipped.'
}
Write-Host ''
Write-Host ' What is left to do by hand, once:'
Write-Host '   1. Open TradingView Desktop, log in, open the Pine Editor, paste'
Write-Host '      wallstreetpro_v3_unified.pine, save it and add it to the chart.'
Write-Host '   2. Open current_state.md and replace the example numbers with yours.'
Write-Host '   3. Run WALLSTREETPRO_START.bat after the New York close.'
Write-Host ''
if ($Problems.Count -gt 0) { exit 1 }
exit 0
