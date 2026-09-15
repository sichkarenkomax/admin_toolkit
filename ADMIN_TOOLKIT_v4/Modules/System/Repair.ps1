function Start-SfcScan {

    Show-ToolkitHeader "SFC — ПРОВЕРКА СИСТЕМНЫХ ФАЙЛОВ"

    Write-Host "Будет выполнена проверка системных файлов Windows."
    Write-Host "Процесс может занять некоторое время."
    Write-Host ""

    if (-not (Confirm-ToolkitAction "Запустить SFC /SCANNOW?")) {
        Show-Info "Операция отменена."
        return
    }

    Write-Host ""
    & "$env:SystemRoot\System32\sfc.exe" /scannow

    Write-Host ""

    if ($LASTEXITCODE -eq 0) {
        Show-Success "SFC завершён."
    }
    else {
        Show-Warning "SFC завершён с кодом: $LASTEXITCODE"
    }
}


function Start-DismCheckHealth {

    Show-ToolkitHeader "DISM — CHECKHEALTH"

    Write-Host "Быстрая проверка состояния хранилища компонентов Windows."
    Write-Host ""

    if (-not (Confirm-ToolkitAction "Запустить DISM CheckHealth?")) {
        Show-Info "Операция отменена."
        return
    }

    Write-Host ""
    & "$env:SystemRoot\System32\Dism.exe" /Online /Cleanup-Image /CheckHealth

    Write-Host ""

    if ($LASTEXITCODE -eq 0) {
        Show-Success "DISM CheckHealth завершён."
    }
    else {
        Show-Warning "DISM завершён с кодом: $LASTEXITCODE"
    }
}


function Start-DismScanHealth {

    Show-ToolkitHeader "DISM — SCANHEALTH"

    Write-Host "Глубокая проверка хранилища компонентов Windows."
    Write-Host "Операция может занять продолжительное время."
    Write-Host ""

    if (-not (Confirm-ToolkitAction "Запустить DISM ScanHealth?")) {
        Show-Info "Операция отменена."
        return
    }

    Write-Host ""
    & "$env:SystemRoot\System32\Dism.exe" /Online /Cleanup-Image /ScanHealth

    Write-Host ""

    if ($LASTEXITCODE -eq 0) {
        Show-Success "DISM ScanHealth завершён."
    }
    else {
        Show-Warning "DISM завершён с кодом: $LASTEXITCODE"
    }
}


function Start-DismRestoreHealth {

    Show-ToolkitHeader "DISM — RESTOREHEALTH"

    Write-Host "Проверка и восстановление хранилища компонентов Windows."
    Write-Host "Операция может занять продолжительное время."
    Write-Host ""

    if (-not (Confirm-ToolkitAction "Запустить DISM RestoreHealth?")) {
        Show-Info "Операция отменена."
        return
    }

    Write-Host ""
    & "$env:SystemRoot\System32\Dism.exe" /Online /Cleanup-Image /RestoreHealth

    Write-Host ""

    if ($LASTEXITCODE -eq 0) {
        Show-Success "DISM RestoreHealth завершён."
    }
    else {
        Show-Warning "DISM завершён с кодом: $LASTEXITCODE"
    }
}


function Start-ChkDsk {

    Show-ToolkitHeader "CHKDSK"

    try {
        $disks = @(
            Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3" |
            Sort-Object DeviceID
        )
    }
    catch {
        Show-Error "Не удалось получить список дисков: $($_.Exception.Message)"
        return
    }

    if ($disks.Count -eq 0) {
        Show-Warning "Локальные диски не найдены."
        return
    }

    Write-Host "Доступные диски:"
    Write-Host ""

    foreach ($disk in $disks) {
        Write-Host "  $($disk.DeviceID)  $($disk.VolumeName)"
    }

    Write-Host ""

    $drive = Read-Host "Введите букву диска"

    if ([string]::IsNullOrWhiteSpace($drive)) {
        return
    }

    $drive = $drive.Trim().TrimEnd(':').ToUpperInvariant()

    if ($drive -notmatch '^[A-Z]$') {
        Show-Error "Некорректная буква диска."
        return
    }

    $selectedDisk = $disks |
        Where-Object { $_.DeviceID -eq "${drive}:" }

    if (-not $selectedDisk) {
        Show-Error "Диск $drive`: не найден."
        return
    }

    Write-Host ""
    Write-Host "Будет выполнена проверка:" -ForegroundColor Yellow
    Write-Host "  chkdsk ${drive}: /scan"
    Write-Host ""

    if (-not (Confirm-ToolkitAction "Запустить проверку диска?")) {
        Show-Info "Операция отменена."
        return
    }

    Write-Host ""
    & "$env:SystemRoot\System32\chkdsk.exe" "${drive}:" /scan

    Write-Host ""

    if ($LASTEXITCODE -eq 0) {
        Show-Success "CHKDSK завершён."
    }
    else {
        Show-Warning "CHKDSK завершён с кодом: $LASTEXITCODE"
    }
}


