param([switch]$Worker, [string]$RunFolder, [string]$Architecture, [switch]$SelfTest)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$catalog = @('WordCraft','GridCraft','DeckCraft','PDFCraft','CADCraft','SolidCraft')
$headers = @{ 'User-Agent' = 'StoryTold-Signed-GUI/3.4'; 'Accept' = 'application/vnd.github+json' }
. (Join-Path $PSScriptRoot 'Installer-Storage.ps1')
. (Join-Path $PSScriptRoot 'SolidCraft-Source.ps1')

# ----------- Get-Architecture ----------
function Get-Architecture {
    $value = $env:PROCESSOR_ARCHITEW6432
    if (-not $value) { $value = $env:PROCESSOR_ARCHITECTURE }
    switch ($value) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        'x86' { return 'x86' }
        default { throw "Unsupported architecture: $value" }
    }
}
# -----------------------------

# ----------- Write-Status ----------
function Write-Status {
    param([string]$App, [string]$Version, [string]$State, [string]$Detail)
    $event = [ordered]@{ App=$App; Version=$Version; State=$State; Detail=$Detail; Time=(Get-Date -Format 'HH:mm:ss') }
    $line = $event | ConvertTo-Json -Compress
    [IO.File]::AppendAllText((Join-Path $RunFolder 'events.jsonl'), $line + [Environment]::NewLine, [Text.Encoding]::UTF8)
}
# -----------------------------

# ----------- Get-ExpectedHash ----------
function Get-ExpectedHash {
    param([string]$Text, [string]$Name)
    $found = @($Text -split '\r?\n' | ForEach-Object {
        if ($_ -match '^([a-fA-F0-9]{64})\s+\*?(.+?)\s*$' -and $Matches[2] -ceq $Name) { $Matches[1].ToUpperInvariant() }
    })
    if ($found.Count -ne 1) { throw "Missing or duplicate SHA-256 entry for $Name." }
    return $found[0]
}
# -----------------------------

# ----------- Save-ReleaseAsset ----------
function Save-ReleaseAsset {
    param($Asset, [string]$Repo, [string]$Destination)
    $url = [uri]$Asset.browser_download_url
    if ($url.Scheme -ne 'https' -or $url.Host -ne 'github.com' -or
        -not $url.AbsolutePath.StartsWith("/storytold/$Repo/releases/download/", [StringComparison]::Ordinal)) {
        throw 'Download URL does not belong to the expected official repository.'
    }
    Invoke-WebRequest -UseBasicParsing -Uri $url.AbsoluteUri -OutFile $Destination -Headers $headers -TimeoutSec 600
}
# -----------------------------

# ----------- Get-InstalledExecutable ----------
function Get-InstalledExecutable {
    param([string]$Msi, [string]$App)
    $installer = $null
    $database = $null
    $productView = $null
    $fileView = $null
    $productRecord = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $installer.OpenDatabase($Msi, 0)
        $productView = $database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = 'ProductCode'")
        $productView.Execute()
        $productRecord = $productView.Fetch()
        if (-not $productRecord) { throw 'MSI ProductCode was not found.' }
        $productCode = $productRecord.StringData(1)
        $fileView = $database.OpenView('SELECT `File`.`File`, `File`.`FileName`, `Component`.`ComponentId`, `Component`.`KeyPath` FROM `File`, `Component` WHERE `File`.`Component_` = `Component`.`Component`')
        $fileView.Execute()
        while ($record = $fileView.Fetch()) {
            try {
                $fileName = ($record.StringData(2) -split '\|')[-1]
                if ($fileName -ieq ($App + '.exe') -and $record.StringData(1) -eq $record.StringData(4)) {
                    # Resolve the installed component, including a custom MSI installation directory.
                    $path = $installer.ComponentPath($productCode, $record.StringData(3))
                    if ($path -and (Test-Path -LiteralPath $path -PathType Leaf) -and
                        [IO.Path]::GetFileName($path) -ieq ($App + '.exe')) { return $path }
                }
            }
            finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record) }
        }
        throw "Windows Installer could not locate the installed $App executable."
    }
    finally {
        foreach ($view in @($fileView, $productView)) { if ($view) { $view.Close() } }
        foreach ($object in @($productRecord, $fileView, $productView, $database, $installer)) {
            if ($object) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($object) }
        }
    }
}
# -----------------------------

