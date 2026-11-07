param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'Installer-Storage.ps1')
. (Join-Path $PSScriptRoot 'Installer-Prerequisites.ps1')

# ----------- Write-Status ----------
function Write-Status {
    param([string]$App,[string]$Version,[string]$State,[string]$Detail)
    # Startup has its own persistent log, before the main window exists.
    Add-Content -LiteralPath (Join-Path $RunFolder 'startup.log') -Value ((Get-Date -Format o) + " [$State] $Detail")
}
# -----------------------------

# ----------- Start-StoryTold ----------
function Start-StoryTold {
    $script:WorkFolder = $null
    $id = [guid]::NewGuid().ToString('N')
    $script:RunFolder = Join-Path $env:LOCALAPPDATA ('StoryToldSignedInstaller\logs\startup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $id)
    New-Item -ItemType Directory -Path $RunFolder -Force | Out-Null
    $exitCode = 0
    try {
        if ($PSVersionTable.PSVersion -lt [version]'5.1') { throw 'Windows PowerShell 5.1 is required.' }
        $os = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        if ([int]$os.CurrentBuildNumber -lt 17763) { throw 'Windows 10 version 1809 or later is required.' }
        if ((Get-FrameworkRelease) -lt 528040) {
            $arch = $env:PROCESSOR_ARCHITEW6432
            if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
            if ($arch -eq 'ARM64') { throw '.NET Framework 4.8 or later must be restored through Windows Update on this ARM64 system.' }
            $script:WorkFolder = New-InstallerWorkFolder $id
            Install-MicrosoftDependency 'net-framework-48' 'https://go.microsoft.com/fwlink/?linkid=2088631' ('/passive /norestart /log "' + (Join-Path $RunFolder 'framework-install.html') + '"')
            if ($script:dependencyRestartRequired) { throw '.NET Framework setup requires a restart. Restart Windows, then open this installer again.' }
            if ((Get-FrameworkRelease) -lt 528040) { throw '.NET Framework 4.8 could not be verified after setup.' }
        }
        Write-Status '' '' 'Ready' '.NET Framework 4.8 or later and Windows PowerShell 5.1 are available.'
        # Use a fresh process after a Framework update; the launcher may have loaded the old CLR.
        $arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'StoryTold-Installer.ps1') + '"'
        # CreateNoWindow suppresses only the console. WindowStyle Hidden can also
        # hide the first WinForms window through the inherited STARTUPINFO state.
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $startInfo.Arguments = $arguments
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start()) { throw 'Unable to start the installer window.' }
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            [IO.File]::WriteAllText((Join-Path $RunFolder 'gui-output.log'),$outputTask.GetAwaiter().GetResult())
            [IO.File]::WriteAllText((Join-Path $RunFolder 'gui-error.log'),$errorTask.GetAwaiter().GetResult())
            if ($process.ExitCode -ne 0) { throw "The installer could not start or exited with an error. Logs: $RunFolder" }
        }
        finally { $process.Dispose() }
    }
    catch {
        $exitCode = 1
        Write-Status '' '' 'Failed' $_.Exception.Message
        $shell = New-Object -ComObject WScript.Shell
        try { [void]$shell.Popup(($_.Exception.Message + "`r`nLogs: $RunFolder"),0,'StoryTold installer',16) }
        finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    }
    finally {
        if ($script:WorkFolder) {
            try { Remove-InstallerWorkFolder $script:WorkFolder $id }
            catch { Write-Status '' '' 'Cleanup warning' $_.Exception.Message }
        }
    }
    return $exitCode
}
# -----------------------------

if (-not $SelfTest) { exit (Start-StoryTold) }
