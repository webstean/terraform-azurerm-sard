#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    return $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Test-InternetConnection {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $response = $null
    try {
        $request = [System.Net.WebRequest]::Create('http://www.msftconnecttest.com/connecttest.txt')
        $request.Timeout = 5000
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        if ($response.StatusCode -eq [System.Net.HttpStatusCode]::OK) {
            return $true
        }
    } catch {
        return $false
    } finally {
        if ($null -ne $response) {
            $response.Close()
        }
    }

    return $false
}

function Invoke-DownloadFile {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutFile
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Ensure TLS 1.2 for endpoints that reject older protocols on Windows PowerShell.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        [int]$MaxAttempts = 1,
        [int]$DelaySeconds = 2
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            & $ScriptBlock
            return
        } catch {
            if ($attempt -ge $MaxAttempts) {
                throw "$Operation failed after $MaxAttempts attempts. $($_.Exception.Message)"
            }
            Write-Warning ('{0} failed on attempt {1}/{2}: {3}. Retrying in {4} seconds...' -f $Operation, $attempt, $MaxAttempts, $_.Exception.Message, $DelaySeconds)
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Invoke-TimedStep {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Output "[START] $Name"
    try {
        & $ScriptBlock
        Write-Output ('[DONE] {0} in {1:n1}s' -f $Name, $stopwatch.Elapsed.TotalSeconds)
    } catch {
        Write-Warning ('[FAIL] {0} after {1:n1}s: {2}' -f $Name, $stopwatch.Elapsed.TotalSeconds, $_.Exception.Message)
        throw
    } finally {
        $stopwatch.Stop()
    }
}

function Invoke-ProcessWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ArgumentList,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Operation,
        [int]$TimeoutSeconds = 600
    )

    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -NoNewWindow
    try {
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            try {
                $process.Kill()
            } catch {
                Write-Warning "Failed to kill timed-out process for ${Operation}: $($_.Exception.Message)"
            }
            throw "$Operation timed out after $TimeoutSeconds seconds"
        }

        if ($process.ExitCode -ne 0) {
            throw "$Operation failed with exit code $($process.ExitCode)"
        }
    } finally {
        $process.Dispose()
    }
}

