param([switch]$Resume)
# StoryTold graphical installer (Windows PowerShell 5.1)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
# ----------- Windows sleep prevention ----------
# Keep both the system and display awake while installation is active.
# ES_CONTINUOUS=0x80000000, ES_SYSTEM_REQUIRED=1, ES_DISPLAY_REQUIRED=2.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class StoryToldPower {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern uint SetThreadExecutionState(uint flags);
}
'@
function Set-InstallerAwake([bool]$enabled) {
    if ($enabled) {
        [void][StoryToldPower]::SetThreadExecutionState([uint32]2147483651)
    } else {
        [void][StoryToldPower]::SetThreadExecutionState([uint32]2147483648)
    }
}
# -----------------------------

$ErrorActionPreference = 'Stop'
$script:work = if (Test-Path 'D:\') { 'D:\temp\StoryTold' } else { 'C:\temp\StoryTold' }
$script:worker = Join-Path $PSScriptRoot 'StoryTold-Installer.ps1'
$script:process = $null
$script:logFile = $null
$script:errorFile = $null
$script:done = $false
$script:resumeMode = [bool]$Resume
$script:startedAt = $null
$script:lastOutputAt = $null
$script:displayEvents = @()
$script:seenLogLines = 0
$script:seenErrorLines = 0

# ----------- create form ----------
function New-InstallerForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'StoryTold Suite Installer'
    $form.Size = New-Object System.Drawing.Size(900,730)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-Object System.Drawing.Size(760,620)
    $form.BackColor = [System.Drawing.Color]::FromArgb(25,29,38)
    $form.ForeColor = [System.Drawing.Color]::White
    $form.Font = New-Object System.Drawing.Font('Segoe UI',10)
    return $form
}
# -----------------------------

# ----------- create label ----------
function New-Label([string]$text,[int]$x,[int]$y,[int]$w,[int]$h,[int]$size=10) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point($x,$y)
    $label.Size = New-Object System.Drawing.Size($w,$h)
    $label.Font = New-Object System.Drawing.Font('Segoe UI',$size)
    return $label
}
# -----------------------------

$form = New-InstallerForm
$title = New-Label 'StoryTold Suite Installer' 24 18 790 42 21
$title.ForeColor = [System.Drawing.Color]::Cyan
$form.Controls.Add($title)
$sub = New-Label 'Select applications, then click Start. Dependencies are installed automatically if needed.' 26 63 820 45 10
$form.Controls.Add($sub)
# Animated ASCII spiral, independent of curl and Cargo output.
$spiral = New-Object System.Windows.Forms.Label
$spiral.Location = New-Object System.Drawing.Point(658,13)
$spiral.Size = New-Object System.Drawing.Size(205,65)
$spiral.Font = New-Object System.Drawing.Font('Consolas',10)
$spiral.ForeColor = [System.Drawing.Color]::Cyan
$spiral.TextAlign = 'MiddleCenter'
$spiral.Text = '     ready     '
$form.Controls.Add($spiral)
$script:spiralFrame = 0

