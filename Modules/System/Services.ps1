$Script:CommonServices = @(
    [PSCustomObject]@{
        Name = 'wuauserv'
        Description = 'Центр обновления Windows'
    },
    [PSCustomObject]@{
        Name = 'BITS'
        Description = 'Фоновая интеллектуальная служба передачи'
    },
    [PSCustomObject]@{
        Name = 'Spooler'
        Description = 'Диспетчер печати'
    },
    [PSCustomObject]@{
        Name = 'WinRM'
        Description = 'Удаленное управление Windows'
    },
    [PSCustomObject]@{
        Name = 'WinDefend'
        Description = 'Microsoft Defender'
    },
    [PSCustomObject]@{
        Name = 'Dnscache'
        Description = 'DNS-клиент'
    },
    [PSCustomObject]@{
        Name = 'Dhcp'
        Description = 'DHCP-клиент'
    },
    [PSCustomObject]@{
        Name = 'NlaSvc'
        Description = 'Служба сведений о сетях'
    }
)


function Get-ToolkitServices {
    Get-Service | Sort-Object Status, DisplayName
}


function Show-StoppedServices {

    Show-ToolkitHeader "НЕ РАБОТАЮЩИЕ СЛУЖБЫ"

    $services = @(
        Get-Service |
            Where-Object { $_.Status -ne 'Running' } |
            Sort-Object DisplayName
    )

    if ($services.Count -eq 0) {
        Show-Success "Все службы находятся в состоянии Running."
        return
    }

    $services |
        Select-Object Status, StartType, Name, DisplayName |
        Format-Table -AutoSize
}


function Find-ToolkitService {

    Show-ToolkitHeader "ПОИСК СЛУЖБЫ"

    $query = Read-Host "Введите часть имени службы"

    if ([string]::IsNullOrWhiteSpace($query)) {
        return
    }

    Get-Service |
        Where-Object {
            $_.Name -like "*$query*" -or
            $_.DisplayName -like "*$query*"
        } |
        Sort-Object DisplayName |
        Select-Object Status, StartType, Name, DisplayName |
        Format-Table -AutoSize
}


function Show-ServiceStatus {

    Show-ToolkitHeader "СОСТОЯНИЕ СЛУЖБЫ"

    $name = Read-Host "Введите имя службы"

    if ([string]::IsNullOrWhiteSpace($name)) {
        return
    }

    try {
        $service = Get-Service -Name $name -ErrorAction Stop

        $service |
            Format-List Status, StartType, Name, DisplayName
    }
    catch {
        Show-Error "Служба не найдена: $name"
    }
}


function Start-ToolkitServiceAction {

    Show-ToolkitHeader "ЗАПУСК СЛУЖБЫ"

    $name = Read-Host "Введите имя службы"

    if ([string]::IsNullOrWhiteSpace($name)) {
        return
    }

    try {
        $service = Get-Service -Name $name -ErrorAction Stop

        if ($service.Status -eq 'Running') {
            Show-Info "Служба уже запущена."
            return
        }

        if (-not (Confirm-ToolkitAction "Запустить службу '$($service.DisplayName)'?")) {
            return
        }

        Start-Service -Name $name -ErrorAction Stop

        Show-Success "Служба запущена."
    }
    catch {
        Show-Error "Не удалось запустить службу:`n$($_.Exception.Message)"
    }
}


function Stop-ToolkitServiceAction {

    Show-ToolkitHeader "ОСТАНОВКА СЛУЖБЫ"

    $name = Read-Host "Введите имя службы"

    if ([string]::IsNullOrWhiteSpace($name)) {
        return
    }

    try {
        $service = Get-Service -Name $name -ErrorAction Stop

        if ($service.Status -ne 'Running') {
            Show-Info "Служба уже не запущена."
            return
        }

        if (-not (Confirm-ToolkitAction "Остановить службу '$($service.DisplayName)'?")) {
            return
        }

        Stop-Service -Name $name -ErrorAction Stop

        Show-Success "Служба остановлена."
    }
    catch {
        Show-Error "Не удалось остановить службу:`n$($_.Exception.Message)"
    }
}


