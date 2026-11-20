# WallStreetPro wide-funnel screener: volatility + relative strength + coiling (trading_system.md 2.7)
# Runs against TradingView's public scanner API (scanner.tradingview.com).
# Needs no browser, no Finviz and no Python. Only PowerShell 5.1 or later.
# Writes the watchlist to watchlist_screener.md, which daily_brief.md reads.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File screener.ps1
#   powershell -ExecutionPolicy Bypass -File screener.ps1 -Capital 25000 -CashAvail 8000
# The sizing columns are hints. -Capital and -CashAvail default to the example
# numbers of wiki/context.example.md; WSP_CAPITAL and WSP_CASH override them.
#
# ---------------------------------------------------------------------------
# DESIGN NOTES. Read before changing anything. Each one came out of a real session.
#
#  1. FIXED ADR BAND [2.5, 8.0], no auto-calibration of the floor.
#     The floor is derived from the rules, not from taste: a stock must be able
#     to move enough for a normal swing to be worth the commissions. Loosening
#     the ADR floor "to be able to buy" reintroduces the root bug of v4.0, which
#     filled the list with 2%-ADR large caps where any ADR-based stop sat inside
#     the daily noise.
#
#  2. RELATIVE STRENGTH instead of proximity to the 52-week high.
#     The old filter (within 7/10/15% of the 52-week high, sorted by dollar
#     volume) SELECTED a pathology: names glued to their 52-week high without
#     asking whether that high sits below an older ceiling. Now a WIDE band
#     (-25%, like Minervini's Trend Template) plus a ranking.
#
#  3. EARNINGS FILTER IN THE SCREENER (ErnDays > 7). It is the cheapest and most
#     decisive veto of the system, so it goes first.
#     CAREFUL: the field is UNRELIABLE. In one real case it said 86 days and the
#     stock gapped -17% on earnings the next morning. Nulls pass, marked "n/a",
#     and every finalist is verified live anyway.
#
#  4. EXTRA COLUMNS (EMA21, change, relative volume, Perf.6M, 52-week low) come in
#     the SAME POST at zero cost. They are exactly what the check used to fetch
#     by opening one chart per name (30 MCP calls in one session to discard on
#     data that was already here).
#
#  5. NO all-time-high filter. `High.All` was tested and it is BROKEN: it is not
#     split-adjusted (one ticker returned 149411.40 with the stock at 54.30).
#     A filter on that field accepts or rejects at random depending on the split
#     history. `High.3M` and `High.6M` ARE adjusted (verified against weekly
#     bars), so those are the ones used.
#
#  6. POSITION IN THE 3-MONTH RANGE (Rng3M). 100 = at the high, 0 = at the low.
#     A name that has gone sideways for 3 months and sits in the MIDDLE of the
#     range has no room to the first ceiling. The 35-65% zone is marked `x`.
#     It was a hard veto (rule D9) until v5; v5 keeps it as context.
#
#  7. FIRST RANKING: closeness to the 6-month high ("clean air"), Perf.6M breaks
#     ties. It was introduced because ranking by Perf.6M alone filled the list
#     with names that had old supply overhead.
#     READ THIS WITH v5 IN MIND: the backtest later measured that the clean-air
#     subset is the one with NEGATIVE expectancy (-0.167R against +0.269R for
#     names with supply overhead). v5 breaks ties by `Coil`, the second table.
#
#  8. THEMATIC ETF SLEEVE, by explicit ALLOWLIST. It is an allowlist and not a
#     name filter on purpose: filtering the fund universe by name lets leveraged
#     products through (eight 2x/3x funds slipped in during one session, all of
#     them prohibited by the rules). A new ETF is added by hand to $EtfUniverse.
#
#  9. THE TWO FLOORS WERE RE-DERIVED when the funnel turned out to hold 174 of
#     11,744 stocks, 1.5% of the market. After the change: 626, or 5.3%.
#     Price band 15-80 -> 10-150. The share price does NOT affect the profit:
#     the same dollars in a $5 stock and in a $200 stock earn the same for the
#     same percentage move. What moves the P&L is the ADR, filtered separately.
#
# 10. SIZING IN THE OUTPUT (1R, shares, notional) plus a cash flag. $Capital
#     drives the RISK percentage; $CashAvail is the CEILING of the notional.
#     A notional that does not fit in the cash is flagged: it cannot be executed
#     today no matter how good the setup is.
#
# 11. `vs 6M high` is NOT enough as a proxy for clean air. In one real case a
#     fund sat 5.8% below its 6-month high, but the path up was full of the
#     previous week's supply. Being close to the 6-month high BECAUSE YOU JUST
#     FELL from it is the opposite of having clean air.
#
# 12. API `range` raised from 500 to 3000. The API returned 621 rows with these
#     filters, so 121 in-band names were being dropped SILENTLY, and by the wrong
#     criterion: the sort is Perf.6M descending, so the ones cut were the lowest
#     relative strength, which is exactly where quiet pullbacks live.
#
# 13. `Coil` COLUMN and SECOND RANKING. Coil = (1-month range as % of price) / ADR%.
#     It is the cheap proxy for "a stop below the base costs how many ADRs".
#     Lower = more compressed.
# ---------------------------------------------------------------------------
#
# Hard filter (in the API): types=stock (no ETFs, funds or DRs), price 10-150,
# EMA50 > EMA200, price > EMA50, revenue TTM > 50M (never pre-revenue),
# ADR% (Volatility.M) in [2.5, 8.0].
# Post-processing: mcap >= 500M, dollar volume >= 20M a day, dist EMA50 <= 15%,
# earnings > 7 days away, within 25% of the 52-week high, max 5 per sector.
# ASCII-only on purpose: PowerShell 5.1 parses a BOM-less script as ANSI.

