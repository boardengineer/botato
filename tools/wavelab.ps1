# WaveLab runner: replay a captured Brotato wave snapshot with the bot, N times.
#
#   wavelab.ps1 capture [-Note tag]      harvest newest run snapshot into the library
#   wavelab.ps1 list                     show the snapshot library
#   wavelab.ps1 run <snapshot> [-Count 3] [-Seed 0] [-Speed 1]
#                                        replay a snapshot; -Seed 0 = fresh seed per
#                                        iteration, fixed seed = repeat circumstances
#
# Snapshots live in C:\brotato\wavelab\snapshots, results in C:\brotato\wavelab\results.

param(
    [Parameter(Position = 0, Mandatory = $true)][ValidateSet('capture', 'list', 'run')][string]$Command,
    [Parameter(Position = 1)][string]$Snapshot,
    [int]$Count = 3,
    [int]$Seed = 0,
    [double]$Speed = 1.0,
    [string]$Note = ''
)

$ErrorActionPreference = 'Stop'
$GameExe = 'C:\godot\steamgodot\godotsteam.36.editor.windows.64.exe'
$GamePath = 'C:\brotato\decompiled-autobattler'
$SaveDir = "$env:APPDATA\BrotatoDecompiled\user"
$RunFile = "$SaveDir\run_v3_0.json"
$SnapDir = 'C:\brotato\wavelab\snapshots'
$ResultDir = 'C:\brotato\wavelab\results'
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
        $candidates = @(Get-Item $RunFile -ErrorAction SilentlyContinue) + @(Get-ChildItem "$SaveDir\run_v3_0_*.bak" -ErrorAction SilentlyContinue) |
            Where-Object { $_ } | Sort-Object LastWriteTime -Descending
        foreach ($c in $candidates) {
            $meta = Read-SnapshotMeta $c.FullName
            if ($meta) {
                $tag = if ($Note) { "-$Note" } else { '' }
                $name = '{0}-w{1}-{2}-d{3}-hp{4}{5}.json' -f (Get-Date -Format 'yyyyMMdd'), $meta.Wave, $meta.Character, $meta.Danger, $meta.HP, $tag
                Copy-Item $c.FullName (Join-Path $SnapDir $name)
                Write-Host "captured: $($c.Name) -> $name"
                return
            }
        }
        Write-Host 'no snapshot with run state found (play to a shop first, or check .bak files)'
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
}