function Repair-WindowsApps {

    Show-ToolkitHeader "ПЕРЕРЕГИСТРАЦИЯ WINDOWS APPS"

    Write-Host "Будут перерегистрированы установленные приложения Windows."
    Write-Host "Операция может занять некоторое время."
    Write-Host ""

    if (-not (Confirm-ToolkitAction "Продолжить?")) {
        Show-Info "Операция отменена."
        return
    }

    Write-Host ""
    Write-Host "Получение списка приложений..." -ForegroundColor Cyan
    Write-Host ""

    try {
        $packages = @(
            Get-AppxPackage -AllUsers -ErrorAction Stop
        )
    }
    catch {
        Show-Error "Не удалось получить список приложений: $($_.Exception.Message)"
        return
    }

    $processed = 0
    $errors = 0

    foreach ($package in $packages) {

        $manifest = Join-Path $package.InstallLocation "AppxManifest.xml"

        if (-not (Test-Path $manifest)) {
            continue
        }

        try {
            Add-AppxPackage `
                -DisableDevelopmentMode `
                -Register $manifest `
                -ErrorAction Stop

            $processed++
        }
        catch {
            $errors++
        }
    }

    Write-Host ""

    Write-Host "Обработано: $processed"
    Write-Host "Ошибок:     $errors"

    if ($errors -eq 0) {
        Show-Success "Перерегистрация Windows Apps завершена."
    }
    else {
        Show-Warning "Перерегистрация завершена с ошибками."
    }
}


function Restart-ToolkitExplorer {

    Show-ToolkitHeader "ПЕРЕЗАПУСК EXPLORER"

    if (-not (Confirm-ToolkitAction "Перезапустить Windows Explorer?")) {
        Show-Info "Операция отменена."
        return
    }

    try {

        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 2

        Start-Process explorer.exe

        Show-Success "Windows Explorer перезапущен."
    }
    catch {
        Show-Error "Не удалось перезапустить Explorer: $($_.Exception.Message)"
    }
}


function Restart-ToolkitPrintSpooler {

    Show-ToolkitHeader "ПЕРЕЗАПУСК PRINT SPOOLER"

    Write-Host "Будет перезапущена служба Диспетчер печати."
    Write-Host ""

    if (-not (Confirm-ToolkitAction "Перезапустить Print Spooler?")) {
        Show-Info "Операция отменена."
        return
    }

    try {

        Restart-Service -Name Spooler -Force -ErrorAction Stop

        Show-Success "Print Spooler успешно перезапущен."
    }
    catch {
        Show-Error "Не удалось перезапустить Print Spooler: $($_.Exception.Message)"
    }
}


# ============================================================
# УПРАВЛЕНИЕ ВАЖНЫМИ СЛУЖБАМИ
# ============================================================

$Script:ImportantServices = @(
    @{
        Name        = "RpcSs"
        DisplayName = "RPC"
    },
    @{
        Name        = "EventLog"
        DisplayName = "Журнал событий"
    },
    @{
        Name        = "Winmgmt"
        DisplayName = "WMI"
    },
    @{
        Name        = "Dhcp"
        DisplayName = "DHCP Client"
    },
    @{
        Name        = "Dnscache"
        DisplayName = "DNS Client"
    },
    @{
        Name        = "LanmanWorkstation"
        DisplayName = "Рабочая станция"
    },
    @{
        Name        = "LanmanServer"
        DisplayName = "Сервер"
    },
    @{
        Name        = "BITS"
        DisplayName = "BITS"
    },
    @{
        Name        = "wuauserv"
        DisplayName = "Windows Update"
    },
    @{
        Name        = "Spooler"
        DisplayName = "Диспетчер печати"
    },
    @{
        Name        = "WinDefend"
        DisplayName = "Microsoft Defender"
    },
    @{
        Name        = "MpsSvc"
        DisplayName = "Брандмауэр Windows"
    },
    @{
        Name        = "CryptSvc"
        DisplayName = "Cryptographic Services"
    },
    @{
        Name        = "TrustedInstaller"
        DisplayName = "Windows Modules Installer"
    }
)


function Get-ImportantServices {

    $result = foreach ($item in $Script:ImportantServices) {

        try {
            $service = Get-CimInstance `
                -ClassName Win32_Service `
                -Filter "Name='$($item.Name)'" `
                -ErrorAction Stop

            if ($service) {
                [PSCustomObject]@{
                    Name        = $item.Name
                    DisplayName = $item.DisplayName
                    State       = $service.State
                    StartMode   = $service.StartMode
                    StartName   = $service.StartName
                }
            }
            else {
                [PSCustomObject]@{
                    Name        = $item.Name
                    DisplayName = $item.DisplayName
                    State       = "Не установлена"
                    StartMode   = "-"
                    StartName   = "-"
                }
            }
        }
        catch {
            [PSCustomObject]@{
                Name        = $item.Name
                DisplayName = $item.DisplayName
                State       = "Ошибка"
                StartMode   = "-"
                StartName   = "-"
            }
        }
    }

    return @($result)
}