function Invoke-JobWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Operation,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [int]$TimeoutSeconds = 600
    )

    $job = Start-Job -ScriptBlock $ScriptBlock
    try {
        $completedJob = Wait-Job -Job $job -Timeout $TimeoutSeconds
        if ($null -eq $completedJob) {
            Stop-Job -Job $job -Force -ErrorAction SilentlyContinue
            throw "$Operation timed out after $TimeoutSeconds seconds"
        }
        Receive-Job -Job $job -Wait -ErrorAction Stop | Out-Null
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

function New-ItemIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function EnableNTFSLongPaths {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Enabling NTFS Long Paths...'
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Type DWord -Value 1
}
EnableNTFSLongPaths

function DisableNTFSLastAccess {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Turning off NTFS Last Access Time...'
    fsutil behavior set DisableLastAccess 1 | Out-Null
}
DisableNTFSLastAccess

function EnableAutoRebootOnCrash {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Enabling Auto Reboot on Windows Crash...'
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'AutoReboot' -Type DWord -Value 1
}
EnableAutoRebootOnCrash

function Set-EdgeNoFirstRun {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $edgePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'

    if (-not (Test-Path -Path $edgePolicyPath)) {
        New-Item -Path $edgePolicyPath -Force | Out-Null
    }

    $policies = @{
        'HideFirstRunExperience'               = 1
        'ImportFavorites'                      = 0
        'AutoImportAtFirstRun'                 = 0
        'BrowserAddProfileEnabled'             = 1
        'DefaultBrowserSettingEnabled'         = 0
        'BrowserSignin'                        = 0  
        'WebToBrowserSignInEnabled'            = 0
        'SeamlessWebToBrowserSignInEnabled'    = 0
        'ConfigureOnPremisesAccountAutoSignIn' = 1
        'ForceSync'                            = 1
    }

    foreach ($policy in $policies.GetEnumerator()) {
        New-ItemProperty -Path $edgePolicyPath -Name $policy.Key -Value $policy.Value -PropertyType DWord -Force | Out-Null
    }

    $userCtaPath = 'HKCU:\Software\Microsoft\Edge\SignIn'
    if (-not (Test-Path -Path $userCtaPath)) {
        New-Item -Path $userCtaPath -Force | Out-Null
    }

    New-ItemProperty -Path $userCtaPath -Name 'SignInCtaShownCount' -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Host 'Microsoft Edge configured to skip first run, auto sign-in, and force sync (subject to device/account setup).'
}
Set-EdgeNoFirstRun

function Disable-ServerManagerAtStartup {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Disabling Server Manager at startup...'

    # Only applies on Server editions (ProductType 2 = DC, 3 = Server)
    if (Test-CommandExists -Name 'Get-CimInstance') {
        $productType = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).ProductType
    } else {
        $productType = (Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop).ProductType
    }
    if ($productType -eq 1) {
        Write-Output 'Skipping: Server Manager is not present on Windows Client.'
        return
    }

    # Machine-wide policy (takes precedence; requires admin)
    $keyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Server\ServerManager'
    if (-not (Test-Path -Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }
    New-ItemProperty -Path $keyPath -Name 'DoNotOpenAtLogon' -PropertyType DWord -Value 1 -Force | Out-Null

    # Per-user registry setting (covers non-policy scenario)
    $userKeyPath = 'HKCU:\Software\Microsoft\ServerManager'
    if (-not (Test-Path -Path $userKeyPath)) {
        New-Item -Path $userKeyPath -Force | Out-Null
    }
    New-ItemProperty -Path $userKeyPath -Name 'DoNotOpenServerManagerAtLogon' -PropertyType DWord -Value 1 -Force | Out-Null

    # Disable the scheduled task that launches Server Manager at logon
    if ((Test-CommandExists -Name 'Get-ScheduledTask') -and (Test-CommandExists -Name 'Disable-ScheduledTask')) {
        $task = Get-ScheduledTask -TaskName 'ServerManager' -ErrorAction SilentlyContinue
        if ($task) {
            Disable-ScheduledTask -TaskName 'ServerManager' -ErrorAction SilentlyContinue | Out-Null
            Write-Output 'ServerManager scheduled task disabled.'
        }
    } else {
        Write-Warning 'Skipping scheduled task hardening because ScheduledTasks cmdlets are unavailable.'
    }

    Write-Output 'Server Manager at startup has been disabled.'
}
Disable-ServerManagerAtStartup

function Set-ServerDiagnosticsOptIn {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Accepting Windows Server diagnostic opt-in to suppress prompt...'

    # Set diagnostic data level to 3 (Optional/Full) — marks the choice as made so the
    # consent prompt never appears again. Change to 1 if you only want Required data.
    $dataCollectionKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    if (-not (Test-Path -Path $dataCollectionKey)) {
        New-Item -Path $dataCollectionKey -Force | Out-Null
    }
    New-ItemProperty -Path $dataCollectionKey -Name 'AllowTelemetry' -PropertyType DWord -Value 3 -Force | Out-Null
    New-ItemProperty -Path $dataCollectionKey -Name 'DoNotShowFeedbackNotifications' -PropertyType DWord -Value 1 -Force | Out-Null

    # Suppress "Improve your experience" / tailored tips toast for the current user
    $privacyKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'
    if (-not (Test-Path -Path $privacyKey)) {
        New-Item -Path $privacyKey -Force | Out-Null
    }
    New-ItemProperty -Path $privacyKey -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -PropertyType DWord -Value 0 -Force | Out-Null

    # Mark CEIP as opted-out so its consent prompt is suppressed
    foreach ($ceipKey in @(
            'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows',
            'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'
        )) {
        if (-not (Test-Path -Path $ceipKey)) {
            New-Item -Path $ceipKey -Force | Out-Null
        }
        New-ItemProperty -Path $ceipKey -Name 'CEIPEnable' -PropertyType DWord -Value 0 -Force | Out-Null
    }

    # Disable the CEIP and Feedback scheduled tasks that trigger the consent dialog
    $ceipTasks = @(
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' },
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'KernelCeipTask' },
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' },
        @{ Path = '\Microsoft\Windows\Feedback\Siuf\'; Name = 'DmClient' },
        @{ Path = '\Microsoft\Windows\Feedback\Siuf\'; Name = 'DmClientOnScenarioDownload' }
    )
    foreach ($t in $ceipTasks) {
        if ((Test-CommandExists -Name 'Get-ScheduledTask') -and (Test-CommandExists -Name 'Disable-ScheduledTask')) {
            $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
            if ($task) {
                Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue | Out-Null
                Write-Output "Disabled scheduled task: $($t.Path)$($t.Name)"
            }
        }
    }

    # Tell DiagTrack the toast has already been shown at level 3 so it won't re-prompt
    $diagTrackKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack'
    if (-not (Test-Path -Path $diagTrackKey)) {
        New-Item -Path $diagTrackKey -Force | Out-Null
    }
    New-ItemProperty -Path $diagTrackKey -Name 'ShowedToastAtLevel' -PropertyType DWord -Value 3 -Force | Out-Null

    Write-Output 'Windows Server diagnostic opt-in accepted and prompt suppressed.'
}
Set-ServerDiagnosticsOptIn
$regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE'
if (-not (Test-Path -Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
New-ItemProperty -Path $regPath -Name 'DisablePrivacyExperience' -PropertyType DWORD -Value 1 -Force

## Install IIS - for health check
if (Test-CommandExists -Name 'Install-WindowsFeature') {
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools
} else {
    Write-Warning 'Skipping IIS install because Install-WindowsFeature is unavailable.'
}
try {
    $path = 'C:\inetpub\wwwroot\index.html'
    $parent = Split-Path -Path $path -Parent

    if (-not (Test-Path -Path $parent)) {
        New-Item -Path $parent -ItemType Directory -Force *> $null
    }

    Set-Content -Path $path -Value '<html><body><h1>Healthy</h1></body></html>' -Force -Encoding UTF8
} catch {
    Write-Warning "Failed to write health check file: $($_.Exception.Message)"
}

function Install-Winget {
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-InternetConnection)) {
        Write-Warning 'Internet connectivity is not available. Skipping winget installation.'
        return
    }

    if (-not (Test-CommandExists -Name 'winget.exe')) {
        Invoke-TimedStep -Name 'Register PSGallery repository' -ScriptBlock {
            Invoke-WithRetry -Operation 'Register PSGallery repository' -ScriptBlock {
                if ((Test-CommandExists -Name 'Register-PSRepository') -and (Test-CommandExists -Name 'Set-PSRepository')) {
                    Register-PSRepository -Default -ErrorAction SilentlyContinue
                    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
                } else {
                    Write-Warning 'PSRepository cmdlets are unavailable. Continuing with winget bootstrap script only.'
                }
            }
        }

        $wingetInstallScript = "$env:TEMP\winget-install.ps1"
        Invoke-TimedStep -Name 'Download winget bootstrap script' -ScriptBlock {
            Invoke-WithRetry -Operation 'Download winget bootstrap script' -ScriptBlock {
                Invoke-DownloadFile -Uri 'https://raw.githubusercontent.com/asheroto/winget-install/master/winget-install.ps1' -OutFile $wingetInstallScript
            }
        }

        Invoke-TimedStep -Name 'Execute winget bootstrap script (timeout: 12m)' -ScriptBlock {
            Invoke-WithRetry -Operation 'Execute winget bootstrap script' -ScriptBlock {
                Invoke-ProcessWithTimeout -FilePath 'powershell.exe' -ArgumentList @(
                    '-NoProfile',
                    '-ExecutionPolicy',
                    'Bypass',
                    '-File',
                    $wingetInstallScript,
                    '-Force'
                ) -Operation 'winget bootstrap script' -TimeoutSeconds 720
            }
        }
    } else {
        Write-Output 'winget already installed. Skipping bootstrap install.'
    }

    if (-not (Test-CommandExists -Name 'winget.exe')) {
        throw 'winget command still unavailable after bootstrap.'
    }

    # Prime sources for unattended use; older builds may not support --disable-interactivity.
    Invoke-TimedStep -Name 'Prime winget source list (timeout: 4m)' -ScriptBlock {
        Invoke-WithRetry -Operation 'Prime winget source list' -ScriptBlock {
            try {
                Invoke-ProcessWithTimeout -FilePath 'winget.exe' -ArgumentList @(
                    'source',
                    'list',
                    '--accept-source-agreements',
                    '--disable-interactivity'
                ) -Operation 'winget source list (disable-interactivity)' -TimeoutSeconds 240
            } catch {
                Invoke-ProcessWithTimeout -FilePath 'winget.exe' -ArgumentList @(
                    'source',
                    'list',
                    '--accept-source-agreements'
                ) -Operation 'winget source list (fallback)' -TimeoutSeconds 240
            }
        }
    }

    Invoke-TimedStep -Name 'Prime winget source update (timeout: 4m)' -ScriptBlock {
        Invoke-WithRetry -Operation 'Prime winget source update' -ScriptBlock {
            try {
                Invoke-ProcessWithTimeout -FilePath 'winget.exe' -ArgumentList @(
                    'source',
                    'update',
                    '--accept-source-agreements',
                    '--disable-interactivity'
                ) -Operation 'winget source update (disable-interactivity)' -TimeoutSeconds 240
            } catch {
                Invoke-ProcessWithTimeout -FilePath 'winget.exe' -ArgumentList @(
                    'source',
                    'update',
                    '--accept-source-agreements'
                ) -Operation 'winget source update (fallback)' -TimeoutSeconds 240
            }
        }
    }

    # Remove msstore only when present.
    $wingetSources = winget source list --name msstore 2>$null
    if (-not $wingetSources) {
        $wingetSources = winget source list 2>$null
    }
    if ($wingetSources -and ($wingetSources -match 'msstore')) {
        try {
            & winget source remove msstore --disable-interactivity *> $null
            if ($LASTEXITCODE -ne 0) {
                & winget source remove msstore *> $null
            }
            if ($LASTEXITCODE -eq 0) {
                Write-Output 'winget source msstore removed.'
            } else {
                Write-Warning 'winget source msstore remove failed; continuing.'
            }
        } catch {
            Write-Warning "winget source msstore remove failed; continuing. $($_.Exception.Message)"
        }
    } else {
        Write-Output 'winget source msstore not present; skipping removal.'
    }

    # Enable winget experimental configuration feature. If settings.json is missing,
    # discover or create it first.
    try {
        $packagesRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Packages'
        $wingetPackageDir = $null

        if (Test-Path -Path $packagesRoot -PathType Container) {
            $wingetPackageDir = Get-ChildItem -Path $packagesRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Microsoft.DesktopAppInstaller_*' } |
            Select-Object -First 1
        }

        if ($null -eq $wingetPackageDir) {
            $wingetPackageDirPath = Join-Path -Path $packagesRoot -ChildPath 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
        } else {
            $wingetPackageDirPath = $wingetPackageDir.FullName
        }

        $settingsDir = Join-Path -Path $wingetPackageDirPath -ChildPath 'LocalState'
        $settingsPath = Join-Path -Path $settingsDir -ChildPath 'settings.json'

        if (-not (Test-Path -Path $settingsDir -PathType Container)) {
            New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
        }

        if (-not (Test-Path -Path $settingsPath -PathType Leaf)) {
            '{"$schema":"https://aka.ms/winget-settings.schema.json"}' | Out-File -FilePath $settingsPath -Encoding utf8 -Force
        }

        try {
            $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Warning 'winget settings.json is invalid. Recreating default settings file.'
            '{"$schema":"https://aka.ms/winget-settings.schema.json"}' | Out-File -FilePath $settingsPath -Encoding utf8 -Force
            $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop
        }

        if (-not $settings.experimentalFeatures) {
            $settings | Add-Member -NotePropertyName experimentalFeatures -NotePropertyValue @{}
        }
        $settings.experimentalFeatures | Add-Member -NotePropertyName configuration -NotePropertyValue $true -Force
        $settings | ConvertTo-Json -Depth 10 | Out-File -FilePath $settingsPath -Encoding utf8 -Force
    } catch {
        Write-Warning "Unable to update winget settings.json; continuing. $($_.Exception.Message)"
    }

    # Install WinGet DSC helper with fallback based on available package manager cmdlets.
    try {
        if (Test-CommandExists -Name 'Install-PSResource') {
            Invoke-TimedStep -Name 'Install Microsoft.WinGet.DSC with Install-PSResource (timeout: 6m)' -ScriptBlock {
                Invoke-JobWithTimeout -Operation 'Install-PSResource Microsoft.WinGet.DSC' -TimeoutSeconds 360 -ScriptBlock {
                    Install-PSResource -Name Microsoft.WinGet.DSC -Repository PSGallery -Force -AllowClobber -Scope AllUsers
                }
            }
        } elseif (Test-CommandExists -Name 'Install-Module') {
            Invoke-TimedStep -Name 'Install Microsoft.WinGet.DSC with Install-Module (timeout: 6m)' -ScriptBlock {
                Invoke-JobWithTimeout -Operation 'Install-Module Microsoft.WinGet.DSC' -TimeoutSeconds 360 -ScriptBlock {
                    Install-Module -Name Microsoft.WinGet.DSC -Repository PSGallery -Force -AllowClobber -Scope AllUsers
                }
            }
        } else {
            Write-Warning 'Neither Install-PSResource nor Install-Module is available; skipping Microsoft.WinGet.DSC install.'
        }
    } catch {
        Write-Warning "Failed to install Microsoft.WinGet.DSC; continuing. $($_.Exception.Message)"
    }
}
#Install-Winget

function Install-PowerShell {
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-InternetConnection)) {
        Write-Warning 'Internet connectivity is not available. Skipping PowerShell installation.'
        return
    }

    $targetVersion = [version]'7.6.4'
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -ne $pwsh) {
        $currentVersion = [version](& $pwsh.Source -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')
        if ($currentVersion -ge $targetVersion) {
            Write-Output "PowerShell $currentVersion already installed. Skipping MSI install."
            return
        }
    }

    $msiUrl = 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.4/PowerShell-7.6.4-win-x64.msi'
    $msiPath = "$env:TEMP\PowerShell-7.6.4-win-x64.msi"

    Invoke-TimedStep -Name 'Download PowerShell MSI' -ScriptBlock {
        Invoke-DownloadFile -Uri $msiUrl -OutFile $msiPath
    }

    $installArgs = @(
        '/i', "`"$msiPath`"",
        '/quiet',
        '/norestart',
        'ADD_PATH=1',
        'ENABLE_PSREMOTING=1'
    )

    Invoke-TimedStep -Name 'Install PowerShell MSI (timeout: 8m)' -ScriptBlock {
        Invoke-ProcessWithTimeout -FilePath 'msiexec.exe' -ArgumentList $installArgs -Operation 'PowerShell 7 MSI install' -TimeoutSeconds 480
    }

    Remove-Item -Path $msiPath -Force -ErrorAction SilentlyContinue
}
#Install-PowerShell

$BIN = "$env:SystemDrive\BIN"
if (-not (Test-Path -Path "${BIN}" -PathType Container -ErrorAction SilentlyContinue)) {
    New-Item -Path "${BIN}" -ItemType Directory -Force | Out-Null
} else {
    Write-Output "Directory ${BIN} already exists." 
}

function Install-SysInternalsProductionTools {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Bin
    )

    Write-Output 'Installing a small subset of SysInternals tools for troubleshooting production machines...' 
    Write-Output 'Turning off Sysinternals EULA prompt.' 
    if (-not (Test-Path -Path 'HKCU:\Software\Sysinternals')) {
        New-Item -Path 'HKCU:\Software\Sysinternals' -Force | Out-Null
    }
    if (-not (Test-Path -Path 'HKLM:\Software\Sysinternals')) {
        New-Item -Path 'HKLM:\Software\Sysinternals' -Force | Out-Null
    }

    if (Get-ItemProperty -Path 'HKCU:\Software\Sysinternals' -Name 'EulaAccepted' -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path 'HKCU:\Software\Sysinternals' -Name 'EulaAccepted' -Value 1
    } else {
        New-ItemProperty -Path 'HKCU:\Software\Sysinternals' -Name 'EulaAccepted' -PropertyType DWORD -Value 1
    }
    if (Get-ItemProperty -Path 'HKLM:\Software\Sysinternals' -Name 'EulaAccepted' -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path 'HKLM:\Software\Sysinternals' -Name 'EulaAccepted' -Value 1
    } else {
        New-ItemProperty -Path 'HKLM:\Software\Sysinternals' -Name 'EulaAccepted' -PropertyType DWORD -Value 1
    }

    if (-not (Test-InternetConnection)) {
        Write-Warning 'Internet connectivity is not available. Skipping SysInternals tools installation.'
        return
    }

    $tools = @(
        @{ Name = 'ZoomIt64.exe'; Friendly = 'ZoomIt.exe' },
        @{ Name = 'tcpview64.exe'; Friendly = 'TCP View.exe' },
        @{ Name = 'winobj64.exe'; Friendly = 'Windows Object Viewer.exe' },
        @{ Name = 'psping64.exe'; Friendly = 'PSPing.exe' },
        @{ Name = 'handle64.exe'; Friendly = 'handle.exe' },
        @{ Name = 'procexp64.exe'; Friendly = 'Process Explorer.exe' },
        @{ Name = 'procmon64.exe'; Friendly = 'Process Monitor.exe' },
        @{ Name = 'Bginfo64.exe'; Friendly = 'BGInfo.exe' }
    )

    foreach ($entry in $tools) {
        $tool = $entry.Name
        $friendlyName = $entry.Friendly
        $url = "https://live.sysinternals.com/$tool"
        if ([string]::IsNullOrWhiteSpace($friendlyName)) {
            $outfile = Join-Path -Path $Bin -ChildPath $tool
        } else {
            $outfile = Join-Path -Path $Bin -ChildPath $friendlyName
        }
        Invoke-WithRetry -Operation "Download $tool" -ScriptBlock {
            Invoke-WebRequest -Uri $url -OutFile $outfile -UseBasicParsing
        }
    }
    ##Invoke-WebRequest -Uri https://www.7-zip.org/a/7z2409-x64.exe -OutFile $Bin\unzip.exe
}
Install-SysInternalsProductionTools -Bin $BIN
if (Test-CommandExists -Name 'Add-MpPreference') {
    Add-MpPreference -ExclusionPath $BIN
} else {
    Write-Warning 'Skipping Defender exclusion because Add-MpPreference is unavailable.'
}

if (Test-CommandExists -Name 'openfiles.exe') {
    openfiles /local on
} else {
    Write-Warning 'Skipping openfiles /local on because openfiles.exe is unavailable.'
}

function Set-IPv4Preference {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    ## Prefer IPv4 over IPv6 with 0x20, disable IPv6 with 0xff, revert to default with 0x00.
    $setting = 0x20
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' -Name 'DisabledComponents' -Type DWord -Value $setting
}

function Disable-IPv6Binding {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ((Test-CommandExists -Name 'Get-NetAdapterBinding') -and (Test-CommandExists -Name 'Disable-NetAdapterBinding')) {
        # More radical - typically not necessary
        Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq 'ms_tcpip6' } | ForEach-Object {
            Disable-NetAdapterBinding -Name $_.Name -ComponentID 'ms_tcpip6'
        }
    } else {
        Write-Warning 'Skipping IPv6 adapter unbind because NetAdapter cmdlets are unavailable.'
    }
}

function DisableInbuiltDNS {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $disableBuiltInDNS = 0x00

    Write-Output 'Disabling Browser InBuilt DNS...'
    ## Disabled Inbuilt DNS for Microsoft Edge
    New-ItemIfMissing -Path 'HKLM:\SOFTWARE\Policies\Microsoft'
    New-ItemIfMissing -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'DnsOverHttpsMode' -Value 'off'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'BuiltInDnsClientEnabled' -Type DWord -Value $disableBuiltInDNS

    ## Disabled Inbuilt DNS for Google Chrome
    New-ItemIfMissing -Path 'HKLM:\SOFTWARE\Policies\Google'
    New-ItemIfMissing -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name 'DnsOverHttpsMode' -Value 'off'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name 'BuiltInDnsClientEnabled' -Type DWord -Value $disableBuiltInDNS
}

function DisableQUIC {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Disabling network QUIC protocol...'
    ## QUIC is currently supported WITH Private Access and Microsoft 365 workloads but NOT in Internet Access
    $disableQUIC = 0x00
    New-ItemIfMissing -Path 'HKLM:\SOFTWARE\Policies\Microsoft'
    New-ItemIfMissing -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    New-ItemIfMissing -Path 'HKLM:\SOFTWARE\Policies\Google'
    New-ItemIfMissing -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'QuicAllowed' -Value $disableQUIC -Type DWord -Force
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name 'QuicAllowed' -Value $disableQUIC -Type DWord -Force
}

function DisableNetBIOS {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Disabling NetBIOS over TCP/IP on all adapters...'
    if (-not (Test-CommandExists -Name 'Get-WmiObject')) {
        Write-Warning 'Skipping NetBIOS disable because Get-WmiObject is unavailable.'
        return
    }

    # Disable NetBIOS over TCP/IP on all adapters
    Get-WmiObject Win32_NetworkAdapterConfiguration |
    Where-Object { $null -ne $_.TcpipNetbiosOptions } |
    ForEach-Object {
        try {
            $null = $_.SetTcpipNetbios(2)
        } catch {
            Write-Warning "Failed to disable NetBIOS on adapter index $($_.Index): $($_.Exception.Message)"
        }
    }
}

# Static IP, no DHCP, on prod servers


## Configure for MAXIMUM compatibility with Microsoft Global Secure Access and other similar (Cisco Umbrella etc..)
Set-IPv4Preference
# Disable-IPv6Binding
DisableInbuiltDNS
DisableQUIC
DisableNetBIOS

try {
    if (Test-CommandExists -Name 'powercfg') {
        # High performance; avoid Balanced on server workloads when supported.
        powercfg /setactive SCHEME_MIN | Out-Null
    } else {
        Write-Warning 'Skipping power scheme update because powercfg is unavailable.'
    }
} catch {
    Write-Warning "Failed to set power scheme to SCHEME_MIN: $($_.Exception.Message)"
}

try {
    if (Test-CommandExists -Name 'Set-Volume') {
        Set-Volume -DriveLetter C -NewFileSystemLabel 'PRODUCTION'
    } else {
        Write-Warning 'Skipping volume label update because Set-Volume is unavailable.'
    }
} catch {
    Write-Warning "Failed to set C: volume label: $($_.Exception.Message)"
}

if (Test-InternetConnection) {
    try {
        if (Test-CommandExists -Name 'w32tm') {
            w32tm /config /manualpeerlist:"time.windows.com,0x8" /syncfromflags:manual /reliable:yes /update
            w32tm /resync ## Time needs to be insync, for Windows activation to work properly   
        }
    } catch {
        Write-Warning "Failed to configure time service: $($_.Exception.Message)"
    }
}

try {
    auditpol /set /category:"Logon/Logoff" /success:enable /failure:enable
    auditpol /set /category:"Account Logon" /success:enable /failure:enable
} catch {
    Write-Warning "Failed to configure audit policy: $($_.Exception.Message)"
}

$script:HostInfoCache = @{}

function Write-StepSummary {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        $InputObject,

        [Parameter()]
        [ValidateSet('info', 'warning', 'success', 'error', 'debug', 'wait', 'waiting', 'warn', 'exception', 'skip', 'start', 'complete', 'completed')]
        [string]$Type = 'info',

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [bool]$ShowTimeStamp = $true
    
    )

    begin {
        $useGitHubSummary = -not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)

        $prefixMap = @{
            exception = '❌❌'
            info      = 'ℹ️'
            success   = '✅'
            error     = '❌'
            debug     = '🔍'
            wait      = '⏳'
            waiting   = '⏳'
            warn      = '⚠️'
            warning   = '⚠️'
            skip      = '⏭️'
            start     = '🚀'
            complete  = '🏁'
            completed = '🏁'
        }

        $prefix = $prefixMap[$Type]
    }

    process {
        $text = if ($null -eq $InputObject) {
            ''
        } elseif ($InputObject -is [string]) {
            $InputObject
        } else {
            ($InputObject | Out-String).TrimEnd()
        }

        if ($showTimeStamp) {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $line = "${timestamp}: ${prefix}: $text"
        } else {
            $line = "${prefix}: $text"
        }
        
        if ($useGitHubSummary) {
            Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $line -Encoding utf8
        } else {

            switch ($Type) {
                'error' {
                    Write-Error -Message $line
                }

                'exception' {
                    Write-Error -Message $line
                }

                'debug' {
                    Write-Verbose -Message $line
                }

                { $_ -in @('warn', 'warning') } {
                    Write-Warning -Message $line
                }

                default {
                    Write-Host $line
                }
            }
        }
        if ($PassThru) {
            $line
        }
    }
}

function Update-ProfileForce {
    param(
        [string] $Uri = 'https://raw.githubusercontent.com/webstean/setup/main/intune/good_profile.ps1',

        [string] $ProfilePath = $PROFILE,

        [ValidateSet('utf8NoBOM', 'utf8BOM', 'ascii')]
        [string] $Encoding = 'ascii',

        [switch] $Backup
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
        return
    }

    $profileDir = Split-Path -Path $ProfilePath -Parent

    if (-not (Test-Path -Path $profileDir -PathType Container)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    try {
        $response = Invoke-WebRequest `
            -Uri $Uri `
            -UseBasicParsing `
            -Headers @{ 'Cache-Control' = 'no-cache' } `
            -ErrorAction Stop
    } catch {
        return 
        #throw "Failed to download profile from '$Uri'. $($_.Exception.Message)"
    }

    if ($response.StatusCode -lt 200 -or $response.StatusCode -gt 299) {
        return 
        #throw "Download failed. HTTP status: $($response.StatusCode) $($response.StatusDescription)"
    }

    $newContent = [string] $response.Content

    if ([string]::IsNullOrWhiteSpace($newContent)) {
        return 
        #throw 'Downloaded profile content is empty.'
    }

    $oldContent = $null
    $exists = Test-Path -Path $ProfilePath -PathType Leaf

    if ($exists) {
        $oldContent = Get-Content -Path $ProfilePath -Raw -ErrorAction Stop
    }

    $oldNormalized = if ($null -ne $oldContent) {
        $oldContent.Trim() -replace "`r`n", "`n"
    } else {
        $null
    }

    $newNormalized = $newContent.Trim() -replace "`r`n", "`n"

    if ($exists -and $oldNormalized -ceq $newNormalized) {
        Write-Host "Profile already current: $ProfilePath" -ForegroundColor Yellow
        return
    }

    if ($Backup -and $exists) {
        $backupPath = "$ProfilePath.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
        Copy-Item -Path $ProfilePath -Destination $backupPath -Force
        Write-Host "Backup created: $backupPath" -ForegroundColor DarkCyan
    }

    Set-Content `
        -Path $ProfilePath `
        -Value $newContent `
        -Encoding $Encoding `
        -Force

    Write-Host "Profile updated: $ProfilePath" -ForegroundColor Green
}
if (Test-InternetConnection) {
    Update-ProfileForce -Backup
}

if (Test-InternetConnection) {
    & ${BIN}\psping.exe -q kms.core.windows.net:1688
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        Write-StepSummary -type 'success' 'Azure KMS host reachable on 1688'
    } else {
        Write-StepSummary -type 'error' "Failed: could not reach KMS host on 1688 (exit code $exitCode)"
    }
}

if (Test-Path "${BIN}\config.bgi") {
    & ${BIN}\bginfo.exe ${BIN}\config.bgi /timer:0
}

#try {
#    if (Get-NetAdapterRdma | Where-Object { $_.Enabled -eq $true }) {
#        Write-StepSummary -type 'info' 'RDMA capable network adapter found.'
#    }
#    if (Get-SmbClientNetworkInterface | Where-Object { $_.'RDMA Capable' -eq $true }) {
#        Write-StepSummary -type 'info' 'RDMA capable SMB client network interface found.'
#    }
#} catch {
#    Write-StepSummary -type 'error' "Error retrieving network adapter RDMA information: $($_.Exception.Message)"
#}

exit 0