$names = @(
    @('WordCraft','Word (WordCraft)'),
    @('GridCraft','Excel (GridCraft)'),
    @('DeckCraft','PowerPoint (DeckCraft)'),
    @('PDFCraft','PDF (PDFCraft)'),
    @('CADCraft','AutoCAD (CADCraft)'),
    @('SolidCraft','SolidWorks (SolidCraft)')
)
$checks = @()
for($i=0;$i -lt $names.Count;$i++) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $names[$i][1]
    $cb.Checked = $true
    $cb.AutoSize = $true
    $cb.Location = New-Object System.Drawing.Point((32 + ($i % 2)*415),(120 + [int][math]::Floor($i/2)*37))
    $form.Controls.Add($cb)
    $checks += $cb
}
$task = New-Label 'Current task: Ready' 26 250 830 30 12
$task.ForeColor = [System.Drawing.Color]::LightSkyBlue
$form.Controls.Add($task)
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(28,291)
$progress.Size = New-Object System.Drawing.Size(820,22)
$progress.Style = 'Continuous'
$progress.Minimum = 0
$progress.Maximum = 6
$form.Controls.Add($progress)
$count = New-Label 'Completed builds: 0 / 6' 28 322 810 25
$form.Controls.Add($count)
$heartbeat = New-Label 'Status: idle' 360 322 490 25 9
$heartbeat.ForeColor = [System.Drawing.Color]::LightGreen
$form.Controls.Add($heartbeat)
$logTitle = New-Label 'Installation events and ASCII spiral (full output saved to log files)' 28 359 820 26 12
$form.Controls.Add($logTitle)
$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.WordWrap = $false
$log.Location = New-Object System.Drawing.Point(28,390)
$log.Size = New-Object System.Drawing.Size(820,220)
$log.BackColor = [System.Drawing.Color]::FromArgb(12,15,20)
$log.ForeColor = [System.Drawing.Color]::Gainsboro
$log.Font = New-Object System.Drawing.Font('Consolas',9)
$log.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($log)
$start = New-Object System.Windows.Forms.Button
$start.Text = 'Start installation'
$start.Size = New-Object System.Drawing.Size(170,37)
$start.Location = New-Object System.Drawing.Point(28,624)
$start.Anchor = 'Bottom,Left'
$form.Controls.Add($start)
$open = New-Object System.Windows.Forms.Button
$open.Text = 'Open log folder'
$open.Size = New-Object System.Drawing.Size(150,37)
$open.Location = New-Object System.Drawing.Point(212,624)
$open.Anchor = 'Bottom,Left'
$form.Controls.Add($open)
$notice = New-Label 'A Windows UAC prompt may appear for system dependencies and final installation.' 383 624 470 48 9
$notice.Anchor = 'Bottom,Right'
$form.Controls.Add($notice)
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 800
$animationTimer = New-Object System.Windows.Forms.Timer
$animationTimer.Interval = 120
$script:animationArt = ''
$script:animationTicks = 0

# ----------- refresh status ----------
function Update-InstallerStatus {
    if (-not $script:logFile) { return }
    if ($script:process -and -not $script:process.HasExited) {
        $elapsed=[int]((Get-Date)-$script:startedAt).TotalSeconds
        $last='unknown'
        if(Test-Path -LiteralPath $script:logFile) {
            $last=[int]((Get-Date)-(Get-Item -LiteralPath $script:logFile).LastWriteTime).TotalSeconds
        }
        $heartbeat.Text="RUNNING | elapsed ${elapsed}s | last status ${last}s ago"
        if($last -ge 90){$heartbeat.ForeColor=[System.Drawing.Color]::Orange}else{$heartbeat.ForeColor=[System.Drawing.Color]::LightGreen}
    }

    if (Test-Path -LiteralPath $script:logFile) {
        try {
            $lines = @(Get-Content -LiteralPath $script:logFile -ErrorAction Stop)
            # Display major events only; the full worker output stays on disk.
            if ($lines.Count -lt $script:seenLogLines) { $script:seenLogLines = 0 }
            for ($i=$script:seenLogLines; $i -lt $lines.Count; $i++) {
                $line = [string]$lines[$i]
                if ($line -match 'Downloading |Extracting |Extraction complete|Moving extracted|Building |Reusing already|Cargo finished successfully|Cargo process exited|^\[[^]]+\] OK:|Installing |Installed:|Requesting one UAC|RESTART_REQUIRED|ERROR|Installation successful|Installation complete|Failed builds|No applications built|Checking|Rust/Cargo missing|Build Tools missing') {
                    $script:displayEvents += $line
                }
            }
            $script:seenLogLines = $lines.Count
            if ($script:errorFile -and (Test-Path -LiteralPath $script:errorFile)) {
                $errors = @(Get-Content -LiteralPath $script:errorFile -ErrorAction SilentlyContinue)
                if ($errors.Count -lt $script:seenErrorLines) { $script:seenErrorLines = 0 }
                if ($errors.Count -gt $script:seenErrorLines) {
                    $newErrors = @($errors | Select-Object -Skip $script:seenErrorLines)
                    $script:displayEvents += '[INSTALLER STDERR]'
                    $script:displayEvents += @($newErrors | Select-Object -Last 12)
                    $script:seenErrorLines = $errors.Count
                }
            }
            $script:displayEvents = @($script:displayEvents | Select-Object -Last 80)
            $completed = @($lines | Where-Object { $_ -match 'OK: (wordcraft|gridcraft|deckcraft|pdfcraft|cadcraft|solidcraft)' }).Count
            $progress.Value = [Math]::Min($progress.Maximum,$completed)
            $count.Text = "Completed builds: $completed / $($progress.Maximum)"
            $latest = @($script:displayEvents | Where-Object { $_ -match 'Downloading |Extracting |Building |Installing |Installed: |Requesting one UAC|missing|ERROR|Installation complete' } | Select-Object -Last 1)
            if ($latest.Count) { $task.Text = 'Current task: ' + ($latest[0] -replace '^\[[^]]+\]\s*','') }
        } catch { }
    }
    Update-InstallerDisplay
    if ($script:process -and $script:process.HasExited -and -not $script:done) {
        $script:done = $true
        $heartbeat.Text = 'Process finished (exit code '+$script:process.ExitCode+')'
        if($script:process.ExitCode -ne 0) { Show-InstallerErrors }
        Update-InstallerStatusLogFinal
        $timer.Stop()
        $animationTimer.Stop()
        Set-InstallerAwake $false
        $start.Enabled = $true
        $start.Text = 'Run again'
        foreach($c in $checks) { $c.Enabled = $true }
        if($script:process.ExitCode -eq 3010) {
            $task.Text = 'Restart required. Resume will start after Windows sign-in.'
            $start.Enabled = $false
        } elseif($script:process.ExitCode -eq 0) {
            $task.Text = 'Finished successfully. Desktop shortcuts created.'
        } else {
            $task.Text = 'Finished with errors. Check the log below.'
        }
    }
}
# -----------------------------

