function Test-DomainJoined {

    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop

        return [bool]$computer.PartOfDomain
    }
    catch {
        return $false
    }
}


function Get-DomainComputerInfo {

    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop

        [PSCustomObject]@{
            Компьютер       = $env:COMPUTERNAME
            Домен           = if ($computer.PartOfDomain) {
                $computer.Domain
            }
            else {
                'Не в домене'
            }
            В_домене        = if ($computer.PartOfDomain) {
                'Да'
            }
            else {
                'Нет'
            }
            Пользователь     = "$env:USERDOMAIN\$env:USERNAME"
            Роль             = switch ($computer.DomainRole) {
                0 { 'Рабочая станция' }
                1 { 'Backup DC' }
                2 { 'Member Server' }
                3 { 'Backup DC' }
                4 { 'Primary DC' }
                5 { 'Primary DC' }
                default { $computer.DomainRole }
            }
        }
    }
    catch {
        Show-Error "Не удалось получить информацию о компьютере:`n$($_.Exception.Message)"
    }
}


function Start-GPUpdate {

    Show-ToolkitHeader "ОБНОВЛЕНИЕ ГРУППОВЫХ ПОЛИТИК"

    Write-Host "Запуск gpupdate /force..." -ForegroundColor Cyan
    Write-Host ""

    try {

        & "$env:SystemRoot\System32\gpupdate.exe" /force

        if ($LASTEXITCODE -eq 0) {
            Show-Success "Групповые политики успешно обновлены."
        }
        else {
            Show-Warning "gpupdate завершился с кодом: $LASTEXITCODE"
        }
    }
    catch {

        Show-Error "Не удалось выполнить gpupdate:`n$($_.Exception.Message)"
    }
}


function Start-GPResult {

    Show-ToolkitHeader "РЕЗУЛЬТАТ ГРУППОВЫХ ПОЛИТИК"

    Write-Host "1. Краткий результат"
    Write-Host "2. Подробный HTML-отчёт"
    Write-Host ""

    $choice = Read-Host "Выберите вариант"

    switch ($choice) {

        '1' {

            Write-Host ""
            Write-Host "Получение результата..." -ForegroundColor Cyan
            Write-Host ""

            try {
                & "$env:SystemRoot\System32\gpresult.exe" /r
            }
            catch {
                Show-Error "Не удалось выполнить gpresult:`n$($_.Exception.Message)"
            }
        }

        '2' {

            $defaultPath = Join-Path $env:TEMP "GPResult_$($env:COMPUTERNAME).html"

            Write-Host ""
            Write-Host "Файл отчёта:"
            Write-Host $defaultPath
            Write-Host ""

            try {

                & "$env:SystemRoot\System32\gpresult.exe" /h $defaultPath /f

                if ($LASTEXITCODE -eq 0 -and (Test-Path $defaultPath)) {

                    Show-Success "HTML-отчёт создан."

                    Write-Host ""
                    Write-Host "Открыть отчёт? [Y/N]"

                    $open = Read-Host

                    if ($open.Trim().ToUpperInvariant() -eq 'Y') {
                        Start-Process $defaultPath
                    }
                }
                else {

                    Show-Warning "Не удалось создать HTML-отчёт. Код: $LASTEXITCODE"
                }
            }
            catch {

                Show-Error "Не удалось выполнить gpresult:`n$($_.Exception.Message)"
            }
        }

        default {
            Show-Error "Неизвестный вариант."
        }
    }
}


function Show-DomainInformation {

    Show-ToolkitHeader "ИНФОРМАЦИЯ О ДОМЕНЕ"

    try {

        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop

        Write-Host "КОМПЬЮТЕР" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"
        Write-Host "Имя:              $($computer.Name)"
        Write-Host "Домен:            $($computer.Domain)"
        Write-Host "В домене:         $(if ($computer.PartOfDomain) { 'Да' } else { 'Нет' })"
        Write-Host "Пользователь:     $env:USERDOMAIN\$env:USERNAME"

        Write-Host ""
        Write-Host "РОЛЬ КОМПЬЮТЕРА" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"

        $role = switch ($computer.DomainRole) {
            0 { 'Standalone Workstation' }
            1 { 'Member Workstation' }
            2 { 'Standalone Server' }
            3 { 'Member Server' }
            4 { 'Backup Domain Controller' }
            5 { 'Primary Domain Controller' }
            default { "Неизвестно ($($computer.DomainRole))" }
        }

        Write-Host $role

        if (-not $computer.PartOfDomain) {
            Write-Host ""
            Show-Warning "Компьютер не состоит в домене."
            return
        }

        Write-Host ""
        Write-Host "КОНТРОЛЛЕР ДОМЕНА" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"

        & "$env:SystemRoot\System32\nltest.exe" /dsgetdc:$($computer.Domain)

    }
    catch {

        Show-Error "Не удалось получить информацию о домене:`n$($_.Exception.Message)"
    }
}


function Test-DomainController {

    Show-ToolkitHeader "ПРОВЕРКА КОНТРОЛЛЕРА ДОМЕНА"

    try {

        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop

        if (-not $computer.PartOfDomain) {
            Show-Warning "Компьютер не состоит в домене."
            return
        }

        $domain = $computer.Domain

        Write-Host "Домен: $domain" -ForegroundColor Cyan
        Write-Host ""

        Write-Host "Поиск контроллера домена..." -ForegroundColor Cyan
        Write-Host ""

        & "$env:SystemRoot\System32\nltest.exe" /dsgetdc:$domain

        Write-Host ""
        Write-Host "Проверка доступности контроллеров..." -ForegroundColor Cyan
        Write-Host ""

        & "$env:SystemRoot\System32\nltest.exe" /dclist:$domain

    }
    catch {

        Show-Error "Не удалось проверить контроллер домена:`n$($_.Exception.Message)"
    }
}


