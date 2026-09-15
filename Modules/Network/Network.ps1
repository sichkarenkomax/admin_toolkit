#Requires -Version 5.1

# ============================================================
# AdminToolkit - Network
# ============================================================


# ============================================================
# Вспомогательные функции
# ============================================================

function Get-ToolkitActiveAdapter {

    try {

        $adapters = @(
            Get-NetAdapter -ErrorAction Stop |
                Where-Object {
                    $_.Status -eq "Up" -and
                    $_.HardwareInterface -eq $true
                } |
                Sort-Object ifIndex
        )

        if ($adapters.Count -gt 0) {
            return $adapters[0]
        }
    }
    catch {
    }

    return $null
}


function Get-ToolkitNetworkConfiguration {

    try {

        return @(
            Get-NetIPConfiguration -ErrorAction Stop |
                Where-Object {
                    $_.NetAdapter.Status -eq "Up"
                }
        )
    }
    catch {

        return @()
    }
}


function Get-ToolkitIPv4 {

    param(
        [Parameter(Mandatory = $true)]
        $Configuration
    )

    $address = $Configuration.IPv4Address |
        Select-Object -First 1

    if ($address) {
        return $address.IPAddress
    }

    return "Н/Д"
}


function Get-ToolkitGateway {

    param(
        [Parameter(Mandatory = $true)]
        $Configuration
    )

    $gateway = $Configuration.IPv4DefaultGateway |
        Select-Object -First 1

    if ($gateway) {
        return $gateway.NextHop
    }

    return "Н/Д"
}


function Get-ToolkitDnsServers {

    param(
        [Parameter(Mandatory = $true)]
        $Configuration
    )

    $servers = @(
        $Configuration.DnsServer.ServerAddresses
    )

    if ($servers.Count -eq 0) {
        return "Н/Д"
    }

    return ($servers -join ", ")
}


