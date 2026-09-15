function Read-EventLogDays {

    while ($true) {

        $inputValue = Read-Host "Количество дней"

        [int]$days = 0

        if ([int]::TryParse($inputValue, [ref]$days)) {

            if ($days -gt 0) {
                return $days
            }
        }

        Show-Error "Введите целое число больше 0."
    }
}


function Get-ToolkitEventLogErrors {

    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('System', 'Application')]
        [string]$LogName,

        [Parameter(Mandatory = $true)]
        [int]$Days
    )

    $startTime = (Get-Date).AddDays(-$Days)

    try {

        $events = @(
            Get-WinEvent -FilterHashtable @{
                LogName   = $LogName
                Level     = 2
                StartTime = $startTime
            } -ErrorAction Stop
        )

        return $events
    }
    catch [System.Diagnostics.Eventing.Reader.EventLogNotFoundException] {

        Show-Error "Журнал '$LogName' не найден."
        return @()
    }
    catch [System.Diagnostics.Eventing.Reader.EventLogException] {

        if (
            $_.Exception.Message -match
            'Не найдены события|No events were found|No events found'
        ) {
            return @()
        }

        Show-Error "Не удалось прочитать журнал '$LogName':`n$($_.Exception.Message)"
        return @()
    }
    catch {

        if (
            $_.Exception.Message -match
            'Не найдены события|No events were found|No events found'
        ) {
            return @()
        }

        Show-Error "Не удалось прочитать журнал '$LogName':`n$($_.Exception.Message)"
        return @()
    }
}