# ----------- final log refresh ----------
function Update-InstallerStatusLogFinal {
    # Keep the major-event summary on screen, not the raw compiler output.
    $log.Text = (@($script:displayEvents | Select-Object -Last 70) -join "`r`n")
    $log.SelectionStart = $log.TextLength
    $log.ScrollToCaret()
}
# -----------------------------

# ----------- start installer ----------
function Start-Installer {
    $selected = @($checks | Where-Object Checked)
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Select at least one application.','StoryTold') | Out-Null
        return
    }
    New-Item -ItemType Directory -Path $script:work -Force | Out-Null
    $script:logFile = Join-Path $script:work ('installer_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
    $params = @()
    for($i=0;$i -lt $checks.Count;$i++) {
        $key = @('WordCraft','GridCraft','DeckCraft','PdfCraft','CadCraft','SolidCraft')[$i]
        $val = if($checks[$i].Checked){1}else{0}
        $params += ('-'+$key+' '+$val)
    }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script:worker + '" ' + $(if($script:resumeMode){'-Resume'}else{($params -join ' ')})
    $script:errorFile = $script:logFile + '.errors.txt'
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'powershell.exe'
    $startInfo.Arguments = $arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    # Direct process output to files instead of event callbacks.
    # PowerShell event handlers may run in another runspace and lose GUI variables.
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $script:process = $null
    $script:done = $false
    $script:startedAt = Get-Date
    $script:spiralFrame = 0
    $script:animationTicks = 0
    $script:displayEvents = @()
    $script:seenLogLines = 0
    $script:seenErrorLines = 0
    $progress.Maximum = $selected.Count
    $progress.Value = 0
    $count.Text = "Completed builds: 0 / $($selected.Count)"
    $log.Clear()
    $start.Enabled = $false
    foreach($c in $checks){$c.Enabled = $false}
    $task.Text = 'Current task: Checking prerequisites...'
    try {
        [IO.File]::WriteAllText($script:logFile,'')
        [IO.File]::WriteAllText($script:errorFile,'')
        # Start-Process -RedirectStandardOutput/-RedirectStandardError handles streams
        # without GUI event handlers or asynchronous callback failures.
        Set-InstallerAwake $true
        $script:process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $script:logFile -RedirectStandardError $script:errorFile
        $timer.Start()
        $animationTimer.Start()
    } catch {
        Set-InstallerAwake $false
        $task.Text = 'ERROR: ' + $_.Exception.Message
        $start.Enabled = $true
        foreach($c in $checks){$c.Enabled = $true}
    }
}
# -----------------------------