function Test-ToolkitPing {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    try {

        $result = Test-Connection `
            -ComputerName $Target `
            -Count 1 `
            -ErrorAction Stop

        return [PSCustomObject]@{
            Target     = $Target
            Success    = $true
            Address    = $result.Address
            ResponseMs = $result.ResponseTime
            Error      = $null
        }
    }
    catch {

        return [PSCustomObject]@{
            Target     = $Target
            Success    = $false
            Address    = $null
            ResponseMs = $null
            Error      = $_.Exception.Message
        }
    }
}


function Read-ToolkitTarget {

    $target = Read-Host "Введите адрес или имя узла"

    if ([string]::IsNullOrWhiteSpace($target)) {
        return $null
    }

    return $target.Trim()
}


# ============================================================
# 1. Комплексная сетевая диагностика
# ============================================================

function Start-NetworkDiagnostics {

    Show-ToolkitHeader "СЕТЕВАЯ ДИАГНОСТИКА"

    Write-Host "Получение параметров сети..." -ForegroundColor DarkGray
    Write-Host ""

    $configuration = $null

    try {

        $configuration = Get-NetIPConfiguration -ErrorAction Stop |
            Where-Object {
                $_.NetAdapter.Status -eq "Up"
            } |
            Sort-Object InterfaceIndex |
            Select-Object -First 1
    }
    catch {

        Show-Error "Не удалось получить конфигурацию сети:`n$($_.Exception.Message)"
        return
    }

    if (-not $configuration) {

        Show-Error "Активное сетевое подключение не найдено."
        return
    }

    $adapter = $configuration.NetAdapter
    $ipv4 = Get-ToolkitIPv4 $configuration
    $gateway = Get-ToolkitGateway $configuration
    $dns = Get-ToolkitDnsServers $configuration

    Write-Host "АДАПТЕР" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    Write-Host "Имя:            $($adapter.Name)"
    Write-Host "Описание:       $($adapter.InterfaceDescription)"
    Write-Host "MAC:            $($adapter.MacAddress)"
    Write-Host "Скорость:       $($adapter.LinkSpeed)"
    Write-Host "IPv4:           $ipv4"
    Write-Host "Шлюз:           $gateway"
    Write-Host "DNS:            $dns"

    Write-Host ""

    Write-Host "ПРОВЕРКА ПОДКЛЮЧЕНИЯ" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    $gatewayResult = $null

    if ($gateway -ne "Н/Д") {

        Write-Host "Шлюз:           $gateway ..." -NoNewline

        $gatewayResult = Test-ToolkitPing $gateway

        if ($gatewayResult.Success) {

            Write-Host (
                " OK ({0} ms)" -f
                $gatewayResult.ResponseMs
            ) -ForegroundColor Green
        }
        else {

            Write-Host " ОШИБКА" -ForegroundColor Red
        }
    }
    else {

        Write-Host "Шлюз:           не указан" -ForegroundColor Yellow
    }

    Write-Host "DNS:            microsoft.com ..." -NoNewline

    $dnsResult = $null

    try {

        $dnsResult = Resolve-DnsName `
            -Name "microsoft.com" `
            -Type A `
            -ErrorAction Stop

        if ($dnsResult) {
            Write-Host " OK" -ForegroundColor Green
        }
        else {
            Write-Host " ОШИБКА" -ForegroundColor Red
        }
    }
    catch {

        Write-Host " ОШИБКА" -ForegroundColor Red
    }

    Write-Host "Интернет:       1.1.1.1 ..." -NoNewline

    $internetResult = Test-ToolkitPing "1.1.1.1"

    if ($internetResult.Success) {

        Write-Host (
            " OK ({0} ms)" -f
            $internetResult.ResponseMs
        ) -ForegroundColor Green
    }
    else {

        Write-Host " НЕДОСТУПЕН" -ForegroundColor Red
    }

    Write-Host ""

    $problems = @()

    if ($gateway -eq "Н/Д") {

        $problems += "не указан шлюз"
    }
    elseif ($gatewayResult -and -not $gatewayResult.Success) {

        $problems += "шлюз недоступен"
    }

    if (-not $dnsResult) {

        $problems += "DNS не отвечает"
    }

    if (-not $internetResult.Success) {

        $problems += "1.1.1.1 недоступен"
    }

    if ($problems.Count -eq 0) {

        Show-Success "Сетевая диагностика: ПРОБЛЕМ НЕ ОБНАРУЖЕНО."
    }
    else {

        Show-Warning (
            "Обнаружены проблемы: " +
            ($problems -join "; ")
        )
    }
}


# ============================================================
# 2. IP / DNS / шлюз
# ============================================================

function Show-NetworkConfiguration {

    Show-ToolkitHeader "IP / DNS / ШЛЮЗ"

    try {

        $configs = @(
            Get-NetIPConfiguration -ErrorAction Stop |
                Where-Object {
                    $_.NetAdapter.Status -eq "Up"
                }
        )

        if ($configs.Count -eq 0) {

            Show-Warning "Активные сетевые подключения не найдены."
            return
        }

        foreach ($config in $configs) {

            $adapter = $config.NetAdapter

            Write-Host "$($adapter.Name)" -ForegroundColor Cyan
            Write-Host "────────────────────────────────────────────────────────────"

            Write-Host "Описание:       $($adapter.InterfaceDescription)"
            Write-Host "Состояние:      $($adapter.Status)"
            Write-Host "MAC:            $($adapter.MacAddress)"
            Write-Host "Скорость:       $($adapter.LinkSpeed)"

            $ipv4 = @(
                $config.IPv4Address |
                    ForEach-Object {
                        $_.IPAddress
                    }
            )

            if ($ipv4.Count -gt 0) {

                Write-Host "IPv4:           $($ipv4 -join ', ')"
            }
            else {

                Write-Host "IPv4:           Н/Д"
            }

            $ipv6 = @(
                $config.IPv6Address |
                    ForEach-Object {
                        $_.IPAddress
                    }
            )

            if ($ipv6.Count -gt 0) {

                Write-Host "IPv6:           $($ipv6 -join ', ')"
            }
            else {

                Write-Host "IPv6:           Н/Д"
            }

            $gateway = Get-ToolkitGateway $config

            Write-Host "Шлюз:           $gateway"

            $dns = Get-ToolkitDnsServers $config

            Write-Host "DNS:            $dns"

            Write-Host ""
        }
    }
    catch {

        Show-Error "Не удалось получить сетевую конфигурацию:`n$($_.Exception.Message)"
    }
}


# ============================================================
# 3. Ping
# ============================================================