function Restart-ToolkitServiceAction {

    Show-ToolkitHeader "ПЕРЕЗАПУСК СЛУЖБЫ"

    $name = Read-Host "Введите имя службы"

    if ([string]::IsNullOrWhiteSpace($name)) {
        return
    }

    try {
        $service = Get-Service -Name $name -ErrorAction Stop

        if (-not (Confirm-ToolkitAction "Перезапустить службу '$($service.DisplayName)'?")) {
            return
        }

        Restart-Service -Name $name -Force -ErrorAction Stop

        Show-Success "Служба перезапущена."
    }
    catch {
        Show-Error "Не удалось перезапустить службу:`n$($_.Exception.Message)"
    }
}


function Set-ToolkitServiceStartupType {

    Show-ToolkitHeader "ТИП ЗАПУСКА СЛУЖБЫ"

    $name = Read-Host "Введите имя службы"

    if ([string]::IsNullOrWhiteSpace($name)) {
        return
    }

    try {
        $service = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction Stop

        if (-not $service) {
            throw "Служба не найдена."
        }

        Write-Host ""
        Write-Host "1. Автоматически"
        Write-Host "2. Автоматически (отложенный запуск)"
        Write-Host "3. Вручную"
        Write-Host "4. Отключена"

        $choice = Read-Host "Выберите тип запуска"

        $mode = switch ($choice) {
            '1' { 'Auto' }
            '2' { 'Auto' }
            '3' { 'Manual' }
            '4' { 'Disabled' }
            default { $null }
        }

        if (-not $mode) {
            Show-Error "Неизвестный вариант."
            return
        }

        if (-not (Confirm-ToolkitAction "Изменить тип запуска службы '$($service.DisplayName)'?")) {
            return
        }

        Set-Service -Name $name -StartupType $mode -ErrorAction Stop

        Show-Success "Тип запуска изменён."
    }
    catch {
        Show-Error "Не удалось изменить тип запуска:`n$($_.Exception.Message)"
    }
}


function Show-CommonServices {

    Show-ToolkitHeader "ЧАСТО ИСПОЛЬЗУЕМЫЕ СЛУЖБЫ"

    $rows = foreach ($item in $Script:CommonServices) {

        try {
            $service = Get-Service -Name $item.Name -ErrorAction Stop

            [PSCustomObject]@{
                Name = $service.Name
                Status = $service.Status
                StartType = $service.StartType
                Description = $item.Description
            }
        }
        catch {

            [PSCustomObject]@{
                Name = $item.Name
                Status = 'Не найдена'
                StartType = '-'
                Description = $item.Description
            }
        }
    }

    $rows | Format-Table -AutoSize
}


function Start-ServicesMenu {

    while ($true) {

        Show-ToolkitHeader "СЛУЖБЫ"

        Show-ToolkitMenuItem "1." "Не работающие службы"
        Show-ToolkitMenuItem "2." "Поиск службы"
        Show-ToolkitMenuItem "3." "Состояние службы"
        Show-ToolkitMenuItem "4." "Запустить службу"
        Show-ToolkitMenuItem "5." "Остановить службу"
        Show-ToolkitMenuItem "6." "Перезапустить службу"
        Show-ToolkitMenuItem "7." "Изменить тип запуска"
        Show-ToolkitMenuItem "8." "Часто используемые службы"

        Write-Host ""
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {
                Show-StoppedServices
                Read-ToolkitKey
            }

            '2' {
                Find-ToolkitService
                Read-ToolkitKey
            }

            '3' {
                Show-ServiceStatus
                Read-ToolkitKey
            }

            '4' {
                Start-ToolkitServiceAction
                Read-ToolkitKey
            }

            '5' {
                Stop-ToolkitServiceAction
                Read-ToolkitKey
            }

            '6' {
                Restart-ToolkitServiceAction
                Read-ToolkitKey
            }

            '7' {
                Set-ToolkitServiceStartupType
                Read-ToolkitKey
            }

            '8' {
                Show-CommonServices
                Read-ToolkitKey
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