function Get-ServiceStartModeName {

    param(
        [string]$StartMode
    )

    switch ($StartMode) {
        "Auto"     { return "Авто" }
        "Manual"   { return "Вручную" }
        "Disabled" { return "Отключена" }
        default    { return $StartMode }
    }
}


function Get-ServiceStateName {

    param(
        [string]$State
    )

    switch ($State) {
        "Running" { return "Запущена" }
        "Stopped" { return "Остановлена" }
        default   { return $State }
    }
}


function Show-ImportantServices {

    Show-ToolkitHeader "ПРОВЕРКА И УПРАВЛЕНИЕ СЛУЖБАМИ"

    $services = @(Get-ImportantServices)

    if ($services.Count -eq 0) {
        Show-Warning "Службы не найдены."
        return
    }

    Write-Host ""
    Write-Host ("{0,-4} {1,-25} {2,-15} {3,-12}" -f "№", "Служба", "Состояние", "Запуск")
    Write-Host "----------------------------------------------------------------"

    $index = 1

    foreach ($service in $services) {

        $state = Get-ServiceStateName $service.State
        $start = Get-ServiceStartModeName $service.StartMode

        $color = "Gray"

        if ($service.State -eq "Running") {
            $color = "Green"
        }
        elseif ($service.State -eq "Stopped") {
            if ($service.StartMode -eq "Auto") {
                $color = "Yellow"
            }
            else {
                $color = "Gray"
            }
        }
        elseif ($service.State -eq "Не установлена") {
            $color = "DarkGray"
        }
        else {
            $color = "Red"
        }

        Write-Host (
            "{0,-4} {1,-25} {2,-15} {3,-12}" -f
            $index,
            $service.DisplayName,
            $state,
            $start
        ) -ForegroundColor $color

        $index++
    }

    Write-Host ""
    Write-Host "Выберите номер службы для управления." -ForegroundColor Cyan
}


