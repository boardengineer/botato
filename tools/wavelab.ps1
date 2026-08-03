# WaveLab runner: replay a captured Brotato wave snapshot with the bot, N times.
#
#   wavelab.ps1 capture [-Note tag]      harvest newest run snapshot into the library
#   wavelab.ps1 list                     show the snapshot library
#   wavelab.ps1 run <snapshot> [-Count 3] [-Seed 0] [-Speed 1]
#                                        replay a snapshot; -Seed 0 = fresh seed per
#                                        iteration, fixed seed = repeat circumstances
#   wavelab.ps1 bench [<snapshot>] [-Count 6] [-Note "what changed"]
#                                        run one steering benchmark (default loud-w11)
#                                        and append the result to bench-history.csv
#   wavelab.ps1 screen <snapshot>        run x3, verdict: does the current steering
#                                        die often enough to join the test bed?
#   wavelab.ps1 bed [-Count N] [-Note ..] [-Only filter]
#                                        bench every member of tools\bench\testbed.txt
#                                        (-Only runs a subset; use for chunked sweeps)
#
# Snapshots live in C:\brotato\wavelab\snapshots, results in C:\brotato\wavelab\results.

param(
    [Parameter(Position = 0, Mandatory = $true)][ValidateSet('capture', 'list', 'run', 'bench', 'screen', 'bed')][string]$Command,
    [Parameter(Position = 1)][string]$Snapshot,
    [int]$Count = 3,
    [int]$Seed = 0,
    [double]$Speed = 1.0,
    [string]$Note = '',
    [string]$Only = '',
    [switch]$All
)

$ErrorActionPreference = 'Stop'
$GameExe = 'C:\godot\steamgodot\godotsteam.36.editor.windows.64.exe'
$GamePath = 'C:\brotato\decompiled-autobattler'
$SaveDir = "$env:APPDATA\BrotatoDecompiled\user"
$RunFile = "$SaveDir\run_v3_0.json"
$SnapDir = 'C:\brotato\wavelab\snapshots'
$ResultDir = 'C:\brotato\wavelab\results'
$Ledger = 'C:\brotato\wavelab\bench-history.csv'
$Manifest = "$PSScriptRoot\bench\testbed.txt"
$TimeoutSec = 300

New-Item -ItemType Directory -Force $SnapDir, $ResultDir | Out-Null

function Read-SnapshotMeta([string]$path) {
    try { $j = Get-Content $path -Raw | ConvertFrom-Json } catch { return $null }
    $s = $j.current_run_state
    if (-not $s -or -not $s.has_run_state) { return $null }
    [pscustomobject]@{
        Wave      = [int]$s.current_wave + 1   # wave that will be PLAYED
        Character = ($s.players_data[0].current_character -replace 'character_', '')
        HP        = [int]$s.players_data[0].current_health
        Danger    = [int]$s.current_difficulty
    }
}

