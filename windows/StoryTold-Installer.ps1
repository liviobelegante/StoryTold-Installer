param([int]$WordCraft=1,[int]$GridCraft=1,[int]$DeckCraft=1,[int]$PdfCraft=1,[int]$CadCraft=1,[int]$SolidCraft=1,[switch]$ElevatedInstall,[string]$Manifest,[switch]$Resume)
$ErrorActionPreference='Stop'

# ----------- log ----------
function Log([string]$Message) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" }
# -----------------------------

# ----------- executable discovery ----------
function Find-Cargo {
    $cmd=Get-Command cargo.exe -ErrorAction SilentlyContinue
    if($cmd){return $cmd.Source}
    $candidate=Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
    if(Test-Path $candidate){return $candidate}
    return $null
}
# -----------------------------

# ----------- install prerequisites ----------
function Ensure-Prerequisites {
    $cargo=Find-Cargo
    if(-not $cargo){
        Log 'Rust/Cargo missing. Installing Rust automatically...'
        $rustup=Join-Path $Work 'rustup-init.exe'
        & curl.exe -fL --retry 2 --connect-timeout 20 --max-time 300 -o $rustup 'https://win.rustup.rs/x86_64'
        if($LASTEXITCODE -ne 0){throw 'Rustup download failed.'}
        & $rustup -y --default-toolchain stable --default-host x86_64-pc-windows-msvc --no-modify-path | Out-Host
        if($LASTEXITCODE -ne 0){throw 'Rust installation failed.'}
        $cargo=Find-Cargo
        if(-not $cargo){throw 'Cargo not found after Rust installation.'}
    }
    $env:PATH="$(Split-Path $cargo);$env:PATH"
    # Capture version output explicitly. Never let native-command stdout become function return data.
    $cargoVersion = (& $cargo --version | Out-String).Trim()
    if($LASTEXITCODE -ne 0){throw 'Cargo version check failed.'}
    $rustVersion = (& rustc.exe --version | Out-String).Trim()
    if($LASTEXITCODE -ne 0){throw 'Rustc version check failed.'}
    Log "Cargo: $cargoVersion"
    Log "Rustc: $rustVersion"
    # Prefer installed compiler binaries over vswhere component metadata.
    # Some valid VS 2019/2022 installations are not returned by -requires.
    $vswhere="${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $compiler=$null
    $vsRoots=@(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio')
    ) | Select-Object -Unique
    foreach($year in @('2022','2019','2026','2025')){
        foreach($root in $vsRoots){
            $yearDir=Join-Path $root $year
            if(-not (Test-Path -LiteralPath $yearDir -PathType Container)){continue}
            foreach($edition in @(Get-ChildItem -LiteralPath $yearDir -Directory -ErrorAction SilentlyContinue)){
                $toolsDir=Join-Path $edition.FullName 'VC\Tools\MSVC'
                if(-not (Test-Path -LiteralPath $toolsDir -PathType Container)){continue}
                $versions=@(Get-ChildItem -LiteralPath $toolsDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
                foreach($version in $versions){
                    $candidate=Join-Path $version.FullName 'bin\Hostx64\x64\cl.exe'
                    if(Test-Path -LiteralPath $candidate -PathType Leaf){$compiler=$candidate;break}
                }
                if($compiler){break}
            }
            if($compiler){break}
        }
        if($compiler){break}
    }
    if(-not $compiler -and (Test-Path -LiteralPath $vswhere -PathType Leaf)){
        $installations=@(& $vswhere -all -products '*' -property installationPath 2>$null)
        foreach($install in $installations){
            if(-not $install){continue}
            $toolsDir=Join-Path ([string]$install) 'VC\Tools\MSVC'
            if(-not (Test-Path -LiteralPath $toolsDir -PathType Container)){continue}
            foreach($version in @(Get-ChildItem -LiteralPath $toolsDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)){
                $candidate=Join-Path $version.FullName 'bin\Hostx64\x64\cl.exe'
                if(Test-Path -LiteralPath $candidate -PathType Leaf){$compiler=$candidate;break}
            }
            if($compiler){break}
        }
    }
    if($compiler){
        Log "MSVC compiler found: $compiler"
    } else {
        Log 'MSVC C++ compiler not found. Installing Build Tools automatically (Windows may show a UAC prompt)...'
        $bootstrap=Join-Path $Work 'vs_BuildTools.exe'
        if(Test-Path -LiteralPath $bootstrap){
            $running=@(Get-CimInstance Win32_Process -Filter "Name = 'vs_BuildTools.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath -eq $bootstrap })
            if($running.Count){throw "Build Tools installer is already running (PID $($running[0].ProcessId)). Finish or close it before retrying."}
            Remove-Item -LiteralPath $bootstrap -Force -ErrorAction Stop
        }
        & curl.exe -fL --retry 2 --connect-timeout 20 --max-time 600 --silent --show-error -o $bootstrap 'https://aka.ms/vs/17/release/vs_BuildTools.exe'
        if($LASTEXITCODE -ne 0){throw 'Visual Studio Build Tools download failed.'}
        $process=Start-Process -FilePath $bootstrap -ArgumentList @('--quiet','--wait','--norestart','--nocache','--add','Microsoft.VisualStudio.Workload.VCTools','--includeRecommended') -Verb RunAs -Wait -PassThru
        if($process.ExitCode -eq 3010){Log 'RESTART_REQUIRED: Visual Studio Build Tools installation requires a restart.';return [pscustomobject]@{Cargo=$cargo;RestartRequired=$true}}
        if($process.ExitCode -ne 0){throw "Build Tools installation failed (exit code $($process.ExitCode))."}
        $installations=@()
        if(Test-Path -LiteralPath $vswhere){$installations=@(& $vswhere -all -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)}
        if(-not $installations.Count){throw 'MSVC was not detected after Build Tools installation.'}
    }
    return [pscustomobject]@{Cargo=[string]$cargo;RestartRequired=$false}
}
# -----------------------------

# ----------- save resume state ----------
function Save-ResumeState($Selected,$Completed,$PendingRestart) {
    $state=[pscustomobject]@{
        Selected=@($Selected)
        Completed=@($Completed)
        PendingRestart=[bool]$PendingRestart
        BuildMode='CPU_NATIVE'
        ScriptDirectory=$PSScriptRoot
        SavedAt=(Get-Date).ToString('o')
    }
    $temp=Join-Path $Work 'resume_state.tmp'
    $path=Join-Path $Work 'resume_state.json'
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $path -Force
}
# -----------------------------

# ----------- register resume after logon ----------
function Register-Resume {
    $gui=Join-Path $PSScriptRoot 'StoryTold-GUI.ps1'
    if(-not (Test-Path -LiteralPath $gui)){throw "GUI missing for resume: $gui"}
    $command='powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "'+$gui+'" -Resume'
    $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    New-Item -Path $key -Force | Out-Null
    New-ItemProperty -Path $key -Name 'StoryToldInstallerResume' -Value $command -PropertyType String -Force | Out-Null
    Log 'Resume registered for the next sign-in. Keep the extracted installer folder in place.'
}
# -----------------------------

# ----------- clear resume ----------
function Clear-Resume {
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'StoryToldInstallerResume' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $Work 'resume_state.json') -Force -ErrorAction SilentlyContinue
}
# -----------------------------

# ----------- download and extract ----------
function Fetch-Source($App) {
    $zip=Join-Path $Work ($App.Id+'_'+(Get-Date -Format 'yyyy-MM-dd_HHmmss')+'.zip')
    Log "Downloading $($App.Id)"
    & curl.exe -fL --retry 2 --connect-timeout 20 --max-time 300 --progress-bar -o $zip $App.Url
    if($LASTEXITCODE -ne 0){throw "Download failed: $($App.Id)"}
    $dest=Join-Path $Work ($App.Id+'-main')
    if(Test-Path $dest){Log "Removing previous source folder: $dest"; Remove-Item $dest -Recurse -Force}
    $extract=Join-Path $Work ('extract_'+$App.Id)
    if(Test-Path $extract){Remove-Item $extract -Recurse -Force}
    New-Item -ItemType Directory -Path $extract | Out-Null
    Log "Extracting $($App.Id) ZIP to $extract (this can take several minutes)"
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
    Log "Extraction complete: $($App.Id)"
    $roots=@(Get-ChildItem -LiteralPath $extract -Directory)
    if($roots.Count -ne 1){throw "Arhiva $($App.Id) has an unexpected archive structure."}
    Log "Moving extracted source to $dest"
    Move-Item -LiteralPath $roots[0].FullName -Destination $dest
    Remove-Item $extract -Recurse -Force
    return $dest
}
# -----------------------------

# ----------- compile application ----------
function Build-App($App,$Cargo) {
    $cached=Join-Path $Work ($App.Id+'-main\target\release\'+$App.Exe+'.exe')
    $cachedLog=Join-Path $Work ($App.Id+'_cargo_stderr.log')
    if((Test-Path -LiteralPath $cached) -and (Test-Path -LiteralPath $cachedLog) -and (Select-String -LiteralPath $cachedLog -Pattern 'Finished `release` profile' -Quiet -ErrorAction SilentlyContinue)){
        Log "Reusing already compiled executable: $cached"
        return $cached
    }
    $source=Fetch-Source $App
    if(-not (Test-Path (Join-Path $source 'Cargo.toml'))){throw "Cargo.toml missing: $source"}
    Log "Building $($App.Id) (CPU-native release optimization)"
    $stdout=Join-Path $Work ($App.Id+'_cargo_stdout.log')
    $stderr=Join-Path $Work ($App.Id+'_cargo_stderr.log')
    $combined=Join-Path $Work ($App.Id+'_cargo_build.log')
    # Use the native process exit code, not PowerShell's treatment of stderr as ErrorRecord.
    # Cargo warnings and progress messages are normal stderr output.
    $args=@('build','--release','-p',[string]$App.Package)
    Log "Cargo started for $($App.Id). Full output: $stderr"
    # Poll the process, so long builds are never silent.
    # Launch a separate PowerShell worker that writes Cargo's actual exit code to disk.
    # This avoids the empty Start-Process.ExitCode issue on some Windows PowerShell versions.
    $exitFile=Join-Path $Work ($App.Id+'_cargo_exitcode.txt')
    $worker=Join-Path $Work ($App.Id+'_cargo_worker.ps1')
    Remove-Item -LiteralPath $exitFile -Force -ErrorAction SilentlyContinue
    $workerText=@'
param([string]$CargoExe,[string]$SourceDir,[string]$Package,[string]$StdoutPath,[string]$StderrPath,[string]$ExitPath)
Set-Location -LiteralPath $SourceDir
try {
    & $CargoExe build --release -p $Package 1> $StdoutPath 2> $StderrPath
    $result=[int]$LASTEXITCODE
} catch {
    $_ | Out-String | Add-Content -LiteralPath $StderrPath
    $result=9001
}
[IO.File]::WriteAllText($ExitPath,[string]$result)
exit $result
'@
    Set-Content -LiteralPath $worker -Value $workerText -Encoding UTF8
    $quoted=@($worker,$Cargo,$source,[string]$App.Package,$stdout,$stderr,$exitFile) | ForEach-Object { '"'+($_ -replace '"','`"')+'"' }
    $workerArgs='-NoProfile -ExecutionPolicy Bypass -File '+($quoted -join ' ')
    $process=Start-Process -FilePath 'powershell.exe' -ArgumentList $workerArgs -WorkingDirectory $source -PassThru -WindowStyle Hidden
    $started=Get-Date
    $lastHeartbeat=Get-Date
    while(-not $process.HasExited) {
        Start-Sleep -Seconds 2
        $process.Refresh()
        if(((Get-Date)-$lastHeartbeat).TotalSeconds -ge 15) {
            $elapsed=[int]((Get-Date)-$started).TotalSeconds
            $latest='Cargo is running; waiting for output'
            if(Test-Path -LiteralPath $stderr) {
                try { $lines=@(Get-Content -LiteralPath $stderr -Tail 1 -ErrorAction SilentlyContinue); if($lines.Count -gt 0){$latest=[string]$lines[-1]} } catch {}
            }
            if($latest.Length -gt 190){$latest=$latest.Substring(0,190)}
            Log "STILL RUNNING: $($App.Id) | elapsed ${elapsed}s | PID $($process.Id) | $latest"
            $lastHeartbeat=Get-Date
        }
    }
    $process.WaitForExit()
    $elapsed=[int]((Get-Date)-$started).TotalSeconds
    $exitCode=$null
    if(Test-Path -LiteralPath $exitFile){
        $raw=(Get-Content -LiteralPath $exitFile -Raw).Trim()
        $parsed=0
        if([int]::TryParse($raw,[ref]$parsed)){$exitCode=$parsed}
    }
    Log "Cargo process exited: $($App.Id) | code $exitCode | elapsed ${elapsed}s"
    $output=@()
    if(Test-Path -LiteralPath $stdout){$output+=@(Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue)}
    if(Test-Path -LiteralPath $stderr){$output+=@(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue)}
    $output | Set-Content -LiteralPath $combined -Encoding UTF8
    if($null -eq $exitCode){throw "Cargo worker did not report an exit code. Check $stderr"}
    if($exitCode -ne 0){
        $tail=($output | Select-Object -Last 18) -join ' | '
        throw "Cargo build failed for $($App.Id) (exit code $exitCode). See $combined. $tail"
    }
    Log "Cargo finished successfully: $($App.Id). Build log: $combined"
    $exe=Join-Path $source ('target\release\'+$App.Exe+'.exe')
    if(-not (Test-Path -LiteralPath $exe)){throw "Executable not found: $exe"}
    return $exe
}
# -----------------------------

# ----------- elevated installation ----------
function Install-Built($ManifestPath) {
    $installLog=Join-Path (Split-Path -Parent $ManifestPath) "elevated_install.log"
    $statusFile=Join-Path (Split-Path -Parent $ManifestPath) "elevated_install.status"
    try { "START $(Get-Date -Format o)" | Set-Content -LiteralPath $installLog -Encoding UTF8 } catch {}
    "RUNNING" | Set-Content -LiteralPath $statusFile -Encoding ASCII
    # Convert the manifest to a flat list of application records.
    # Windows PowerShell can wrap a JSON array in a nested Object[].
    $rawItems=ConvertFrom-Json -InputObject (Get-Content -LiteralPath $ManifestPath -Raw)
    $items=@($rawItems | ForEach-Object { $_ })
    if($items.Count -eq 1 -and $items[0] -is [array]) {
        $items=@($items[0] | ForEach-Object { $_ })
    }
    "Manifest records: $($items.Count)" | Add-Content -LiteralPath $installLog

    $root=Join-Path ${env:ProgramFiles(x86)} 'StoryTold'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $desktop=[Environment]::GetFolderPath('CommonDesktopDirectory')
    $shell=New-Object -ComObject WScript.Shell
    $fail=0
    foreach($item in $items){
        try {
            $folder=[string]$item.Folder
            $exePath=[string]$item.Exe
            $shortcutName=[string]$item.Shortcut
            $appId=[string]$item.Id
            if([string]::IsNullOrWhiteSpace($folder) -or [string]::IsNullOrWhiteSpace($exePath)) {
                throw "Invalid manifest record: $($item | ConvertTo-Json -Compress -Depth 3)"
            }
            $targetDir=Join-Path -Path $root -ChildPath ($folder+'\target\release')
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            $target=Join-Path $targetDir ([IO.Path]::GetFileName($exePath))
            Copy-Item -LiteralPath $exePath -Destination $target -Force
            $link=$shell.CreateShortcut((Join-Path $desktop ($shortcutName+'.lnk')))
            $link.TargetPath=$target
            $link.WorkingDirectory=$targetDir
            $link.IconLocation="$target,0"
            $link.Description=$item.Id
            $link.Save()
            Log "Installed: $($item.Id) -> $target"
            "OK $($item.Id) -> $target" | Add-Content -LiteralPath $installLog
        } catch { $fail++; Log "ERROR instalare $($item.Id): $_"; "ERROR $($item.Id): $_" | Add-Content -LiteralPath $installLog }
    }
    if($fail){"FAILED" | Set-Content -LiteralPath $statusFile -Encoding ASCII; exit 1}else{"SUCCESS" | Set-Content -LiteralPath $statusFile -Encoding ASCII; exit 0}
}
# -----------------------------

if($ElevatedInstall){
    try { Install-Built $Manifest }
    catch {
        $base=Split-Path -Parent $Manifest
        "FATAL: $($_ | Out-String)" | Add-Content -LiteralPath (Join-Path $base 'elevated_install.log') -ErrorAction SilentlyContinue
        'FAILED' | Set-Content -LiteralPath (Join-Path $base 'elevated_install.status') -ErrorAction SilentlyContinue
        exit 1
    }
    exit
}
$Work=if(Test-Path 'D:\'){ 'D:\temp\StoryTold' } else { 'C:\temp\StoryTold' }
New-Item -ItemType Directory -Path $Work -Force | Out-Null
$apps=@(
    [pscustomobject]@{Id='wordcraft';Enabled=$WordCraft;Url='https://github.com/storytold/wordcraft/archive/refs/heads/main.zip';Package='wordcraft';Exe='wordcraft';Folder='wordcraft-main';Shortcut='Word (WordCraft)'},
    [pscustomobject]@{Id='gridcraft';Enabled=$GridCraft;Url='https://github.com/storytold/gridcraft/archive/refs/heads/main.zip';Package='gridcraft';Exe='gridcraft';Folder='gridcraft-main';Shortcut='Excel (GridCraft)'},
    [pscustomobject]@{Id='deckcraft';Enabled=$DeckCraft;Url='https://github.com/storytold/deckcraft/archive/refs/heads/main.zip';Package='deckcraft';Exe='deckcraft';Folder='deckcraft-main';Shortcut='PowerPoint (DeckCraft)'},
    [pscustomobject]@{Id='pdfcraft';Enabled=$PdfCraft;Url='https://github.com/storytold/pdfcraft/archive/refs/heads/main.zip';Package='pdfcraft';Exe='pdfcraft';Folder='pdfcraft-main';Shortcut='PDF (PDFCraft)'},
    [pscustomobject]@{Id='cadcraft';Enabled=$CadCraft;Url='https://github.com/storytold/cadcraft/archive/refs/heads/main.zip';Package='cadcraft';Exe='cadcraft';Folder='cadcraft-main';Shortcut='AutoCAD (CADCraft)'},
    [pscustomobject]@{Id='solidcraft';Enabled=$SolidCraft;Url='https://github.com/tangency-labs/solidcraft/archive/refs/heads/main.zip';Package='solidcraft';Exe='solidcraft';Folder='solid-main';Shortcut='SolidWorks (SolidCraft)'}
)
$statePath=Join-Path $Work 'resume_state.json'
$selected=@($apps | Where-Object Enabled -eq 1 | ForEach-Object {$_.Id})
$built=@();$failed=@()
if($Resume){
    if(-not (Test-Path -LiteralPath $statePath)){Log 'ERROR: No saved resume state exists.';exit 1}
    $state=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $selected=@($state.Selected)
    if($state.BuildMode -ne 'CPU_NATIVE'){Log 'Previous builds were not marked CPU-native. Rebuilding selected applications.'}
    foreach($item in $(if($state.BuildMode -eq 'CPU_NATIVE'){@($state.Completed)}else{@()})){ 
        if($null -ne $item -and $item.Exe -and (Test-Path -LiteralPath $item.Exe)){$built+= $item}
    }
    Log "Resuming selected applications: $($selected -join ', ')"
} else {
    Clear-Resume
    Save-ResumeState $selected $built $false
}
if(-not $selected.Count){Log 'No applications selected.';exit 1}
try {
    $prereq=Ensure-Prerequisites
    if($prereq.RestartRequired){
        Save-ResumeState $selected $built $true
        Register-Resume
        Log 'RESTART_REQUIRED: Please restart Windows when convenient. Installation will resume at next sign-in.'
        exit 3010
    }
    $cargo=[string]$prereq.Cargo
    # Rust codegen for the processor on this PC. Do not apply any GPU flags.
    $env:RUSTFLAGS='-C target-cpu=native'
    Log "CPU optimization: $env:RUSTFLAGS"
    if(-not (Test-Path -LiteralPath $cargo -PathType Leaf)){throw "Invalid Cargo executable path: $cargo"}
} catch {Log "ERROR prerequisites: $_";exit 1}
foreach($app in $apps | Where-Object {$selected -contains $_.Id}){
    if(@($built | Where-Object Id -eq $app.Id).Count){Log "SKIPPED already built: $($app.Id)";continue}
    try {
        $exe=Build-App $app $cargo
        $built+= [pscustomobject]@{Id=$app.Id;Exe=$exe;Folder=$app.Folder;Shortcut=$app.Shortcut}
        Save-ResumeState $selected $built $false
        Log "OK: $($app.Id)"
    } catch {Log "ERROR building $($app.Id): $_";$failed+=$app.Id}
}
if(-not $built.Count){Log 'No applications built. Skipping elevation.';exit 1}
$manifestPath=Join-Path $Work 'install_manifest.json'
ConvertTo-Json -InputObject @($built) -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Log 'Requesting one UAC approval for installation and desktop shortcuts.'
$elevatedLog=Join-Path $Work 'elevated_install.log'
$statusFile=Join-Path $Work 'elevated_install.status'
Remove-Item -LiteralPath $statusFile -Force -ErrorAction SilentlyContinue
$argsList="-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ElevatedInstall -Manifest `"$manifestPath`""
try {
    $process=Start-Process -FilePath 'powershell.exe' -ArgumentList $argsList -Verb RunAs -PassThru -ErrorAction Stop
    Log "Elevated installer started. PID: $($process.Id). Waiting for installation."
    $last=Get-Date
    while(-not $process.HasExited){
        Start-Sleep -Seconds 2
        $process.Refresh()
        if(((Get-Date)-$last).TotalSeconds -ge 15){
            Log "INSTALLATION ACTIVE: elevated PID $($process.Id), waiting for completion"
            $last=Get-Date
        }
    }
    $process.WaitForExit()
    $status=if(Test-Path -LiteralPath $statusFile){(Get-Content -LiteralPath $statusFile -Raw).Trim()}else{'MISSING'}
    Log "Elevated installer finished. Status: $status. Log: $elevatedLog"
    if($status -ne 'SUCCESS'){
        if(Test-Path -LiteralPath $elevatedLog){Get-Content -LiteralPath $elevatedLog -Tail 20 | ForEach-Object {Log "INSTALL DETAIL: $_"}}
        throw "Elevated installation did not report success (status $status). See $elevatedLog"
    }
} catch {
    Log "ERROR UAC / elevated installation: $($_ | Out-String)"
    Log "Builds remain available in $Work; do not delete them."
    exit 1
}
foreach($app in $built){$src=Join-Path $Work ($app.Id+'-main');if(Test-Path $src){Remove-Item $src -Recurse -Force -ErrorAction SilentlyContinue}}
Clear-Resume
if($failed.Count){Log "Failed builds: $($failed -join ', ')";exit 1}
Log 'Installation successful. Removing all temporary files and logs.'
# The GUI may hold a log open. Schedule deletion in a detached process after this installer exits.
$cleanupScript=Join-Path $env:TEMP ('storytold_cleanup_'+[guid]::NewGuid().ToString('N')+'.ps1')
$cleanupText=@'
param([string]$Target)
Start-Sleep -Seconds 8
for($i=0;$i -lt 20;$i++){
    try { Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction Stop; break }
    catch { Start-Sleep -Seconds 3 }
}
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
'@
Set-Content -LiteralPath $cleanupScript -Value $cleanupText -Encoding UTF8
Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$cleanupScript+'" -Target "'+$Work+'"') -WindowStyle Hidden
Log 'Installation complete. Temporary folder will be removed shortly.'
exit 0