# ----------- New-DesktopShortcut ----------
function New-DesktopShortcut {
    param([string]$App, [string]$Executable, [string]$DesktopFolder = [Environment]::GetFolderPath('DesktopDirectory'))
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'Shortcut target does not exist.' }
    if (-not $DesktopFolder -or -not (Test-Path -LiteralPath $DesktopFolder -PathType Container)) { throw 'The current user desktop folder is unavailable.' }
    $shell = $null
    $shortcut = $null
    $temporary = Join-Path $DesktopFolder ([guid]::NewGuid().ToString('N') + '.lnk')
    $destination = Join-Path $DesktopFolder ($App + '.lnk')
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($temporary)
        $shortcut.TargetPath = $Executable
        $shortcut.WorkingDirectory = Split-Path -LiteralPath $Executable
        $shortcut.IconLocation = $Executable + ',0'
        $shortcut.Description = $App + ' - Official installed application'
        $shortcut.Save()
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
        $shortcut = $null
        Move-Item -LiteralPath $temporary -Destination $destination -Force
        return $destination
    }
    finally {
        if ($shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
        if ($shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
# -----------------------------

# ----------- New-ApplicationShortcut ----------
function New-ApplicationShortcut {
    param([string]$App, [string]$Executable)
    if ($script:request.Scope -ne 'AllUsers') {return (New-DesktopShortcut $App $Executable)}
    $desktop=[Environment]::GetFolderPath('CommonDesktopDirectory')
    $linkPath=Join-Path $desktop ($App+'.lnk')
    $shell=$null; $link=$null
    try {
        if (Test-Path -LiteralPath $linkPath) {
            $shell=New-Object -ComObject WScript.Shell
            $link=$shell.CreateShortcut($linkPath)
            if ($link.TargetPath -ieq $Executable -and -not $link.Arguments) {return $linkPath}
        }
    }
    finally {
        if($link){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)}
        if($shell){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
    }
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {return (New-DesktopShortcut $App $Executable $desktop)}
    $resultFile=Join-Path $RunFolder ('shortcut-'+[guid]::NewGuid().ToString('N')+'.json')
    $packet=@{App=$App;Executable=$Executable;Desktop=$desktop;Result=$resultFile}|ConvertTo-Json -Compress
    $data=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($packet))
    $code='$ErrorActionPreference="Stop"' + "`n# ----------- New-DesktopShortcut ----------`nfunction New-DesktopShortcut {`n" + (Get-Command New-DesktopShortcut -CommandType Function).Definition + "`n}`n# -----------------------------`n"
    $code+='$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("'+$data+'"))|ConvertFrom-Json' + "`n"
    $code+=@'
try {
    $path=New-DesktopShortcut $p.App $p.Executable $p.Desktop
    @{Success=$true;Path=$path}|ConvertTo-Json|Set-Content -LiteralPath $p.Result -Encoding UTF8
    exit 0
} catch {
    @{Success=$false;Error=$_.Exception.Message}|ConvertTo-Json|Set-Content -LiteralPath $p.Result -Encoding UTF8
    exit 1
}
'@
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $process=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand '+$encoded) -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if (-not (Test-Path -LiteralPath $resultFile)) {throw 'Shared desktop shortcut creation was canceled or did not finish.'}
    $result=Get-Content -LiteralPath $resultFile -Raw|ConvertFrom-Json
    if ($process.ExitCode -ne 0 -or -not $result.Success) {throw ('Shared shortcut failed: '+$result.Error)}
    return $linkPath
}
# -----------------------------

# ----------- Assert-MsiScopeSupport ----------
function Assert-MsiScopeSupport {
    param([string]$Msi)
    $installer=$null;$database=$null;$view=$null;$record=$null
    try {
        $installer=New-Object -ComObject WindowsInstaller.Installer
        $database=$installer.OpenDatabase($Msi,0)
        $view=$database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = 'ALLUSERS'")
        $view.Execute();$record=$view.Fetch()
        if (-not $record -or $record.StringData(1) -ne '2') {throw 'This MSI does not declare the expected dual-scope support. Installation is blocked instead of ignoring your scope choice.'}
    }
    finally {
        if($view){$view.Close()}
        foreach($object in @($record,$view,$database,$installer)){if($object){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($object)}}
    }
}
# -----------------------------

# ----------- Close-RunningApplication ----------
function Close-RunningApplication {
    param([string]$App, [int]$TimeoutSeconds = 30)
    $name = $App.ToLowerInvariant()
    $running = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    if (-not $running.Count) { return }
    Write-Status $App '' 'Closing application' 'Requesting normal closure. Save any documents if the application asks. Forced termination is not used.'
    foreach ($process in $running) {
        try { if (-not $process.HasExited) { [void]$process.CloseMainWindow() } }
        catch { Write-Status $App '' 'Close warning' $_.Exception.Message }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not @(Get-Process -Name $name -ErrorAction SilentlyContinue).Count) { return }
        Start-Sleep -Milliseconds 500
    }
    throw "$App is still running. Save your documents, close the application and retry."
}
# -----------------------------

# ----------- Install-OfficialApp ----------
function Install-OfficialApp {
    param([string]$App)
    $repo = $App.ToLowerInvariant()
    $version = ''
    Write-Status $App '' 'Checking' 'Looking for the latest stable official release.'
    try {
        try { $release = Invoke-RestMethod -Uri "https://api.github.com/repos/storytold/$repo/releases/latest" -Headers $headers -TimeoutSec 60 }
        catch {
            if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
                Write-Status $App '' 'Unavailable' 'No public repository or stable release is available at the official address.'
                return
            }
            throw
        }
        if ($release.draft -or $release.prerelease) { throw 'The release is not stable.' }
        $version = [string]$release.tag_name
        $local = Get-LocalApplication $App -Scope $script:request.Scope
        $opposite='AllUsers'
        if ($script:request.Scope -eq 'AllUsers') {$opposite='CurrentUser'}
        if (@(Get-RegisteredMsiScopes $App) -contains $opposite) {
            Write-Status $App $version 'Scope change required' 'Uninstall the existing MSI copy in Windows Settings > Apps before changing installation scope. No automatic uninstall is performed.'
            return
        }
        $latestNumber = Convert-AppVersion $version
        if ($local -and $local.Number -and $latestNumber -and $local.Number -ge $latestNumber) {
            $detail = "Installed $($local.Version) at $($local.Path). Latest stable: $version. No installation required."
            try { $detail += ' Shortcut: ' + (New-ApplicationShortcut $App $local.Path); $state='Up to date' }
            catch { $detail += ' Shortcut warning: ' + $_.Exception.Message; $state='Up to date (shortcut warning)' }
            Write-Status $App $version $state $detail
            return
        }
        $pattern = '^' + [regex]::Escape($repo) + '-[0-9][0-9A-Za-z.\-]*-windows-' + $Architecture + '\.msi$'
        $msis = @($release.assets | Where-Object { $_.name -cmatch $pattern })
        $sums = @($release.assets | Where-Object { $_.name -ceq 'SHA256SUMS.txt' })
        if ($msis.Count -ne 1 -or $sums.Count -ne 1) { throw "No unique official $Architecture MSI and checksum file were found." }
        $asset = $msis[0]
        $downloadFolder = Join-Path $script:WorkFolder 'downloads'
        New-Item -ItemType Directory -Path $downloadFolder -Force | Out-Null
        $msi = Join-Path $downloadFolder $asset.name
        $sumFile = Join-Path $downloadFolder "$repo-SHA256SUMS.txt"
        Write-Status $App $version 'Downloading' $asset.name
        Save-ReleaseAsset $sums[0] $repo $sumFile
        Save-ReleaseAsset $asset $repo $msi
        $expected = Get-ExpectedHash ([IO.File]::ReadAllText($sumFile)) $asset.name
        # Keep the package immutable until Windows Installer exits.
        $guard = [IO.File]::Open($msi, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            Write-Status $App $version 'Verifying' 'Checking SHA-256 and Windows Authenticode signature.'
            if ((Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash -ne $expected) { throw 'SHA-256 mismatch. Installation blocked.' }
            $signature = Get-AuthenticodeSignature -LiteralPath $msi
            if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) { throw "Invalid digital signature: $($signature.Status). Installation blocked." }
            # Pin the publisher organization while allowing certificate renewal.
            if ($signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Learning Machines Inc(?:,|$)') {
                throw "Unexpected publisher: $($signature.SignerCertificate.Subject). Installation blocked."
            }
            Write-Status $App $version 'Verified' ("Publisher: " + $signature.SignerCertificate.Subject + '; certificate: ' + $signature.SignerCertificate.Thumbprint)
            Assert-MsiScopeSupport $msi
            Close-RunningApplication $App
            $msiLog = Join-Path $RunFolder "$repo-msi.log"
            Write-Status $App $version 'Installing' 'Windows Installer is running. Windows may request administrator approval.'
            $arguments = '/i "' + $msi + '" /passive /norestart /L*v "' + $msiLog + '"'
            if ($script:request.Scope -eq 'AllUsers') {$arguments+=' ALLUSERS=1 MSIINSTALLPERUSER="" DESKTOPSHORTCUT=1'}
            else {$arguments+=' ALLUSERS=2 MSIINSTALLPERUSER=1 DESKTOPSHORTCUT=1'}
            $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $arguments -Wait -PassThru
            switch ($process.ExitCode) {
                0 { $resultState = 'Installed'; $resultDetail = 'Windows Installer completed successfully.' }
                3010 { $resultState = 'Restart required'; $resultDetail = 'Installed successfully. Restart Windows when convenient.' }
                1641 { $resultState = 'Restart required'; $resultDetail = 'Windows Installer reported a restart was initiated.' }
                1602 { throw 'Installation canceled or administrator approval declined.' }
                default { throw "Windows Installer exit code $($process.ExitCode). See $msiLog" }
            }
            $script:registrySnapshot=$null
            $script:msiSnapshot=$null
            if (@(Get-RegisteredMsiScopes $App) -notcontains $script:request.Scope) {
                Write-Status $App $version 'Scope verification failed' 'MSI finished, but the selected installation scope could not be confirmed in Windows registration. Inspect the MSI log before retrying.'
                return
            }
            try {
                $executable = Get-InstalledExecutable $msi $App
                $shortcutPath = New-ApplicationShortcut $App $executable
                $resultDetail += ' Desktop shortcut created: ' + $shortcutPath
            }
            catch {
                $resultState += ' (shortcut warning)'
                $resultDetail += ' Application installation succeeded, but the desktop shortcut could not be created: ' + $_.Exception.Message
            }
            Write-Status $App $version $resultState $resultDetail
        }
        finally { $guard.Dispose() }
    }
    catch { Write-Status $App $version 'Failed' $_.Exception.Message }
}
# -----------------------------