# ----------- update installer display ----------
function Update-InstallerDisplay {
    $events = @($script:displayEvents | Select-Object -Last 48)
    $lines = @($events)
    if ($script:process -and -not $script:process.HasExited) {
        $lines += ''
        $lines += '    [ INSTALLATION ACTIVE ]'
        $lines += $script:animationArt
    }
    $display = $lines -join "`r`n"
    if ($log.Text -ne $display) {
        $log.Text = $display
        $log.SelectionStart = $log.TextLength
        $log.ScrollToCaret()
    }
}
# -----------------------------

# ----------- animate ASCII spiral ----------
function Update-InstallerSpiral {
    if (-not $script:process -or $script:process.HasExited) { return }
    $script:spiralFrame++
    $script:animationTicks++
    $frames = @('|','/','-','\')
    $spin = $frames[$script:spiralFrame % $frames.Count]
    $spiral.Text = "   $spin   ACTIVE   $spin"

    # A triangle wave reverses at each edge: left -> right -> left.
    # Row phase shifts create a continuous diagonal/helical appearance.
    $width = 48
    $period = 2 * $width
    $art = @()
    for ($r = 0; $r -lt 10; $r++) {
        $phase = [int](($script:spiralFrame + $r * 5) % $period)
        $offset = if ($phase -le $width) { $phase } else { $period - $phase }
        $opposite = $width - $offset
        $pattern = @('-=O=-', '=O=-=', 'O=-=O', '=-=O=')[$r % 4]
        $row = [char[]](' ' * ($width + $pattern.Length))
        for ($i = 0; $i -lt $pattern.Length; $i++) {
            $row[$offset + $i] = $pattern[$i]
        }
        # Second trace travels in the opposite direction.
        $row[$opposite + 2] = '#'
        $art += (-join $row)
    }
    $script:animationArt = $art -join "`r`n"
    Update-InstallerDisplay
}
# -----------------------------

# ----------- show installer errors ----------
function Show-InstallerErrors {
    $details = @()
    if ($script:errorFile -and (Test-Path -LiteralPath $script:errorFile)) {
        $details += @(Get-Content -LiteralPath $script:errorFile -Tail 30 -ErrorAction SilentlyContinue)
    }
    $elevated = Join-Path $script:work 'elevated_install.log'
    if (Test-Path -LiteralPath $elevated) {
        $details += '--- Elevated installation details ---'
        $details += @(Get-Content -LiteralPath $elevated -Tail 30 -ErrorAction SilentlyContinue)
    }
    if ($details.Count -gt 0) {
        $script:displayEvents += '[ERROR DETAILS]'
        $script:displayEvents += $details
    } else {
        $script:displayEvents += '[ERROR] Worker returned nonzero exit code. Check installer log and Cargo logs.'
    }
    $script:displayEvents = @($script:displayEvents | Select-Object -Last 80)
    Update-InstallerDisplay
}
# -----------------------------

$start.Add_Click({
    try { Start-Installer }
    catch {
        $detail = ($_ | Out-String)
        $task.Text = 'ERROR: ' + $_.Exception.Message
        [System.Windows.Forms.MessageBox]::Show($detail, 'StoryTold installer error') | Out-Null
        if ($script:logFile) { Add-Content -LiteralPath $script:logFile -Value $detail -ErrorAction SilentlyContinue }
        $start.Enabled = $true
        foreach ($c in $checks) { $c.Enabled = $true }
    }
})
$open.Add_Click({ if(Test-Path $script:work){Start-Process explorer.exe -ArgumentList ('"'+$script:work+'"')} })
$timer.Add_Tick({ Update-InstallerStatus })
$animationTimer.Add_Tick({ Update-InstallerSpiral })
if($script:resumeMode){
    $form.Add_Shown({
        $start.Text='Resuming installation...'
        Start-Installer
    })
}
$form.Add_FormClosing({
    if($script:process -and -not $script:process.HasExited) {
        $_.Cancel = $true
        [System.Windows.Forms.MessageBox]::Show('Installation is still running. Wait until it finishes.','StoryTold') | Out-Null
    }
})
try { [void]$form.ShowDialog() } finally { Set-InstallerAwake $false }
$timer.Dispose()
$animationTimer.Dispose()
$form.Dispose()