function Start-NetworkPing {

    Show-ToolkitHeader "PING"

    $target = Read-ToolkitTarget

    if (-not $target) {
        return
    }

    $countText = Read-Host "Количество запросов [по умолчанию 4]"

    [int]$count = 4

    if (-not [int]::TryParse($countText, [ref]$count)) {

        $count = 4
    }

    if ($count -lt 1) {

        $count = 4
    }

    if ($count -gt 100) {

        $count = 100
    }

    Write-Host ""
    Write-Host "Проверка $target..." -ForegroundColor Cyan
    Write-Host ""

    try {

        $results = @(
            Test-Connection `
                -ComputerName $target `
                -Count $count `
                -ErrorAction SilentlyContinue
        )

        $successCount = $results.Count
        $lostCount = $count - $successCount

        if ($successCount -gt 0) {

            $times = @(
                $results |
                    ForEach-Object {
                        [double]$_.ResponseTime
                    }
            )

            $min = ($times | Measure-Object -Minimum).Minimum
            $max = ($times | Measure-Object -Maximum).Maximum
            $avg = ($times | Measure-Object -Average).Average

            $address = $results[0].Address

            Write-Host "Адрес:          $address"
            Write-Host "Отправлено:     $count"
            Write-Host "Получено:       $successCount"
            Write-Host "Потеряно:       $lostCount"

            $loss = ($lostCount / $count) * 100

            Write-Host ("Потери:         {0:N0} %" -f $loss)
            Write-Host "Минимум:        $min ms"
            Write-Host "Максимум:       $max ms"
            Write-Host ("Среднее:        {0:N1} ms" -f $avg)
        }
        else {

            Write-Host "Ответов не получено." -ForegroundColor Red
            Write-Host "Отправлено:     $count"
            Write-Host "Потеряно:       $count"
            Write-Host "Потери:         100 %"
        }
    }
    catch {

        Show-Error "Ошибка Ping:`n$($_.Exception.Message)"
    }
}


# ============================================================
# 4. Tracert
# ============================================================

function Start-NetworkTrace {

    Show-ToolkitHeader "TRACERT"

    $target = Read-ToolkitTarget

    if (-not $target) {
        return
    }

    Write-Host ""
    Write-Host "Построение маршрута до $target..." -ForegroundColor Cyan
    Write-Host ""

    $oldOutputEncoding = [Console]::OutputEncoding
    $oldInputEncoding  = [Console]::InputEncoding

    try {

        # ----------------------------------------------------
        # tracert на Windows использует системную кодовую
        # страницу консоли. Для нашей PowerShell-сессии
        # принудительно устанавливаем UTF-8.
        # ----------------------------------------------------

        & "$env:SystemRoot\System32\chcp.com" 65001 > $null

        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        [Console]::InputEncoding  = New-Object System.Text.UTF8Encoding($false)

        # ВАЖНО:
        # stdout не перехватываем.
        # tracert выводится непосредственно в текущую консоль.
        & "$env:SystemRoot\System32\tracert.exe" -d $target
    }
    catch {

        Show-Error "Не удалось выполнить tracert:`n$($_.Exception.Message)"
    }
    finally {

        try {

            [Console]::OutputEncoding = $oldOutputEncoding
            [Console]::InputEncoding  = $oldInputEncoding
        }
        catch {
        }
    }
}


# ============================================================
# 5. Resolve-DnsName
# ============================================================

function Start-NetworkDnsResolve {

    Show-ToolkitHeader "DNS — RESOLVE-DNSNAME"

    $target = Read-ToolkitTarget

    if (-not $target) {
        return
    }

    Write-Host ""
    Write-Host "Тип записи:" -ForegroundColor Cyan
    Write-Host "1. A"
    Write-Host "2. AAAA"
    Write-Host "3. MX"
    Write-Host "4. NS"
    Write-Host "5. CNAME"
    Write-Host "6. TXT"
    Write-Host "7. Любая"

    $choice = Read-Host "Выберите тип"

    $type = switch ($choice) {

        "1" { "A" }
        "2" { "AAAA" }
        "3" { "MX" }
        "4" { "NS" }
        "5" { "CNAME" }
        "6" { "TXT" }
        "7" { "ANY" }
        default { "A" }
    }

    Write-Host ""

    try {

        $records = @(
            Resolve-DnsName `
                -Name $target `
                -Type $type `
                -ErrorAction Stop
        )

        if ($records.Count -eq 0) {

            Show-Warning "DNS-записи не найдены."
            return
        }

        $records |
            Select-Object Name,
                          Type,
                          TTL,
                          IPAddress,
                          NameHost,
                          MailExchange,
                          NameAdministrator |
            Format-Table -AutoSize
    }
    catch {

        Show-Error "Ошибка DNS-разрешения:`n$($_.Exception.Message)"
    }
}


# ============================================================
# 6. Test-NetConnection
# ============================================================

function Start-NetworkTestConnection {

    Show-ToolkitHeader "TEST-NETCONNECTION"

    $target = Read-ToolkitTarget

    if (-not $target) {
        return
    }

    $portText = Read-Host "Порт (Enter — только общая проверка)"

    Write-Host ""

    try {

        if ([string]::IsNullOrWhiteSpace($portText)) {

            $result = Test-NetConnection `
                -ComputerName $target `
                -InformationLevel Detailed `
                -WarningAction SilentlyContinue

            $result |
                Select-Object ComputerName,
                              RemoteAddress,
                              InterfaceAlias,
                              SourceAddress,
                              PingSucceeded,
                              PingReplyDetails |
                Format-List
        }
        else {

            [int]$port = 0

            if (-not [int]::TryParse($portText, [ref]$port)) {

                Show-Error "Некорректный номер порта."
                return
            }

            if ($port -lt 1 -or $port -gt 65535) {

                Show-Error "Порт должен быть от 1 до 65535."
                return
            }

            $result = Test-NetConnection `
                -ComputerName $target `
                -Port $port `
                -InformationLevel Detailed `
                -WarningAction SilentlyContinue

            Write-Host "Узел:           $($result.ComputerName)"
            Write-Host "Адрес:          $($result.RemoteAddress)"
            Write-Host "Исходный IP:    $($result.SourceAddress)"
            Write-Host "Интерфейс:      $($result.InterfaceAlias)"
            Write-Host "Ping:           $($result.PingSucceeded)"
            Write-Host "Порт:           $port"
            Write-Host "TCP:            $($result.TcpTestSucceeded)"

            Write-Host ""

            if ($result.TcpTestSucceeded) {

                Show-Success "TCP-порт $port доступен."
            }
            else {

                Show-Warning "TCP-порт $port недоступен."
            }
        }
    }
    catch {

        Show-Error "Ошибка Test-NetConnection:`n$($_.Exception.Message)"
    }
}


# ============================================================
# 7. Очистить DNS
# ============================================================

function Clear-NetworkDnsCache {

    Show-ToolkitHeader "ОЧИСТКА DNS-КЭША"

    Write-Host "Текущий DNS-кэш будет очищен." -ForegroundColor Yellow

    if (-not (
        Confirm-ToolkitAction "Очистить DNS-кэш?"
    )) {
        return
    }

    try {

        Clear-DnsClientCache -ErrorAction Stop

        Show-Success "DNS-кэш успешно очищен."
    }
    catch {

        try {

            & "$env:SystemRoot\System32\ipconfig.exe" /flushdns

            if ($LASTEXITCODE -eq 0) {

                Show-Success "DNS-кэш успешно очищен."
            }
            else {

                throw "ipconfig завершился с кодом $LASTEXITCODE."
            }
        }
        catch {

            Show-Error "Не удалось очистить DNS-кэш:`n$($_.Exception.Message)"
        }
    }
}


# ============================================================
# 8. Сброс сети
# ============================================================

function Reset-NetworkStack {

    Show-ToolkitHeader "СБРОС СЕТИ"

    Write-Host "ВНИМАНИЕ!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Будут выполнены:"
    Write-Host "  • очистка DNS-кэша"
    Write-Host "  • сброс Winsock"
    Write-Host "  • сброс TCP/IP"
    Write-Host ""
    Write-Host "После операции может потребоваться перезагрузка."
    Write-Host ""

    if (-not (
        Confirm-ToolkitAction "Выполнить полный сброс сетевого стека?"
    )) {
        return
    }

    Write-Host ""

    try {

        Write-Host "Очистка DNS..." -ForegroundColor Cyan

        try {

            Clear-DnsClientCache -ErrorAction Stop
        }
        catch {

            & "$env:SystemRoot\System32\ipconfig.exe" /flushdns |
                Out-Null
        }

        Write-Host "Сброс Winsock..." -ForegroundColor Cyan

        & "$env:SystemRoot\System32\netsh.exe" winsock reset

        if ($LASTEXITCODE -ne 0) {

            throw "Ошибка netsh winsock reset."
        }

        Write-Host "Сброс TCP/IP..." -ForegroundColor Cyan

        & "$env:SystemRoot\System32\netsh.exe" int ip reset

        if ($LASTEXITCODE -ne 0) {

            throw "Ошибка netsh int ip reset."
        }

        Write-Host ""

        Show-Success "Сетевой стек сброшен."

        Show-Warning "Рекомендуется перезагрузить компьютер."
    }
    catch {

        Show-Error "Не удалось выполнить сброс сети:`n$($_.Exception.Message)"
    }
}


# ============================================================
# 9. Wi-Fi
# ============================================================

function Show-WifiInformation {

    Show-ToolkitHeader "WI-FI"

    try {

        $output = & "$env:SystemRoot\System32\netsh.exe" wlan show interfaces 2>&1

        if ($LASTEXITCODE -ne 0) {

            Show-Warning "Wi-Fi-интерфейс не найден или недоступен."
            return
        }

        Write-Host ""

        foreach ($line in $output) {

            $text = [string]$line

            if (
                $text -match "^\s*Name\s*:" -or
                $text -match "^\s*Description\s*:" -or
                $text -match "^\s*GUID\s*:" -or
                $text -match "^\s*Physical address\s*:" -or
                $text -match "^\s*State\s*:" -or
                $text -match "^\s*SSID\s*:" -or
                $text -match "^\s*BSSID\s*:" -or
                $text -match "^\s*Network type\s*:" -or
                $text -match "^\s*Radio type\s*:" -or
                $text -match "^\s*Authentication\s*:" -or
                $text -match "^\s*Channel\s*:" -or
                $text -match "^\s*Signal\s*:" -or
                $text -match "^\s*Receive rate" -or
                $text -match "^\s*Transmit rate" -or
                $text -match "^\s*Имя\s*:" -or
                $text -match "^\s*Описание\s*:" -or
                $text -match "^\s*Состояние\s*:" -or
                $text -match "^\s*Сигнал\s*:"
            ) {

                Write-Host $text
            }
        }
    }
    catch {

        Show-Error "Не удалось получить информацию Wi-Fi:`n$($_.Exception.Message)"
    }
}


# ============================================================
# 10. Сохранённые Wi-Fi профили
# ============================================================

function Show-SavedWifiProfiles {

    Show-ToolkitHeader "СОХРАНЁННЫЕ WI-FI ПРОФИЛИ"

    try {

        $output = & "$env:SystemRoot\System32\netsh.exe" wlan show profiles 2>&1

        if ($LASTEXITCODE -ne 0) {

            Show-Warning "Не удалось получить список Wi-Fi профилей."
            return
        }

        $profiles = @()

        foreach ($line in $output) {

            $text = [string]$line

            if ($text -match ":\s*(.+)$") {

                $name = $matches[1].Trim()

                if (
                    $text -match "All User Profile" -or
                    $text -match "Профиль всех пользователей" -or
                    $text -match "Профиль пользователей"
                ) {

                    if ($name) {

                        $profiles += $name
                    }
                }
            }
        }

        $profiles = @(
            $profiles |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                } |
                Sort-Object -Unique
        )

        if ($profiles.Count -eq 0) {

            Show-Info "Сохранённые Wi-Fi профили не найдены."
            return
        }

        Write-Host (
            "Найдено профилей: {0}" -f
            $profiles.Count
        ) -ForegroundColor Cyan

        Write-Host ""

        for ($i = 0; $i -lt $profiles.Count; $i++) {

            Write-Host (
                "{0}. {1}" -f
                ($i + 1),
                $profiles[$i]
            )
        }

        Write-Host ""
        Show-Info "Пароли Wi-Fi намеренно не выводятся."
    }
    catch {

        Show-Error "Не удалось получить Wi-Fi профили:`n$($_.Exception.Message)"
    }
}


# ============================================================
# 11. Проверка портов
# ============================================================

function Start-NetworkPortCheck {

    Show-ToolkitHeader "ПРОВЕРКА ПОРТОВ"

    $target = Read-Host "Адрес узла"

    if ([string]::IsNullOrWhiteSpace($target)) {
        return
    }

    $portsText = Read-Host `
        "Порты через запятую (например: 80,443,3389)"

    if ([string]::IsNullOrWhiteSpace($portsText)) {

        Show-Error "Порты не указаны."
        return
    }

    $ports = @()

    foreach ($part in $portsText -split ',') {

        [int]$port = 0

        if (
            [int]::TryParse(
                $part.Trim(),
                [ref]$port
            )
        ) {

            if ($port -ge 1 -and $port -le 65535) {

                $ports += $port
            }
        }
    }

    $ports = @(
        $ports |
            Sort-Object -Unique
    )

    if ($ports.Count -eq 0) {

        Show-Error "Не найдено корректных портов."
        return
    }

    Write-Host ""
    Write-Host "Проверка $target..." -ForegroundColor Cyan
    Write-Host ""

    $rows = @()

    foreach ($port in $ports) {

        Write-Host (
            "Порт {0,-5} " -f $port
        ) -NoNewline

        try {

            $result = Test-NetConnection `
                -ComputerName $target `
                -Port $port `
                -InformationLevel Quiet `
                -WarningAction SilentlyContinue

            if ($result) {

                Write-Host "OPEN" -ForegroundColor Green

                $status = "OPEN"
            }
            else {

                Write-Host "CLOSED" -ForegroundColor Red

                $status = "CLOSED"
            }

            $rows += [PSCustomObject]@{
                Порт   = $port
                Статус = $status
            }
        }
        catch {

            Write-Host "ERROR" -ForegroundColor Red

            $rows += [PSCustomObject]@{
                Порт   = $port
                Статус = "ERROR"
            }
        }
    }

    Write-Host ""

    $openCount = @(
        $rows |
            Where-Object {
                $_.Статус -eq "OPEN"
            }
    ).Count

    $closedCount = @(
        $rows |
            Where-Object {
                $_.Статус -eq "CLOSED"
            }
    ).Count

    Write-Host "Открыто:        $openCount"
    Write-Host "Закрыто:        $closedCount"
}


# ============================================================
# Главное меню сети
# ============================================================

function Start-NetworkMenu {

    while ($true) {

        Show-ToolkitHeader "СЕТЬ"

        Show-ToolkitMenuItem "1."  "Сетевая диагностика"
        Show-ToolkitMenuItem "2."  "IP / DNS / шлюз"
        Show-ToolkitMenuItem "3."  "Ping"
        Show-ToolkitMenuItem "4."  "Tracert"
        Show-ToolkitMenuItem "5."  "Resolve-DnsName"
        Show-ToolkitMenuItem "6."  "Test-NetConnection"
        Show-ToolkitMenuItem "7."  "Очистить DNS"
        Show-ToolkitMenuItem "8."  "Сбросить сеть"
        Show-ToolkitMenuItem "9."  "Показать Wi-Fi"
        Show-ToolkitMenuItem "10." "Сохранённые Wi-Fi профили"
        Show-ToolkitMenuItem "11." "Проверка портов"

        Write-Host ""
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {
                Start-NetworkDiagnostics
                Read-ToolkitKey
            }

            '2' {
                Show-NetworkConfiguration
                Read-ToolkitKey
            }

            '3' {
                Start-NetworkPing
                Read-ToolkitKey
            }

            '4' {
                Start-NetworkTrace
                Read-ToolkitKey
            }

            '5' {
                Start-NetworkDnsResolve
                Read-ToolkitKey
            }

            '6' {
                Start-NetworkTestConnection
                Read-ToolkitKey
            }

            '7' {
                Clear-NetworkDnsCache
                Read-ToolkitKey
            }

            '8' {
                Reset-NetworkStack
                Read-ToolkitKey
            }

            '9' {
                Show-WifiInformation
                Read-ToolkitKey
            }

            '10' {
                Show-SavedWifiProfiles
                Read-ToolkitKey
            }

            '11' {
                Start-NetworkPortCheck
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