# ----------- Invoke-InstallWorker ----------
function Invoke-InstallWorker {
    $awake = $false
    $mutex = $null
    $ownsMutex = $false
    $operationCompleted = $false
    $savedTemp = $env:TEMP
    $savedTmp = $env:TMP
    $savedCargo = $env:CARGO_HOME
    $script:WorkFolder = $null
    try {
        $script:request = Get-Content -LiteralPath (Join-Path $RunFolder 'request.json') -Raw | ConvertFrom-Json
        $script:WorkFolder = [string]$script:request.WorkFolder
        if (-not $script:WorkFolder -or $script:request.WorkId -notmatch '^[a-f0-9]{32}$') { throw 'Missing temporary operation folder or identifier.' }
        $script:WorkFolder = Get-InstallerWorkFolder $script:WorkFolder ([string]$script:request.WorkId)
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $mutex = [Threading.Mutex]::new($false, ('Local\StoryToldCraftInstaller-' + $sid))
        try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (-not $ownsMutex) { throw 'Another installer operation is already running for this user. Wait for it to finish.' }
        $selected = @($script:request.Apps | Select-Object -Unique)
        if (-not $selected.Count -or @($selected | Where-Object { $_ -notin $catalog }).Count) { throw 'Invalid application selection.' }
        if ($script:request.Mode -notin @('Check','Install')) { throw 'Invalid operation.' }
        if ($script:request.Scope -notin @('CurrentUser','AllUsers')) {throw 'Invalid installation scope.'}
        Write-Status '' '' 'Installation scope' $script:request.Scope
        $env:TEMP = Join-Path $script:WorkFolder 'os-temp'
        $env:TMP = $env:TEMP
        $env:CARGO_HOME = Join-Path $script:WorkFolder 'cargo-home'
        New-Item -ItemType Directory -Path $env:TEMP,$env:CARGO_HOME -Force | Out-Null
        Write-Status '' '' 'Work folder' ("Temporary files: $script:WorkFolder. They will be removed when the operation finishes.")
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class StoryToldPower {
    // ----------- SetThreadExecutionState ----------
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern uint SetThreadExecutionState(uint flags);
    // -----------------------------
}
'@
        # ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED.
        # Hold the request during downloads, compilation, UAC, installation and cleanup.
        $awake = [StoryToldPower]::SetThreadExecutionState([uint32]2147483651) -ne 0
        if (-not $awake) { throw 'Windows standby prevention could not be enabled. Installation has not started.' }
        Write-Status '' '' 'Standby prevention active' 'Automatic system sleep and display timeout are prevented until all work and temporary cleanup finish.'
        foreach ($app in $selected) {
            $local = Get-LocalApplication $app -Scope $script:request.Scope
            $text = 'Not detected'
            if ($local) { $text=$local.Version; if (-not $text) {$text='Unknown version'} }
            Write-Status $app '' 'Local version' $text
            if ($local) { Write-Status $app '' 'Installed path' $local.Path }
            if ($script:request.Mode -eq 'Check') { Check-AppVersion $app }
            elseif ($app -eq 'SolidCraft') { Install-SolidCraftSource }
            else { Install-OfficialApp $app }
            if ($script:request.Mode -eq 'Install') {
                $script:registrySnapshot = $null
                $script:msiSnapshot = $null
                $local = Get-LocalApplication $app -Scope $script:request.Scope
                if ($local) { $text=$local.Version; if (-not $text) {$text='Unknown version'}; Write-Status $app '' 'Local version' $text; Write-Status $app '' 'Installed path' $local.Path }
            }
        }
        $operationCompleted = $true
    }
    catch { Write-Status '' '' 'Fatal' $_.Exception.Message }
    finally {
        $env:TEMP = $savedTemp
        $env:TMP = $savedTmp
        $env:CARGO_HOME = $savedCargo
        if ($script:WorkFolder) {
            for ($retry=0; $retry -lt 3; $retry++) {
                try { Remove-InstallerWorkFolder $script:WorkFolder ([string]$script:request.WorkId); Write-Status '' '' 'Cleanup complete' 'Downloaded packages, sources, Cargo cache and temporary build files were removed.'; break }
                catch { if ($retry -lt 2) { Start-Sleep -Milliseconds 500 } else { Write-Status '' '' 'Cleanup warning' $_.Exception.Message } }
            }
        }
        if ($awake) {
            [void][StoryToldPower]::SetThreadExecutionState([uint32]2147483648)
            Write-Status '' '' 'Standby prevention released' 'Normal Windows automatic sleep and display behavior restored.'
        }
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        if ($mutex) { $mutex.Dispose() }
        if ($operationCompleted) { Write-Status '' '' 'Complete' 'Selected applications have been processed. Review the results above.' }
    }
}
# -----------------------------