function Test-DomainTime {

    Show-ToolkitHeader "ПРОВЕРКА ВРЕМЕНИ"

    Write-Host "Локальное время:" -ForegroundColor Cyan
    Write-Host (Get-Date)

    Write-Host ""
    Write-Host "Часовой пояс:" -ForegroundColor Cyan
    Write-Host ([TimeZoneInfo]::Local.DisplayName)

    Write-Host ""
    Write-Host "Состояние Windows Time:" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    try {
        & "$env:SystemRoot\System32\w32tm.exe" /query /status
    }
    catch {
        Show-Error "Не удалось получить состояние службы времени:`n$($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "Источник времени:" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    try {
        & "$env:SystemRoot\System32\w32tm.exe" /query /source
    }
    catch {
        Show-Error "Не удалось определить источник времени:`n$($_.Exception.Message)"
    }
}


function Clear-KerberosTickets {

    Show-ToolkitHeader "ОЧИСТКА KERBEROS TICKETS"

    Write-Host "Текущие билеты Kerberos:" -ForegroundColor Cyan
    Write-Host ""

    try {
        & "$env:SystemRoot\System32\klist.exe"
    }
    catch {
        Show-Error "Не удалось получить Kerberos tickets:`n$($_.Exception.Message)"
        return
    }

    Write-Host ""

    if (-not (Confirm-ToolkitAction "Удалить все Kerberos tickets текущего пользователя?")) {
        return
    }

    try {

        & "$env:SystemRoot\System32\klist.exe" purge

        if ($LASTEXITCODE -eq 0) {
            Show-Success "Kerberos tickets очищены."
        }
        else {
            Show-Warning "klist purge завершился с кодом: $LASTEXITCODE"
        }
    }
    catch {

        Show-Error "Не удалось очистить Kerberos tickets:`n$($_.Exception.Message)"
    }
}


function Test-DomainTrust {

    Show-ToolkitHeader "ДИАГНОСТИКА ДОВЕРИЯ ДОМЕНА"

    try {

        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop

        if (-not $computer.PartOfDomain) {
            Show-Warning "Компьютер не состоит в домене."
            return
        }

        Write-Host "Домен: $($computer.Domain)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Проверка защищённого канала..." -ForegroundColor Cyan
        Write-Host ""

        & "$env:SystemRoot\System32\nltest.exe" /sc_verify:$($computer.Domain)

        Write-Host ""

        if ($LASTEXITCODE -eq 0) {
            Show-Success "Защищённый канал с доменом работает."
        }
        else {
            Show-Error "Проверка защищённого канала завершилась с кодом: $LASTEXITCODE"
        }
    }
    catch {

        Show-Error "Не удалось выполнить проверку доверия:`n$($_.Exception.Message)"
    }
}


function Test-DomainShares {

    Show-ToolkitHeader "ПРОВЕРКА SYSVOL / NETLOGON"

    try {

        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop

        if (-not $computer.PartOfDomain) {
            Show-Warning "Компьютер не состоит в домене."
            return
        }

        $domain = $computer.Domain

        $paths = @(
            "\\$domain\SYSVOL",
            "\\$domain\NETLOGON"
        )

        foreach ($path in $paths) {

            Write-Host ""
            Write-Host $path -ForegroundColor Cyan

            if (Test-Path $path) {
                Show-Success "Доступен."
            }
            else {
                Show-Error "Недоступен."
            }
        }
    }
    catch {

        Show-Error "Не удалось проверить SYSVOL / NETLOGON:`n$($_.Exception.Message)"
    }
}


function Start-ActiveDirectoryMenu {

    while ($true) {

        Show-ToolkitHeader "ACTIVE DIRECTORY / ДОМЕН"

        Show-ToolkitMenuItem "1." "Обновить групповые политики (GPUpdate)"
        Show-ToolkitMenuItem "2." "Результат групповых политик (GPResult)"
        Show-ToolkitMenuItem "3." "Информация о домене"
        Show-ToolkitMenuItem "4." "Проверка контроллера домена"
        Show-ToolkitMenuItem "5." "Проверка времени"
        Show-ToolkitMenuItem "6." "Очистить Kerberos tickets"
        Show-ToolkitMenuItem "7." "Диагностика доверия домена"
        Show-ToolkitMenuItem "8." "Проверка SYSVOL / NETLOGON"

        Write-Host ""
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {
                Start-GPUpdate
                Read-ToolkitKey
            }

            '2' {
                Start-GPResult
                Read-ToolkitKey
            }

            '3' {
                Show-DomainInformation
                Read-ToolkitKey
            }

            '4' {
                Test-DomainController
                Read-ToolkitKey
            }

            '5' {
                Test-DomainTime
                Read-ToolkitKey
            }

            '6' {
                Clear-KerberosTickets
                Read-ToolkitKey
            }

            '7' {
                Test-DomainTrust
                Read-ToolkitKey
            }

            '8' {
                Test-DomainShares
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