function Show-EventLogSummary {

    param(
        [Parameter()]
        [array]$Events,

        [Parameter(Mandatory = $true)]
        [string]$LogName,

        [Parameter(Mandatory = $true)]
        [int]$Days
    )

    if (-not $Events -or $Events.Count -eq 0) {
        return
    }

    Write-Host ""
    Write-Host "СВОДКА" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    Write-Host "Журнал:        $LogName"
    Write-Host "Период:        последние $Days дн."
    Write-Host "Всего ошибок:  $($Events.Count)"

    $providers = @(
        $Events |
            Group-Object ProviderName |
            Sort-Object Count -Descending
    )

    if ($providers.Count -gt 0) {

        Write-Host ""
        Write-Host "ПО ИСТОЧНИКАМ" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"

        $providers |
            Select-Object `
                @{Name = 'Количество'; Expression = { $_.Count }},
                @{Name = 'Источник'; Expression = { $_.Name }} |
            Format-Table -AutoSize
    }
}


function Show-EventLogList {

    param(
        [Parameter()]
        [array]$Events
    )

    if (-not $Events -or $Events.Count -eq 0) {
        return
    }

    Write-Host ""
    Write-Host "ОШИБКИ" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    $limit = [Math]::Min($Events.Count, 100)

    $rows = @()

    for ($i = 0; $i -lt $limit; $i++) {

        $event = $Events[$i]

        $message = ''

        if ($event.Message) {
            $message = ($event.Message -replace '\s+', ' ').Trim()
        }

        if ($message.Length -gt 120) {
            $message = $message.Substring(0, 117) + '...'
        }

        $rows += [PSCustomObject]@{
            '№'         = $i + 1
            'Время'     = $event.TimeCreated
            'Источник'  = $event.ProviderName
            'EventID'   = $event.Id
            'Сообщение' = $message
        }
    }

    $rows |
        Format-Table -Wrap -AutoSize

    if ($Events.Count -gt 100) {

        Write-Host ""

        Show-Warning (
            "Показаны первые 100 событий из $($Events.Count)."
        )
    }
}


function Show-EventLogDetails {

    param(
        [Parameter()]
        [array]$Events
    )

    if (-not $Events -or $Events.Count -eq 0) {

        Show-Warning "Нет событий для просмотра."
        return
    }

    Write-Host ""

    $maxNumber = [Math]::Min($Events.Count, 100)

    $number = Read-Host "Введите номер события (1-$maxNumber)"

    [int]$index = 0

    if (-not [int]::TryParse($number, [ref]$index)) {

        Show-Error "Некорректный номер."
        return
    }

    if ($index -lt 1 -or $index -gt $maxNumber) {

        Show-Error "Событие с таким номером не найдено."
        return
    }

    $event = $Events[$index - 1]

    Show-ToolkitHeader "ПОДРОБНОСТИ СОБЫТИЯ"

    Write-Host "№:            $index"
    Write-Host "Журнал:       $($event.LogName)"
    Write-Host "Время:        $($event.TimeCreated)"
    Write-Host "Источник:     $($event.ProviderName)"
    Write-Host "Event ID:     $($event.Id)"
    Write-Host "Уровень:      $($event.LevelDisplayName)"
    Write-Host "Компьютер:    $($event.MachineName)"

    if ($event.UserId) {

        try {

            $account = $event.UserId.Translate(
                [System.Security.Principal.NTAccount]
            ).Value

            Write-Host "Пользователь: $account"
        }
        catch {

            Write-Host "Пользователь: $($event.UserId.Value)"
        }
    }

    Write-Host ""
    Write-Host "СООБЩЕНИЕ" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    if ($event.Message) {
        Write-Host $event.Message
    }
    else {
        Show-Warning "Текст сообщения отсутствует."
    }
}


function Show-ToolkitEventLog {

    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('System', 'Application')]
        [string]$LogName
    )

    Show-ToolkitHeader "ОШИБКИ ЖУРНАЛА: $LogName"

    $days = Read-EventLogDays

    Write-Host ""
    Write-Host "Поиск ошибок за последние $days дн...." -ForegroundColor Cyan

    $events = @(Get-ToolkitEventLogErrors `
        -LogName $LogName `
        -Days $days
    )

    Write-Host ""
    Write-Host "Журнал: $LogName" -ForegroundColor Cyan
    Write-Host "Период: последние $days дн."
    Write-Host "Ошибок: $($events.Count)"

    if ($events.Count -eq 0) {

        Write-Host ""
        Show-Success "Ошибок за указанный период не обнаружено."

        return
    }

    Show-EventLogSummary `
        -Events $events `
        -LogName $LogName `
        -Days $days

    Show-EventLogList `
        -Events $events

    Write-Host ""
    Write-Host "Для просмотра полного события используется номер из таблицы." `
        -ForegroundColor DarkGray

    Write-Host ""

    $details = Read-Host "Открыть подробности события? [Y/N]"

    if ($details.Trim().ToUpperInvariant() -eq 'Y') {

        Show-EventLogDetails `
            -Events $events
    }
}


function Show-CombinedEventLogs {

    Show-ToolkitHeader "ОШИБКИ ЖУРНАЛОВ: SYSTEM + APPLICATION"

    $days = Read-EventLogDays

    Write-Host ""
    Write-Host "Поиск ошибок за последние $days дн...." -ForegroundColor Cyan

    $systemEvents = @(
        Get-ToolkitEventLogErrors `
            -LogName 'System' `
            -Days $days
    )

    $applicationEvents = @(
        Get-ToolkitEventLogErrors `
            -LogName 'Application' `
            -Days $days
    )

    Write-Host ""
    Write-Host "РЕЗУЛЬТАТ" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    Write-Host "System:       $($systemEvents.Count)"
    Write-Host "Application:  $($applicationEvents.Count)"
    Write-Host "Всего:        $($systemEvents.Count + $applicationEvents.Count)"

    if (
        $systemEvents.Count -eq 0 -and
        $applicationEvents.Count -eq 0
    ) {

        Write-Host ""
        Show-Success "Ошибок за указанный период не обнаружено."

        return
    }

    if ($systemEvents.Count -gt 0) {

        Show-EventLogSummary `
            -Events $systemEvents `
            -LogName 'System' `
            -Days $days
    }

    if ($applicationEvents.Count -gt 0) {

        Show-EventLogSummary `
            -Events $applicationEvents `
            -LogName 'Application' `
            -Days $days
    }

    $allEvents = @(
        $systemEvents +
        $applicationEvents |
        Sort-Object TimeCreated -Descending
    )

    Show-EventLogList `
        -Events $allEvents

    Write-Host ""
    Write-Host "Для просмотра полного события используется номер из таблицы." `
        -ForegroundColor DarkGray

    Write-Host ""

    $details = Read-Host "Открыть подробности события? [Y/N]"

    if ($details.Trim().ToUpperInvariant() -eq 'Y') {

        Show-EventLogDetails `
            -Events $allEvents
    }
}


function Start-EventLogsMenu {

    while ($true) {

        Show-ToolkitHeader "ЖУРНАЛЫ СОБЫТИЙ"

        Show-ToolkitMenuItem "1." "Ошибки журнала «Система»"
        Show-ToolkitMenuItem "2." "Ошибки журнала «Приложения»"
        Show-ToolkitMenuItem "3." "Ошибки «Система» + «Приложения»"

        Write-Host ""
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {
                Show-ToolkitEventLog -LogName 'System'
                Read-ToolkitKey
            }

            '2' {
                Show-ToolkitEventLog -LogName 'Application'
                Read-ToolkitKey
            }

            '3' {
                Show-CombinedEventLogs
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