# ----------- Refresh-InstallScope ----------
function Refresh-InstallScope {
    $scope='CurrentUser'
    if ($script:allUsers.Checked) {$scope='AllUsers'}
    foreach ($app in $catalog) {
        $local=Get-LocalApplication $app -Scope $scope
        $text='Not detected';$path='';$state='Ready'
        if($local){$text=$local.Version;$path=$local.Path;if(-not $text){$text='Unknown version'}}
        else {
            $other=Get-LocalApplication $app
            if($other){$text='Not in selected scope';$path=$other.Path;$state='Other scope exists'}
        }
        $rows[$app].SubItems[1].Text=$text
        $rows[$app].SubItems[3].Text=$state
        $rows[$app].SubItems[4].Text=$path
        $rows[$app].ToolTipText=$path
    }
    $script:status.Text='Ready | '+(Get-Architecture)+' | Scope: '+$scope
}
# -----------------------------

# ----------- Show-Installer ----------
function Show-Installer {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    $script:form = New-Object Windows.Forms.Form
    $form.Text = 'StoryTold Craft | Install and update'
    $form.ClientSize = New-Object Drawing.Size(940,720)
    $form.MinimumSize = New-Object Drawing.Size(956,759)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object Drawing.Font('Segoe UI',10)
    $form.BackColor = [Drawing.Color]::FromArgb(245,247,250)
    $title = New-Object Windows.Forms.Label
    $title.Text = 'StoryTold Craft'
    $title.Font = New-Object Drawing.Font('Segoe UI',22,[Drawing.FontStyle]::Bold)
    $title.SetBounds(24,18,890,45)
    $form.Controls.Add($title)
    $subtitle = New-Object Windows.Forms.Label
    $subtitle.Text = 'Choose applications. Check installed versions, then install or update only when needed.'
    $subtitle.SetBounds(26,70,890,28)
    $form.Controls.Add($subtitle)
    $notice = New-Object Windows.Forms.Label
    $notice.Text = 'SolidCraft is compiled from its latest stable source (unsigned local build). Other apps use signed MSI packages.'
    $notice.SetBounds(26,104,890,42)
    $form.Controls.Add($notice)
    $all = New-Object Windows.Forms.Button
    $all.Text = 'Select all'
    $all.SetBounds(26,148,105,30)
    $all.Add_Click({ if ($script:list.Enabled) { foreach ($item in $script:list.Items) { $item.Checked=$true } } })
    $none = New-Object Windows.Forms.Button
    $none.Text = 'Select none'
    $none.SetBounds(141,148,115,30)
    $none.Add_Click({ if ($script:list.Enabled) { foreach ($item in $script:list.Items) { $item.Checked=$false } } })
    $script:setup = New-Object Windows.Forms.CheckBox
    $setup.Text = 'Set up missing build tools for SolidCraft (large downloads, may request UAC)'
    $setup.Checked = $true
    $setup.SetBounds(274,148,640,32)
    $form.Controls.AddRange(@($all,$none,$setup))
    $script:allUsers=New-Object Windows.Forms.CheckBox
    $allUsers.Text='Install for all users (Program Files, requires administrator approval). Unchecked: current user only.'
    $allUsers.Checked=$false
    $allUsers.SetBounds(26,183,888,29)
    $allUsers.Add_CheckedChanged({if($script:list -and $script:list.Enabled){Refresh-InstallScope}})
    $form.Controls.Add($allUsers)
    $script:list = New-Object Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.GridLines = $true
    $list.CheckBoxes = $true
    $list.SetBounds(26,220,888,200)
    $list.Anchor = 'Top,Left,Right'
    [void]$list.Columns.Add('Application',170)
    [void]$list.Columns.Add('Installed version',160)
    [void]$list.Columns.Add('Latest stable',140)
    [void]$list.Columns.Add('Status',390)
    [void]$list.Columns.Add('Installed path',650)
    $list.ShowItemToolTips = $true
    $script:rows = @{}
    foreach ($app in $catalog) {
        $row = New-Object Windows.Forms.ListViewItem($app)
        $row.Checked = $true
        $local = Get-LocalApplication $app
        $installedText = 'Not detected'
        if ($local) { $installedText = $local.Version; if (-not $installedText) { $installedText='Unknown version' } }
        [void]$row.SubItems.Add($installedText)
        [void]$row.SubItems.Add('Not checked')
        [void]$row.SubItems.Add('Ready')
        $installedPath = ''
        if ($local) { $installedPath=$local.Path; $row.ToolTipText=$installedPath }
        [void]$row.SubItems.Add($installedPath)
        [void]$list.Items.Add($row)
        $script:rows[$app] = $row
    }
    $script:log = New-Object Windows.Forms.TextBox
    $log.Multiline = $true
    $log.ReadOnly = $true
    $log.ScrollBars = 'Vertical'
    $log.SetBounds(26,434,888,170)
    $log.Anchor = 'Top,Bottom,Left,Right'
    $log.Text = "Save your work and close the selected apps before installing.`r`nSolidCraft: tangency-labs/solidcraft, latest stable release, pinned commit, backup and rollback."
    $log.AppendText("`r`nDownloads and build files: D:\Temp (C:\Temp fallback), removed when the operation finishes.`r`nHover an application or scroll right to see its installed path.")
    $log.AppendText("`r`nAutomatic standby and display timeout are prevented while an operation is running.`r`nScope checkbox applies to all selected apps. Changing an existing MSI scope requires uninstalling that copy first.`r`nSolidCraft: all users uses the original StoryTold folder; current user uses AppData\Local\Programs\StoryToldCraft\SolidCraft.")
    $form.Controls.AddRange(@($list,$log))
    $script:status = New-Object Windows.Forms.Label
    $status.SetBounds(26,615,888,28)
    $status.Anchor = 'Bottom,Left,Right'
    $status.Text = 'Ready | ' + (Get-Architecture)
    $form.Controls.Add($status)
    $script:install = New-Object Windows.Forms.Button
    $install.Text = 'Install / update selected'
    $install.SetBounds(26,656,250,42)
    $install.Anchor = 'Bottom,Left'
    $install.BackColor = [Drawing.Color]::FromArgb(30,95,190)
    $install.ForeColor = [Drawing.Color]::White
    $install.FlatStyle = 'Flat'
    $install.Add_Click({ Start-Installation })
    $script:check = New-Object Windows.Forms.Button
    $check.Text = 'Check versions'
    $check.SetBounds(292,656,175,42)
    $check.Anchor = 'Bottom,Left'
    $check.Add_Click({ Start-Installation -CheckOnly })
    $script:openLogs = New-Object Windows.Forms.Button
    $openLogs.Text = 'Open logs'
    $openLogs.SetBounds(483,656,145,42)
    $openLogs.Anchor = 'Bottom,Left'
    $openLogs.Enabled = $false
    $openLogs.Add_Click({ Start-Process -FilePath explorer.exe -ArgumentList ('"' + $script:activeFolder + '"') })
    $openApp = New-Object Windows.Forms.Button
    $openApp.Text = 'Open app folder'
    $openApp.SetBounds(638,656,125,42)
    $openApp.Anchor = 'Bottom,Left'
    $openApp.Add_Click({
        if ($script:list.SelectedItems.Count -and $script:list.SelectedItems[0].SubItems[4].Text) {
            $path = Split-Path -LiteralPath $script:list.SelectedItems[0].SubItems[4].Text
            if (Test-Path -LiteralPath $path -PathType Container) { Start-Process -FilePath explorer.exe -ArgumentList ('"' + $path + '"') }
        }
        else { [void][Windows.Forms.MessageBox]::Show('Select an installed application row first.','Application folder') }
    })
    $close = New-Object Windows.Forms.Button
    $close.Text = 'Close'
    $close.SetBounds(769,656,145,42)
    $close.Anchor = 'Bottom,Right'
    $close.Add_Click({ $script:form.Close() })
    $form.Controls.AddRange(@($install,$check,$openLogs,$openApp,$close))
    $script:timer = New-Object Windows.Forms.Timer
    $timer.Interval = 500
    $timer.Add_Tick({ Update-Progress })
    $form.Add_FormClosing({
        if ($script:workerProcess -and -not $script:workerProcess.HasExited) {
            $_.Cancel = $true
            [void][Windows.Forms.MessageBox]::Show('Installation is still running. Wait for completion before closing this window.','Installation in progress')
        }
    })
    Refresh-InstallScope
    try { [void]$form.ShowDialog() }
    finally { $timer.Stop(); $timer.Dispose(); $form.Dispose() }
}
# -----------------------------