param(
    [double]$Capital    = 10000,   # trading capital: cash plus open positions at cost. RISK % is measured on this
    [double]$CashAvail  = 10000,   # liquid cash. It is the CEILING of the notional
    [double]$RiskTarget = 0.015,   # risk per trade as a fraction of $Capital
    [double]$StopMult   = 1.5      # stop distance in ADR multiples (v5: fixed at 1.5)
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$inv = [Globalization.CultureInfo]::InvariantCulture
if ($env:WSP_CAPITAL -and -not $PSBoundParameters.ContainsKey('Capital'))   { $Capital   = [double]::Parse($env:WSP_CAPITAL, $inv) }
if ($env:WSP_CASH    -and -not $PSBoundParameters.ContainsKey('CashAvail')) { $CashAvail = [double]::Parse($env:WSP_CASH, $inv) }

$OutFile     = Join-Path $PSScriptRoot 'watchlist_screener.md'
$McapFloor   = 5e8      # >= 500M
$DollarVol   = 2e7      # >= 20M a day of dollar volume (avgvol10d * close)
$AdrFloor    = 2.5
$AdrCeiling  = 8.0
$PxFloor     = 10       # below this spreads widen
$PxCeiling   = 150
# ETFs: a wider band. They do not gap on the news of ONE company.
$EtfPxFloor  = 15
$EtfPxCeiling= 300

$ErnMinDays  = 7        # no earnings within 7 days (the rule asks for 5; margin of 2)
$SectorCap   = 5        # cap per sector
$TargetMin   = 20
$TargetMax   = 30
$CoilCap     = 15       # size of the second ranking (by coiling)
$PoolByBand  = @{}      # full in-band pool per band, for the second ranking

$RngDeadLo   = 35       # 3-month range dead zone: entering here is buying
$RngDeadHi   = 65       # the middle of a sideways range
$EtfAdrFloor = 2.2
$EtfDolVol   = 25e6     # ETF: >= 25M a day
$EtfCap      = 12       # max ETFs in the output

# LIVE LEVEL NOTES: multi-year walls the API cannot see (High.All is not
# split-adjusted, note 5). The note is ABOUT THE LEVEL, not about the ticker:
# once price breaks it on volume and retests it from above, remove the entry.
# Listed names are marked `Pat = L` so the reason is visible in the output.
# Format:  'TICKER' = 'wall at 27.30 / 27.60 / 27.95, two rejections. Free only above 27.95 on volume'
$LevelNotes = @{
}

# ALLOWLIST of thematic and sector ETFs. NOT leveraged, NOT inverse, NOT covered-call.
# To add one: check that it is NOT leveraged, inverse or buffered, then add it here.
$EtfUniverse = @(
    # Energy and oil
    'XLE','XOP','OIH','IEO','FCG','USO','BNO','AMLP',
    # Nuclear and uranium
    'URA','URNM','NLR',
    # AI infrastructure, software, cybersecurity, cloud, power grid
    'SMH','SOXX','IGV','CIBR','BUG','ARTY','SKYY','WCLD','GRID','PAVE','DTCR','XLK',
    # Robotics
    'BOTZ','ROBO','ARKQ','IRBO',
    # Spot bitcoin and crypto (no leveraged futures)
    'IBIT','FBTC','BITB','ARKB','BLOK','WGMI',
    # Metals, miners, materials
    'GDX','GDXJ','SIL','SILJ','RING','COPX','XME','SLV','GLD',
    # Biotech, health, innovation
    'XBI','IBB','ARKG','ARKK','XLV',
    # Defense, industrials, infrastructure
    'ITA','XAR','XLI',
    # Remaining SPDR sectors and liquid regionals
    'XLF','XLU','XLP','XLY','XLB','XLRE','XLC','IWM','QQQ','EWY','EWZ','EWJ','KWEB','TAN','LIT'
)

# Returns the in-band rows for a given 52-week-high band.
function Get-Rows($highBand) {
    $filter = '[{"left":"close","operation":"in_range","right":[' + $PxFloor + ',' + $PxCeiling + ']},' +
              '{"left":"EMA50","operation":"greater","right":"EMA200"},' +
              '{"left":"close","operation":"greater","right":"EMA50"},' +
              '{"left":"total_revenue","operation":"greater","right":50000000},' +
              '{"left":"Volatility.M","operation":"in_range","right":[' + $AdrFloor + ',' + $AdrCeiling + ']}]'
    $cols = '"name","close","EMA50","EMA200","RSI","Volatility.M","average_volume_10d_calc",' +
            '"price_52_week_high","sector","market_cap_basic","earnings_release_next_date",' +
            '"EMA21","change","relative_volume_10d_calc","Perf.6M","price_52_week_low",' +
            '"High.3M","Low.3M","High.6M","Perf.5Y","High.1M","Low.1M"'
    $body = '{"filter":' + $filter + ',"options":{"lang":"en"},"symbols":{"query":{"types":["stock"]},"tickers":[]},' +
            '"columns":[' + $cols + '],' +
            '"sort":{"sortBy":"Perf.6M","sortOrder":"desc"},"range":[0,3000]}'
    $resp = Invoke-RestMethod -Uri 'https://scanner.tradingview.com/america/scan' -Method Post -Body $body -ContentType 'application/json' -UseBasicParsing
    $rows = foreach ($item in $resp.data) {
        $d = $item.d
        $close = [double]$d[1]; $ema50 = [double]$d[2]; $high52 = [double]$d[7]
        if (-not $ema50 -or -not $high52) { continue }
        if (-not $d[9]) { continue }                       # null mcap (ETF or fund) -> out
        $mcap = [double]$d[9]
        $dvol = if ($d[6]) { [double]$d[6] * $close } else { 0 }
        $ema21 = if ($d[11]) { [double]$d[11] } else { $null }
        $ernDays = if ($d[10]) {
            [int]([DateTimeOffset]::FromUnixTimeSeconds([long]$d[10]).UtcDateTime - (Get-Date).ToUniversalTime()).TotalDays
        } else { $null }
        $distE50 = [math]::Round((($close / $ema50) - 1) * 100, 1)
        $fromHi  = [math]::Round((($close / $high52) - 1) * 100, 1)
        $hi3 = if ($d[16]) { [double]$d[16] } else { $null }
        $lo3 = if ($d[17]) { [double]$d[17] } else { $null }
        $hi6 = if ($d[18]) { [double]$d[18] } else { $null }
        $p5y = if ($d[19] -ne $null) { [double]$d[19] } else { $null }
        # Position inside the 3-month range. 100 = at the high, 0 = at the low.
        $rngPos = $null
        if ($hi3 -and $lo3 -and $hi3 -gt $lo3) {
            $rngPos = [math]::Round((($close - $lo3) / ($hi3 - $lo3)) * 100, 0)
        }
        # Distance to the 6-month high.
        $fromHi6 = if ($hi6) { [math]::Round((($close / $hi6) - 1) * 100, 1) } else { $null }

        # Position hint, NOT a verdict. The signal is checked on the closed candle.
        #   B = within 3% of the 52-week high, breakout candidate
        #   A = near EMA50 and holding EMA21 (the pullback pattern, removed in v5)
        $pat = if ($fromHi -ge -3) { 'B' }
               elseif ($distE50 -le 5 -and $ema21 -and $close -ge $ema21) { 'A' }
               else { '-' }
        if ($rngPos -ne $null -and $rngPos -ge $RngDeadLo -and $rngPos -le $RngDeadHi) {
            $pat = 'x'
        }
        if ($LevelNotes.ContainsKey([string]$d[0])) { $pat = 'L' }
        # Sizing hint: with a stop of $StopMult x ADR, how many shares risk $RiskTarget.
        $adrPct = if ($d[5]) { [double]$d[5] } else { 0 }
        $oneR   = $StopMult * $adrPct * $close / 100
        $shares = if ($oneR -gt 0) { [math]::Floor(($RiskTarget * $Capital) / $oneR) } else { 0 }
        $notional = [math]::Round($shares * $close, 0)
        # COILING: depth of the 1-month base measured in ADRs. Lower = more compressed.
        $hi1M = if ($d[20]) { [double]$d[20] } else { $null }
        $lo1M = if ($d[21]) { [double]$d[21] } else { $null }
        $base1M = if ($hi1M -and $lo1M -and $close -gt 0) { (($hi1M - $lo1M) / $close) * 100 } else { $null }
        $coil   = if ($base1M -ne $null -and $adrPct -gt 0) { [math]::Round($base1M / $adrPct, 2) } else { $null }
        $fits = ($notional -le $CashAvail)
        $pctCap = if ($Capital -gt 0) { [math]::Round(($notional / $Capital) * 100, 0) } else { 0 }
        [pscustomobject]@{
            Ticker    = [string]$d[0]
            Price     = [math]::Round($close, 2)
            DistEMA50 = $distE50
            FromHigh  = $fromHi
            RngPos    = $rngPos
            FromHi6   = $fromHi6
            Perf5Y    = if ($p5y -ne $null) { [math]::Round($p5y, 0) } else { $null }
            Base1M    = if ($base1M -ne $null) { [math]::Round($base1M, 1) } else { $null }
            Coil      = $coil
            OneR      = [math]::Round($oneR, 2)
            Shares    = $shares
            Notional  = $notional
            PctCap    = $pctCap
            Fits      = $fits
            RSI       = if ($d[4]) { [math]::Round([double]$d[4], 0) } else { $null }
            ADR       = if ($d[5]) { [math]::Round([double]$d[5], 1) } else { $null }
            Sector    = [string]$d[8]
            Mcap      = $mcap
            DolVol    = $dvol
            ErnDays   = $ernDays
            Chg       = if ($d[12] -ne $null) { [math]::Round([double]$d[12], 1) } else { $null }
            VolRel    = if ($d[13]) { [math]::Round([double]$d[13], 2) } else { $null }
            Perf6M    = if ($d[14] -ne $null) { [math]::Round([double]$d[14], 0) } else { $null }
            Low52     = if ($d[15]) { [math]::Round([double]$d[15], 2) } else { $null }
            OverE21   = if ($ema21) { $close -ge $ema21 } else { $null }
            Pat       = $pat
        }
    }
    # Quality, liquidity, not extended, no earnings close, inside the 52-week-high band.
    # A null ErnDays passes (the field is unreliable) and is marked n/a in the output.
    $inband = @($rows | Where-Object {
        $_.Mcap -ge $McapFloor -and $_.DolVol -ge $DollarVol -and $_.DistEMA50 -le 15 -and
        $_.FromHigh -ge $highBand -and
        ($_.ErnDays -eq $null -or $_.ErnDays -gt $ErnMinDays)
    })
    # The FULL in-band pool stays available for the second ranking (by coiling).
    $script:PoolByBand[$highBand] = $inband
    ,@($inband | Sort-Object -Property @{Expression={ if ($_.FromHi6 -ne $null) { $_.FromHi6 } else { -999 } }; Descending=$true},
                              @{Expression='Perf6M'; Descending=$true})
}

# Thematic ETF sleeve, by explicit ALLOWLIST (note 8).
function Get-EtfRows {
    $tk = ($EtfUniverse | ForEach-Object { '"' + $_ + '"' }) -join ','
    $cols = '"name","close","EMA50","EMA200","EMA21","RSI","Volatility.M",' +
            '"average_volume_10d_calc","price_52_week_high","High.3M","Low.3M","High.6M",' +
            '"Perf.6M","change","relative_volume_10d_calc","description"'
    $body = '{"options":{"lang":"en"},"symbols":{"query":{"types":[]},"tickers":[]},' +
            '"filter":[{"left":"name","operation":"in_range","right":[' + $tk + ']}],' +
            '"columns":[' + $cols + '],"range":[0,400]}'
    $resp = Invoke-RestMethod -Uri 'https://scanner.tradingview.com/america/scan' -Method Post -Body $body -ContentType 'application/json' -UseBasicParsing
    $seen = @{}
    $rows = foreach ($item in $resp.data) {
        $d = $item.d
        $t = [string]$d[0]
        if ($seen.ContainsKey($t)) { continue }
        $seen[$t] = $true
        $close = [double]$d[1]; $e50 = [double]$d[2]; $e200 = [double]$d[3]
        if (-not $e50 -or -not $e200 -or -not $close) { continue }
        $e21 = if ($d[4]) { [double]$d[4] } else { $null }
        $hi3 = if ($d[9]) { [double]$d[9] } else { $null }
        $lo3 = if ($d[10]) { [double]$d[10] } else { $null }
        $hi6 = if ($d[11]) { [double]$d[11] } else { $null }
        $rngPos = $null
        if ($hi3 -and $lo3 -and $hi3 -gt $lo3) {
            $rngPos = [math]::Round((($close - $lo3) / ($hi3 - $lo3)) * 100, 0)
        }
        $distE50 = [math]::Round((($close / $e50) - 1) * 100, 1)
        $adr = if ($d[6]) { [math]::Round([double]$d[6], 1) } else { 0 }
        $dvol = if ($d[7]) { [double]$d[7] * $close } else { 0 }
        # Explicit reason for the discard, so the check does not have to work it out.
        $status = 'OK'
        if ($close -lt $EtfPxFloor -or $close -gt $EtfPxCeiling) { $status = 'outside price band' }
        elseif ($e50 -le $e200)      { $status = 'death cross' }
        elseif ($close -le $e50)     { $status = 'below EMA50' }
        elseif ($distE50 -gt 15)     { $status = 'extended' }
        elseif ($adr -lt $EtfAdrFloor) { $status = "ADR<$EtfAdrFloor" }
        elseif ($dvol -lt $EtfDolVol)  { $status = 'illiquid' }
        elseif ($rngPos -ne $null -and $rngPos -ge $RngDeadLo -and $rngPos -le $RngDeadHi) { $status = 'middle of 3M range' }
        $oneR = $StopMult * $adr * $close / 100
        $shares = if ($oneR -gt 0) { [math]::Floor(($RiskTarget * $Capital) / $oneR) } else { 0 }
        $notional = [math]::Round($shares * $close, 0)
        $fits = ($notional -le $CashAvail)
        $pat = if ($hi6 -and (($close / $hi6) - 1) * 100 -ge -3) { 'B' }
               elseif ($distE50 -le 5 -and $e21 -and $close -ge $e21) { 'A' }
               else { '-' }
        [pscustomobject]@{
            Ticker    = $t
            Price     = [math]::Round($close, 2)
            DistEMA50 = $distE50
            FromHigh  = if ($d[8]) { [math]::Round((($close / [double]$d[8]) - 1) * 100, 1) } else { $null }
            FromHi6   = if ($hi6) { [math]::Round((($close / $hi6) - 1) * 100, 1) } else { $null }
            RngPos    = $rngPos
            ADR       = $adr
            RSI       = if ($d[5]) { [math]::Round([double]$d[5], 0) } else { $null }
            Perf6M    = if ($d[12] -ne $null) { [math]::Round([double]$d[12], 0) } else { $null }
            Chg       = if ($d[13] -ne $null) { [math]::Round([double]$d[13], 1) } else { $null }
            VolRel    = if ($d[14]) { [math]::Round([double]$d[14], 2) } else { $null }
            DolVol    = $dvol
            OverE21   = if ($e21) { $close -ge $e21 } else { $null }
            Pat       = $pat
            Status    = $status
            OneR      = [math]::Round($oneR, 2)
            Shares    = $shares
            Notional  = $notional
            PctCap    = if ($Capital -gt 0) { [math]::Round(($notional / $Capital) * 100, 0) } else { 0 }
            Fits      = $fits
        }
    }
    ,@($rows | Where-Object { $_.Status -eq 'OK' } |
        Sort-Object -Property @{Expression={ if ($_.FromHi6 -ne $null) { $_.FromHi6 } else { -999 } }; Descending=$true},
                              @{Expression='Perf6M'; Descending=$true})
}

# Applies the per-sector cap, keeping the incoming order.
function Limit-Sector($list, $cap) {
    $seen = @{}; $out = @()
    foreach ($r in $list) {
        $s = if ($r.Sector) { $r.Sector } else { '(n/a)' }
        if (-not $seen.ContainsKey($s)) { $seen[$s] = 0 }
        if ($seen[$s] -lt $cap) { $out += $r; $seen[$s]++ }
    }
    ,$out
}

# Calibration by 52-week-high band. The ADR floor is never loosened (note 1).
# Minervini uses 25%; it opens to 35% only if the funnel does not reach 20 names.
$bands = @(-25, -35)
$sel = @(); $usedBand = $null
try {
    foreach ($b in $bands) {
        $cand = Limit-Sector (Get-Rows $b) $SectorCap
        if ($cand.Count -gt $sel.Count) { $sel = $cand; $usedBand = $b }
        if ($sel.Count -ge $TargetMin) { break }
    }
} catch {
    "ERROR querying the TradingView scanner: $($_.Exception.Message)" | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
$sel = @($sel | Select-Object -First $TargetMax)

if (-not $sel -or $sel.Count -eq 0) {
    'ERROR: the screener returned no in-band names (check the API and the filters).' | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host 'ERROR: 0 in-band names.' -ForegroundColor Red
    exit 1
}

$stamp   = Get-Date -Format 'yyyy-MM-dd HH:mm'
$band    = [math]::Abs($usedBand)
$riskPct = [math]::Round($RiskTarget * 100, 1)
$shCol   = "sh@$riskPct%"
$flag    = '[no cash]'
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Watchlist Screener: volatility + relative strength + coiling (auto-generated)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("- Generated: $stamp (local time). Source: TradingView scanner API")
[void]$sb.AppendLine("- Filter: stocks, price $PxFloor-$PxCeiling, revenue TTM > 50M, dollar volume >= 20M a day, EMA50 > EMA200, price > EMA50")
[void]$sb.AppendLine("- ADR% (Volatility.M) in [$AdrFloor, $AdrCeiling], dist EMA50 <= 15%, mcap >= 500M, earnings > $ErnMinDays days away, max $SectorCap per sector")
[void]$sb.AppendLine("- Within $band% of the 52-week high. First table ranked by closeness to the 6-month high, Perf.6M breaks ties. $($sel.Count) names")
[void]$sb.AppendLine("- ``1R`` = $StopMult x ADR in dollars. ``$shCol`` = shares that risk $riskPct% of trading capital (`$$Capital).")
[void]$sb.AppendLine("- ``notional`` = cost and % of trading capital. **$flag = it does not fit in the available cash (`$$CashAvail): not executable today.**")
[void]$sb.AppendLine("- ``Pat = x``: inside the $RngDeadLo-$RngDeadHi% zone of its 3-month range. Context only since v5.")
[void]$sb.AppendLine('')
[void]$sb.AppendLine("| # | Ticker | Price | Pat | Sector | dEMA50 | vs 52w high | **vs 6M high** | **Rng3M** | ADR | **Coil** | **1R** | **$shCol** | **notional** | Perf6M | RelVol | >E21 | RSI | Ern |")
[void]$sb.AppendLine('|--:|:---|---:|:--:|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|:--:|---:|---:|')
$n = 0
foreach ($r in $sel) {
    $n++
    $ern  = if ($r.ErnDays -ne $null) { "$($r.ErnDays)" } else { 'n/a' }
    $e21  = if ($r.OverE21 -eq $true) { 'yes' } elseif ($r.OverE21 -eq $false) { 'NO' } else { '?' }
    $vr   = if ($r.VolRel -ne $null) { "$($r.VolRel)x" } else { '-' }
    $h6   = if ($r.FromHi6 -ne $null) { "$($r.FromHi6)%" } else { '-' }
    $rp   = if ($r.RngPos -ne $null) { "$($r.RngPos)%" } else { '-' }
    $fitTxt = if ($r.Fits) { "`$$($r.Notional)" } else { "`$$($r.Notional) $flag" }
    $co   = if ($r.Coil -ne $null) { "$($r.Coil)x" } else { '-' }
    [void]$sb.AppendLine("| $n | $($r.Ticker) | `$$($r.Price) | $($r.Pat) | $($r.Sector) | +$($r.DistEMA50)% | $($r.FromHigh)% | $h6 | $rp | $($r.ADR)% | $co | `$$($r.OneR) | $($r.Shares) | $fitTxt ($($r.PctCap)%) | $($r.Perf6M)% | $vr | $e21 | $($r.RSI) | $ern |")
}
[void]$sb.AppendLine('')

# SECOND RANKING, by COILING (1-month base / ADR; lower = more compressed).
# The first ranking structurally rewards the name that JUST broke out, the one
# that arrives with its base already far below. This table sorts the SAME pool
# the other way. An asterisk marks names that are also in the first table.
$coilList = @()
if ($usedBand -ne $null -and $PoolByBand.ContainsKey($usedBand)) {
    $coilList = @($PoolByBand[$usedBand] | Where-Object { $_.Coil -ne $null } | Sort-Object Coil)
}
if ($coilList.Count -gt 0) {
    $coilSel = Limit-Sector $coilList $SectorCap
    $coilSel = @($coilSel | Select-Object -First $CoilCap)
    $inMain = @{}
    foreach ($r in $sel) { $inMain[$r.Ticker] = $true }
    [void]$sb.AppendLine('## Second ranking: THE MOST COMPRESSED (`Coil` = 1-month range / ADR)')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("- Same pool of $($coilList.Count) in-band names, **different order**: lowest ``Coil`` first.")
    [void]$sb.AppendLine('- Low `Coil` = the 1-month base measures few ADRs. **This is the v5 tie-break** when more than one name signals.')
    [void]$sb.AppendLine('- `*` = also in the table above.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("| # | Ticker | Price | Pat | dEMA50 | **Coil** | Base1M | ADR | vs 52w high | **Rng3M** | **1R** | **$shCol** | **notional** | >E21 | RSI | Perf6M | Ern |")
    [void]$sb.AppendLine('|--:|:---|---:|:--:|---:|---:|---:|---:|---:|---:|---:|---:|---:|:--:|---:|---:|---:|')
    $m = 0
    foreach ($r in $coilSel) {
        $m++
        $star = if ($inMain.ContainsKey($r.Ticker)) { '*' } else { '' }
        $ern  = if ($r.ErnDays -ne $null) { "$($r.ErnDays)" } else { 'n/a' }
        $e21  = if ($r.OverE21 -eq $true) { 'yes' } elseif ($r.OverE21 -eq $false) { 'NO' } else { '?' }
        $rp   = if ($r.RngPos -ne $null) { "$($r.RngPos)%" } else { '-' }
        $b1   = if ($r.Base1M -ne $null) { "$($r.Base1M)%" } else { '-' }
        $fitTxt = if ($r.Fits) { "`$$($r.Notional)" } else { "`$$($r.Notional) $flag" }
        [void]$sb.AppendLine("| $m | $($r.Ticker)$star | `$$($r.Price) | $($r.Pat) | +$($r.DistEMA50)% | **$($r.Coil)x** | $b1 | $($r.ADR)% | $($r.FromHigh)% | $rp | `$$($r.OneR) | $($r.Shares) | $fitTxt | $e21 | $($r.RSI) | $($r.Perf6M)% | $ern |")
    }
    [void]$sb.AppendLine('')
}

# Thematic ETF sleeve (note 8).
try {
    $etf = Get-EtfRows
    if ($etf.Count -gt $EtfCap) { $etf = @($etf | Select-Object -First $EtfCap) }
} catch {
    $etf = @()
    Write-Host "WARNING: the ETF scan failed ($($_.Exception.Message)). Continuing with stocks only." -ForegroundColor Yellow
}
[void]$sb.AppendLine("## Thematic ETFs ($($EtfUniverse.Count) scanned by allowlist)")
[void]$sb.AppendLine('')
[void]$sb.AppendLine("- Filter: EMA50 > EMA200, price > EMA50, dist EMA50 <= 15%, ADR >= $EtfAdrFloor%, dollar volume >= 25M a day, outside the 3M mid-range")
[void]$sb.AppendLine('- **No earnings** (that guardrail does not apply to ETFs). Stop: rule D3 if ADR < 2% (at least 2.0x ADR), otherwise the standard stop.')
[void]$sb.AppendLine('')
if ($etf.Count -eq 0) {
    [void]$sb.AppendLine('**None passes today.**')
} else {
    [void]$sb.AppendLine("| # | Ticker | Price | Pat | dEMA50 | vs 52w high | **vs 6M high** | **Rng3M** | ADR | **1R** | **$shCol** | **notional** | RSI | Perf6M | >E21 |")
    [void]$sb.AppendLine('|--:|:---|---:|:--:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|:--:|')
    $m = 0
    foreach ($r in $etf) {
        $m++
        $e21 = if ($r.OverE21 -eq $true) { 'yes' } elseif ($r.OverE21 -eq $false) { 'NO' } else { '?' }
        $h6  = if ($r.FromHi6 -ne $null) { "$($r.FromHi6)%" } else { '-' }
        $rp  = if ($r.RngPos -ne $null) { "$($r.RngPos)%" } else { '-' }
        $fitTxt = if ($r.Fits) { "`$$($r.Notional)" } else { "`$$($r.Notional) $flag" }
        [void]$sb.AppendLine("| $m | $($r.Ticker) | `$$($r.Price) | $($r.Pat) | +$($r.DistEMA50)% | $($r.FromHigh)% | $h6 | $rp | $($r.ADR)% | `$$($r.OneR) | $($r.Shares) | $fitTxt ($($r.PctCap)%) | $($r.RSI) | $($r.Perf6M)% | $e21 |")
    }
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('**ETFs:** ' + (($etf | ForEach-Object { $_.Ticker }) -join ' - '))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('**Tickers:** ' + (($sel | ForEach-Object { $_.Ticker }) -join ' - '))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('> **How to read this.** `Pat` is a position hint, not a verdict:')
[void]$sb.AppendLine('> B = within 3% of the high (52-week for stocks, 6-month for ETFs). A = dist EMA50 <= 5% and above EMA21.')
[void]$sb.AppendLine("> x = inside the $RngDeadLo-$RngDeadHi% zone of its 3-month range.")
if ($LevelNotes.Count -gt 0) {
    [void]$sb.AppendLine('> L = it has a live level note:')
    foreach ($k in $LevelNotes.Keys) { [void]$sb.AppendLine("> - **$k**: $($LevelNotes[$k])") }
}
[void]$sb.AppendLine('>')
[void]$sb.AppendLine('> The signal itself is not in this file: it is a close above the high of the previous 10 sessions,')
[void]$sb.AppendLine('> read on the closed candle (trading_system.md 2.3).')
[void]$sb.AppendLine('>')
[void]$sb.AppendLine('> `ADR` is Volatility.M, the operating ADR20: **never recompute it by hand.**')
[void]$sb.AppendLine('> `RelVol` is volume against its 10-day average. Context, not a veto.')
[void]$sb.AppendLine("> ``Ern`` is already filtered to > $ErnMinDays days, but the field has failed before: verify it live.")
[void]$sb.AppendLine('>')
[void]$sb.AppendLine('> Multi-year ceilings are NOT filtered here: `High.All` comes without split adjustment.')
[void]$sb.AppendLine('> `High.3M` and `High.6M` are adjusted, which is why those are the ones used.')

$sb.ToString() | Out-File -FilePath $OutFile -Encoding utf8

Write-Host "OK: $($sel.Count) stocks + $($etf.Count) ETFs (ADR [$AdrFloor,$AdrCeiling], 52w-high band $band%) -> watchlist_screener.md" -ForegroundColor Green
$sel | Format-Table Ticker, Price, Pat, RngPos, FromHi6, ADR, Coil, Perf6M, DistEMA50, FromHigh, ErnDays, Sector -AutoSize
Write-Host 'Thematic ETFs that pass:' -ForegroundColor Cyan
$etf | Format-Table Ticker, Price, Pat, RngPos, FromHi6, ADR, RSI, Perf6M, DistEMA50, FromHigh -AutoSize