function Manage-ImportantService {

    param(
        [Parameter(Mandatory)]
        [int]$Index
    )

    $services = @(Get-ImportantServices)

    if ($Index -lt 1 -or $Index -gt $services.Count) {
        Show-Error "Некорректный номер службы."
        return
    }

    $serviceInfo = $services[$Index - 1]

    if ($serviceInfo.State -eq "Не установлена") {
        Show-Warning "Служба '$($serviceInfo.DisplayName)' не установлена."
        return
    }

    if ($serviceInfo.State -eq "Ошибка") {
        Show-Error "Не удалось получить состояние службы."
        return
    }

    while ($true) {

        Show-ToolkitHeader "УПРАВЛЕНИЕ СЛУЖБОЙ"

        Write-Host "Служба:       $($serviceInfo.DisplayName)"
        Write-Host "Имя:          $($serviceInfo.Name)"
        Write-Host "Состояние:    $(Get-ServiceStateName $serviceInfo.State)"
        Write-Host "Тип запуска:  $(Get-ServiceStartModeName $serviceInfo.StartMode)"

        Write-Host ""
        Write-Host "1. Запустить"
        Write-Host "2. Перезапустить"
        Write-Host "3. Остановить"

        Write-Host ""
        Write-Host "R. Обновить"
        Write-Host "0. Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {

                if ($serviceInfo.State -eq "Running") {
                    Show-Info "Служба уже запущена."
                    Read-ToolkitKey
                    continue
                }

                if (-not (Confirm-ToolkitAction "Запустить службу '$($serviceInfo.DisplayName)'?")) {
                    continue
                }

                try {

                    Start-Service `
                        -Name $serviceInfo.Name `
                        -ErrorAction Stop

                    Show-Success "Служба запущена."
                }
                catch {
                    Show-Error "Не удалось запустить службу: $($_.Exception.Message)"
                }

                Read-ToolkitKey
            }

            '2' {

                if (-not (Confirm-ToolkitAction "Перезапустить службу '$($serviceInfo.DisplayName)'?")) {
                    continue
                }

                try {

                    if ($serviceInfo.State -eq "Running") {
                        Restart-Service `
                            -Name $serviceInfo.Name `
                            -Force `
                            -ErrorAction Stop
                    }
                    else {
                        Start-Service `
                            -Name $serviceInfo.Name `
                            -ErrorAction Stop
                    }

                    Show-Success "Служба перезапущена / запущена."
                }
                catch {
                    Show-Error "Не удалось перезапустить службу: $($_.Exception.Message)"
                }

                Read-ToolkitKey
            }

            '3' {

                if ($serviceInfo.State -eq "Stopped") {
                    Show-Info "Служба уже остановлена."
                    Read-ToolkitKey
                    continue
                }

                if (-not (Confirm-ToolkitAction "Остановить службу '$($serviceInfo.DisplayName)'?")) {
                    continue
                }

                try {

                    Stop-Service `
                        -Name $serviceInfo.Name `
                        -Force `
                        -ErrorAction Stop

                    Show-Success "Служба остановлена."
                }
                catch {
                    Show-Error "Не удалось остановить службу: $($_.Exception.Message)"
                }

                Read-ToolkitKey
            }

            'R' {

                $fresh = @(Get-ImportantServices)

                $serviceInfo = $fresh |
                    Where-Object { $_.Name -eq $serviceInfo.Name }

                continue
            }

            '0' {
                return
            }

            default {
                Show-Error "Неизвестная команда."
                Start-Sleep -Milliseconds 800
            }
        }
    }
}


function Start-ImportantServicesMenu {

    while ($true) {

        Show-ImportantServices

        Write-Host ""
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            'R' {
                continue
            }

            '0' {
                return
            }

            default {

                $index = 0

                if ([int]::TryParse($choice, [ref]$index)) {
                    Manage-ImportantService -Index $index
                }
                else {
                    Show-Error "Неизвестная команда."
                    Start-Sleep -Milliseconds 800
                }
            }
        }
    }
}


# ============================================================
# ГЛАВНОЕ МЕНЮ РЕМОНТА WINDOWS
# ============================================================

function Start-RepairMenu {

    while ($true) {

        Show-ToolkitHeader "РЕМОНТ WINDOWS"

        Show-ToolkitMenuItem "1." "SFC"
        Show-ToolkitMenuItem "2." "DISM CheckHealth"
        Show-ToolkitMenuItem "3." "DISM ScanHealth"
        Show-ToolkitMenuItem "4." "DISM RestoreHealth"
        Show-ToolkitMenuItem "5." "CHKDSK"
        Show-ToolkitMenuItem "6." "Перерегистрировать Windows Apps"
        Show-ToolkitMenuItem "7." "Перезапустить Explorer"
        Show-ToolkitMenuItem "8." "Перезапустить Print Spooler"
        Show-ToolkitMenuItem "9." "Проверить и управлять службами"

        Write-Host ""
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {
                Start-SfcScan
                Read-ToolkitKey
            }

            '2' {
                Start-DismCheckHealth
                Read-ToolkitKey
            }

            '3' {
                Start-DismScanHealth
                Read-ToolkitKey
            }

            '4' {
                Start-DismRestoreHealth
                Read-ToolkitKey
            }

            '5' {
                Start-ChkDsk
                Read-ToolkitKey
            }

            '6' {
                Repair-WindowsApps
                Read-ToolkitKey
            }

            '7' {
                Restart-ToolkitExplorer
                Read-ToolkitKey
            }

            '8' {
                Restart-ToolkitPrintSpooler
                Read-ToolkitKey
            }

            '9' {
                Start-ImportantServicesMenu
            }

            'R' {
                continue
            }

            '0' {
                return
            }

            default {
                Show-Error "Неизвестная команда."
                Start-Sleep -Milliseconds 800
            }
        }
    }
}