# ----------- Start-Installation ----------
function Start-Installation {
    param([switch]$CheckOnly)
    $createdWork = $null
    $workerStarted = $false
    try {
        $selected = @($list.Items | Where-Object Checked | ForEach-Object Text)
        if (-not $selected.Count) { [void][Windows.Forms.MessageBox]::Show('Select at least one application.','No applications selected'); return }
        $workId = [guid]::NewGuid().ToString('N')
        $script:activeFolder = Join-Path $env:LOCALAPPDATA ('StoryToldSignedInstaller\logs\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $workId)
        New-Item -ItemType Directory -Path $script:activeFolder -Force | Out-Null
        $script:activeWorkFolder = New-InstallerWorkFolder $workId
        $createdWork = $script:activeWorkFolder
        $script:seen = 0
        $script:completed = $false
        $script:fatal = $false
        $script:cleanupWarning = $false
        foreach ($app in $catalog) { $rows[$app].SubItems[3].Text = 'Not selected' }
        foreach ($app in $selected) { $rows[$app].SubItems[3].Text = 'Waiting' }
        $mode='Install'
        if ($CheckOnly) { $mode='Check' }
        $scope='CurrentUser'
        if($allUsers.Checked){$scope='AllUsers'}
        @{Apps=$selected; Mode=$mode; Scope=$scope; SetupBuildTools=[bool]$setup.Checked; WorkFolder=$script:activeWorkFolder; WorkId=$workId} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:activeFolder 'request.json') -Encoding UTF8
        $log.Clear()
        $architectureName = Get-Architecture
        $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Worker -RunFolder "' + $script:activeFolder + '" -Architecture ' + $architectureName
        $script:workerProcess = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $script:activeFolder 'worker-output.log') -RedirectStandardError (Join-Path $script:activeFolder 'worker-error.log')
        $workerStarted = $true
        $install.Enabled = $false
        $check.Enabled = $false
        $list.Enabled = $false
        $setup.Enabled = $false
        $allUsers.Enabled = $false
        $openLogs.Enabled = $true
        $status.Text = "$mode selected applications..."
        $timer.Start()
    }
    catch {
        $message = $_.Exception.Message
        if ($createdWork -and -not $workerStarted) {
            try { Remove-InstallerWorkFolder $createdWork $workId } catch { $message += ' Temporary cleanup failed: ' + $_.Exception.Message }
        }
        [void][Windows.Forms.MessageBox]::Show($message,'Unable to start')
    }
}
# -----------------------------