switch ($Command) {
    'capture' {
        # Newest first: for duplicate wave/hp names (shop re-saves of the same
        # wave) the most recent — the final post-shop state — claims the name
        $candidates = @(Get-Item $RunFile -ErrorAction SilentlyContinue) + @(Get-ChildItem "$SaveDir\run_v3_0_*.bak" -ErrorAction SilentlyContinue) |
            Where-Object { $_ } | Sort-Object LastWriteTime -Descending
        $captured = 0
        foreach ($c in $candidates) {
            $meta = Read-SnapshotMeta $c.FullName
            if (-not $meta) { continue }
            $tag = if ($Note) { "-$Note" } else { '' }
            $name = '{0}-w{1}-{2}-d{3}-hp{4}{5}.json' -f (Get-Date -Format 'yyyyMMdd'), $meta.Wave, $meta.Character, $meta.Danger, $meta.HP, $tag
            $dest = Join-Path $SnapDir $name
            if ($All -and (Test-Path $dest)) { Write-Host "skip (exists): $name"; continue }
            Copy-Item $c.FullName $dest
            Write-Host "captured: $($c.Name) -> $name"
            $captured++
            if (-not $All) { return }
        }
        if (-not $captured) { Write-Host 'no snapshot with run state found (play to a shop first, or check .bak files)' }
    }

    'list' {
        Get-ChildItem "$SnapDir\*.json" | ForEach-Object {
            $meta = Read-SnapshotMeta $_.FullName
            if ($meta) { [pscustomobject]@{ Snapshot = $_.Name; Wave = $meta.Wave; Character = $meta.Character; Danger = $meta.Danger; HP = $meta.HP } }
        } | Format-Table -AutoSize
    }

    'run' {
        if (-not $Snapshot) { throw 'usage: wavelab.ps1 run <snapshot> [-Count N] [-Seed X] [-Speed F]' }
        $snapPath = if (Test-Path $Snapshot) { $Snapshot } else { Join-Path $SnapDir $Snapshot }
        if (-not (Test-Path $snapPath)) { throw "snapshot not found: $snapPath" }
        $meta = Read-SnapshotMeta $snapPath
        if (-not $meta) { throw "not a valid run snapshot: $snapPath" }
        if (Get-Process -Name 'godotsteam*' -ErrorAction SilentlyContinue) { throw 'a game instance is already running; close it first' }

        # Preserve whatever run save the user currently has, once per invocation
        if (Test-Path $RunFile) { Copy-Item $RunFile "$ResultDir\run_v3_0.pre-wavelab.json" -Force }

        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Write-Host ("replaying wave {0} ({1}, danger {2}, hp {3}) x{4}  seed={5} speed={6}" -f $meta.Wave, $meta.Character, $meta.Danger, $meta.HP, $Count, $Seed, $Speed)
        $results = @()

        for ($i = 1; $i -le $Count; $i++) {
            Copy-Item $snapPath $RunFile -Force
            $iterSeed = if ($Seed -ne 0) { $Seed } else { Get-Random -Minimum 1 -Maximum 2147483646 }
            $log = "$ResultDir\$stamp-i$i.log"
            # NOTE: no --no-window: pause.gd advances its boot state machine in
            # _draw(), so the game hangs at boot without a rendered window
            $p = Start-Process -FilePath $GameExe -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err" -ArgumentList @(
                '--path', $GamePath, "--wavelab=1", "--wavelab-seed=$iterSeed", "--wavelab-speed=$Speed")
            if (-not $p.WaitForExit($TimeoutSec * 1000)) {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                Write-Host "  iter ${i}: TIMEOUT after ${TimeoutSec}s (log: $log)"
                $results += [pscustomobject]@{ Iter = $i; Outcome = 'timeout'; Dmg = ''; HpEnd = ''; T = ''; Seed = $iterSeed }
                continue
            }
            $line = Select-String -Path $log -Pattern '^WAVELAB RESULT' | Select-Object -Last 1
            if ($line -and $line.Line -match 'outcome=(\w+) dmg=(\d+) hp_end=(\d+) t=(\d+)') {
                $results += [pscustomobject]@{ Iter = $i; Outcome = $Matches[1]; Dmg = [int]$Matches[2]; HpEnd = [int]$Matches[3]; T = [int]$Matches[4]; Seed = $iterSeed }
                Write-Host ("  iter {0}: {1}  dmg={2} hp_end={3} t={4}s" -f $i, $Matches[1], $Matches[2], $Matches[3], $Matches[4])
            } else {
                $err = Select-String -Path $log -Pattern '^WAVELAB ERROR' | Select-Object -Last 1
                $why = if ($err) { $err.Line } else { 'no RESULT line (game closed early?)' }
                Write-Host "  iter ${i}: FAILED - $why (log: $log)"
                $results += [pscustomobject]@{ Iter = $i; Outcome = 'error'; Dmg = ''; HpEnd = ''; T = ''; Seed = $iterSeed }
            }
        }

        $ok = @($results | Where-Object Outcome -in 'survived', 'died')
        if ($ok.Count) {
            $survived = @($ok | Where-Object Outcome -eq 'survived').Count
            Write-Host ''
            Write-Host ("summary: {0}/{1} survived, avg dmg {2:n0}" -f $survived, $ok.Count, ($ok | Measure-Object Dmg -Average).Average)
        }
        $results | Export-Csv "$ResultDir\$stamp-summary.csv" -NoTypeInformation
        Write-Host "results: $ResultDir\$stamp-summary.csv"
    }

    'bench' {
        # One steering benchmark batch against a bed snapshot (default: the
        # founding loud-w11 wave). Appends a commit-stamped row to the ledger;
        # the hit-source split is where regressions the total hides show up.
        $benchSnap = if ($Snapshot) { $Snapshot } else { '20260802-w11-loud-d5-hp59.json' }
        $ledger = $Ledger
        if (-not $PSBoundParameters.ContainsKey('Count')) { $Count = 6 } # bench default is 6, not run's 3

        $repo = 'C:\Brotato Mods\botato'
        $commit = (git -C $repo rev-parse --short HEAD 2>$null)
        $dirty = if (git -C $repo status --porcelain 2>$null) { '+dirty' } else { '' }

        & $PSCommandPath run $benchSnap -Count $Count -Speed $Speed

        $sum = Get-ChildItem "$ResultDir\*-summary.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $rows = @(Import-Csv $sum.FullName | Where-Object Outcome -in 'survived', 'died')
        if (-not $rows.Count) { Write-Host 'bench: no scored iterations, nothing recorded'; break }
        $batchStamp = $sum.Name -replace '-summary\.csv$', ''
        $hits = Get-ChildItem "$ResultDir\$batchStamp-i*.log" | Select-String -Pattern 'BOTLOG HIT.*src=(\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }
        $entry = [pscustomobject]@{
            Date        = Get-Date -Format 'yyyy-MM-dd HH:mm'
            Commit      = "$commit$dirty"
            Snapshot    = $benchSnap
            Note        = $Note
            Runs        = $rows.Count
            Survived    = @($rows | Where-Object Outcome -eq 'survived').Count
            AvgDmg      = [math]::Round(($rows | Measure-Object Dmg -Average).Average, 0)
            AvgT        = [math]::Round(($rows | Measure-Object T -Average).Average, 0)
            DmgPerSec   = [math]::Round((($rows | Measure-Object Dmg -Sum).Sum / [math]::Max(($rows | Measure-Object T -Sum).Sum, 1)), 2)
            CrocHits    = @($hits | Where-Object { $_ -eq 'croc' }).Count
            PursuerHits = @($hits | Where-Object { $_ -eq 'pursuer' }).Count
            ProjHits    = @($hits | Where-Object { $_ -like 'proj*' }).Count
            OtherHits   = @($hits | Where-Object { $_ -ne 'croc' -and $_ -ne 'pursuer' -and $_ -notlike 'proj*' }).Count
            Batch       = $batchStamp
        }
        $entry | Export-Csv $ledger -NoTypeInformation -Append
        Write-Host ''
        Write-Host 'bench history (last 8):'
        Import-Csv $ledger | Select-Object -Last 8 | Format-Table Date, Commit, @{n = 'Snapshot'; e = { $_.Snapshot -replace '^\d{8}-', '' -replace '\.json$', '' } }, Note, @{n = 'Surv'; e = { "$($_.Survived)/$($_.Runs)" } }, AvgDmg, AvgT, DmgPerSec, CrocHits, PursuerHits, ProjHits -AutoSize
    }

    'screen' {
        # Test-bed admission: does the CURRENT steering die often enough here
        # for this snapshot to be a useful regression target?
        if (-not $Snapshot) { throw 'usage: wavelab.ps1 screen <snapshot>' }
        & $PSCommandPath bench $Snapshot -Count 3 -Note "screen: $Snapshot"
        $row = Import-Csv $Ledger | Select-Object -Last 1
        if ($row.Snapshot -ne $Snapshot) { throw "screen: last ledger row is for '$($row.Snapshot)', not '$Snapshot' — bench batch failed?" }
        $died = [int]$row.Runs - [int]$row.Survived
        Write-Host ''
        if ([int]$row.Runs -ge 3 -and $died -ge 2) {
            Write-Host ("BED CANDIDATE: {0} died {1}/{2} (add to tools\bench\testbed.txt + copy snapshot to tools\bench\)" -f $Snapshot, $died, $row.Runs) -ForegroundColor Green
        } else {
            Write-Host ("rejected: {0} died only {1}/{2} (needs >=2/3)" -f $Snapshot, $died, $row.Runs) -ForegroundColor Yellow
        }
    }

    'bed' {
        # Bench every member of the test bed. -Only <substring> restricts to
        # matching members (chunked sweeps: the full bed at -Count 10 runs
        # ~90-120 min, far past any single background-task window).
        if (-not (Test-Path $Manifest)) { throw "no test bed manifest: $Manifest" }
        $members = @(Get-Content $Manifest | ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ })
        if ($Only) { $members = @($members | Where-Object { $_ -like "*$Only*" }) }
        if (-not $members.Count) { throw 'bed: no members match' }
        Write-Host ("bed sweep: {0} member(s) x{1}" -f $members.Count, $Count)
        foreach ($m in $members) {
            & $PSCommandPath bench $m -Count $Count -Note $Note
        }
        Write-Host ''
        Write-Host '=== bed sweep results ==='
        $rows = @(Import-Csv $Ledger | Select-Object -Last $members.Count)
        $rows | Format-Table @{n = 'Snapshot'; e = { $_.Snapshot -replace '^\d{8}-', '' -replace '\.json$', '' } }, @{n = 'Surv'; e = { "$($_.Survived)/$($_.Runs)" } }, AvgDmg, AvgT, DmgPerSec, CrocHits, PursuerHits, ProjHits, OtherHits -AutoSize
        $totRuns = ($rows | Measure-Object -Property Runs -Sum).Sum
        $totSurv = ($rows | Measure-Object -Property Survived -Sum).Sum
        $wDps = [math]::Round((($rows | ForEach-Object { [double]$_.DmgPerSec * [int]$_.Runs } | Measure-Object -Sum).Sum / [math]::Max($totRuns, 1)), 2)
        Write-Host ("bed aggregate: {0}/{1} survived, run-weighted DmgPerSec {2}" -f $totSurv, $totRuns, $wDps)
    }
}