# ----------- Update-Progress ----------
function Update-Progress {
    try {
        $eventFile = Join-Path $script:activeFolder 'events.jsonl'
        if (Test-Path -LiteralPath $eventFile) {
            $lines = @([IO.File]::ReadAllLines($eventFile))
            for ($index=$script:seen; $index -lt $lines.Count; $index++) {
                try { $event = $lines[$index] | ConvertFrom-Json } catch { break }
                if ($event.App -and $rows.ContainsKey($event.App)) {
                    if ($event.Version) { $rows[$event.App].SubItems[2].Text = $event.Version }
                    if ($event.State -notin @('Local version','Installed path')) { $rows[$event.App].SubItems[3].Text = $event.State }
                    if ($event.State -eq 'Installed path') { $rows[$event.App].SubItems[4].Text=$event.Detail; $rows[$event.App].ToolTipText=$event.Detail }
                    if ($event.State -eq 'Local version') { $rows[$event.App].SubItems[1].Text = $event.Detail }
                }
                $log.AppendText("$($event.Time) $($event.App) [$($event.State)] $($event.Detail)`r`n")
                if ($event.State -eq 'Complete' -or $event.State -eq 'Fatal') { $script:completed = $true }
                if ($event.State -eq 'Fatal') { $script:fatal = $true }
                if ($event.State -eq 'Cleanup warning') { $script:cleanupWarning = $true }
                $script:seen = $index + 1
            }
        }
        if ($script:workerProcess.HasExited) {
            $timer.Stop()
            $install.Enabled = $true
            $check.Enabled = $true
            $list.Enabled = $true
            $setup.Enabled = $true
            $allUsers.Enabled = $true
            $failed = @($catalog | Where-Object { $rows[$_].SubItems[3].Text -in @('Failed','Scope verification failed') }).Count
            $unavailable = @($catalog | Where-Object { $rows[$_].SubItems[3].Text -eq 'Unavailable' }).Count
            $warnings = @($catalog | Where-Object { $rows[$_].SubItems[3].Text -like '*shortcut warning*' }).Count
            $restartRequired = @($catalog | Where-Object { $rows[$_].SubItems[3].Text -like 'Restart required*' }).Count
            $scopeChanges = @($catalog | Where-Object { $rows[$_].SubItems[3].Text -eq 'Scope change required' }).Count
            if ($script:fatal) { $status.Text = 'Installation could not finish. See the error above and open logs.' }
            elseif ($script:completed) { $status.Text = "Finished | Failed: $failed | Unavailable: $unavailable | Shortcut warnings: $warnings | See logs." }
            else { $status.Text = 'Installer stopped unexpectedly. Check logs and try again.' }
            if ($script:cleanupWarning) { $status.Text += ' Temporary cleanup incomplete.' }
            if ($restartRequired) { $status.Text += ' Windows restart required.' }
            if ($scopeChanges) { $status.Text += " Scope changes needed: $scopeChanges." }
        }
    }
    catch { $status.Text = 'Waiting for installer status...' }
}
# -----------------------------

if ($SelfTest) { return }
if ($Worker) { Invoke-InstallWorker; exit }
try { Show-Installer }
catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'StoryTold installer error')
    exit 1
}
