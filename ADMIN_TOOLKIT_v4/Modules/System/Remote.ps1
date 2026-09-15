#Requires -Version 5.1

# ============================================================
# REMOTE MANAGEMENT
# ============================================================

$Script:RemoteComputer = $null


# ============================================================
# ВЫБОР УДАЛЁННОГО КОМПЬЮТЕРА
# ============================================================

function Read-RemoteComputer {

    $computer = Read-Host "Введите имя компьютера или IP-адрес"

    if ([string]::IsNullOrWhiteSpace($computer)) {
        Show-Warning "Компьютер не указан."
        return $false
    }

    $Script:RemoteComputer = $computer.Trim()

    return $true
}


# ============================================================
# ПРОВЕРКА TCP-ПОРТА
# ============================================================

function Test-RemotePort {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [int]$Port,

        [int]$Timeout = 2000
    )

    try {
        $client = New-Object System.Net.Sockets.TcpClient

        $async = $client.BeginConnect(
            $ComputerName,
            $Port,
            $null,
            $null
        )

        $success = $async.AsyncWaitHandle.WaitOne($Timeout)

        if ($success -and $client.Connected) {
            $client.EndConnect($async)
            $client.Close()
            return $true
        }

        $client.Close()
        return $false
    }
    catch {
        return $false
    }
}


# ============================================================
# RPC / WMI
# ============================================================

function Test-RemoteRpc {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )

    try {
        $null = Get-CimInstance `
            -ClassName Win32_OperatingSystem `
            -ComputerName $ComputerName `
            -ErrorAction Stop `
            -OperationTimeoutSec 5

        return $true
    }
    catch {
        return $false
    }
}


# ============================================================
# ДИАГНОСТИКА КОМПЬЮТЕРА
# ============================================================

function Start-RemoteDiagnostics {

    Show-ToolkitHeader "ДИАГНОСТИКА УДАЛЁННОГО КОМПЬЮТЕРА"

    $computer = $Script:RemoteComputer

    if ([string]::IsNullOrWhiteSpace($computer)) {
        Show-Error "Удалённый компьютер не выбран."
        return
    }

    Write-Host "Компьютер: " -NoNewline
    Write-Host $computer -ForegroundColor Cyan
    Write-Host ""

    # --------------------------------------------------------
    # DNS
    # --------------------------------------------------------

    Write-Host "DNS:       " -NoNewline

    $dnsOk = $false

    try {
        $dnsResult = Resolve-DnsName `
            -Name $computer `
            -ErrorAction Stop `
            | Where-Object {
                $_.Type -in @('A', 'AAAA')
            }

        if ($dnsResult) {
            $dnsOk = $true
            Write-Host "OK" -ForegroundColor Green
        }
        else {
            Write-Host "не найден" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "ошибка" -ForegroundColor Red
    }


    # --------------------------------------------------------
    # PING
    # --------------------------------------------------------

    Write-Host "Ping:      " -NoNewline

    $pingOk = $false

    try {
        $pingOk = Test-Connection `
            -ComputerName $computer `
            -Count 2 `
            -Quiet `
            -ErrorAction SilentlyContinue

        if ($pingOk) {
            Write-Host "OK" -ForegroundColor Green
        }
        else {
            Write-Host "нет ответа" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "ошибка" -ForegroundColor Red
    }


    # --------------------------------------------------------
    # SMB
    # --------------------------------------------------------

    Write-Host "SMB 445:   " -NoNewline

    $smbOk = Test-RemotePort `
        -ComputerName $computer `
        -Port 445

    if ($smbOk) {
        Write-Host "открыт" -ForegroundColor Green
    }
    else {
        Write-Host "недоступен" -ForegroundColor Yellow
    }


    # --------------------------------------------------------
    # WinRM
    # --------------------------------------------------------

    Write-Host "WinRM 5985:" -NoNewline

    $winrmOk = Test-RemotePort `
        -ComputerName $computer `
        -Port 5985

    if ($winrmOk) {
        Write-Host " открыт" -ForegroundColor Green
    }
    else {
        Write-Host " недоступен" -ForegroundColor Yellow
    }


    # --------------------------------------------------------
    # RPC / WMI
    # --------------------------------------------------------

    Write-Host "RPC / WMI: " -NoNewline

    $rpcOk = Test-RemoteRpc `
        -ComputerName $computer

    if ($rpcOk) {
        Write-Host "OK" -ForegroundColor Green
    }
    else {
        Write-Host "недоступен" -ForegroundColor Yellow
    }


    # --------------------------------------------------------
    # ИТОГ
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "ИТОГ" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    if ($rpcOk) {
        Show-Success "RPC/WMI доступен — удалённое администрирование через CIM возможно."
    }
    elseif ($winrmOk) {
        Show-Success "WinRM доступен — PowerShell Remoting может использоваться."
    }
    elseif ($pingOk) {
        Show-Warning "Компьютер доступен по сети, но удалённые службы администрирования недоступны."
    }
    else {
        Show-Error "Компьютер недоступен."
    }
}


# ============================================================
# СИСТЕМНАЯ ИНФОРМАЦИЯ
# ============================================================

function Show-RemoteSystemInfo {

    Show-ToolkitHeader "СИСТЕМНАЯ ИНФОРМАЦИЯ"

    $computer = $Script:RemoteComputer

    if ([string]::IsNullOrWhiteSpace($computer)) {
        Show-Error "Удалённый компьютер не выбран."
        return
    }

    try {

        Write-Host "Получение информации..." -ForegroundColor Cyan
        Write-Host ""

        $os = Get-CimInstance `
            -ClassName Win32_OperatingSystem `
            -ComputerName $computer `
            -ErrorAction Stop

        $cs = Get-CimInstance `
            -ClassName Win32_ComputerSystem `
            -ComputerName $computer `
            -ErrorAction Stop

        $bios = Get-CimInstance `
            -ClassName Win32_BIOS `
            -ComputerName $computer `
            -ErrorAction Stop

        $cpu = Get-CimInstance `
            -ClassName Win32_Processor `
            -ComputerName $computer `
            -ErrorAction Stop |
            Select-Object -First 1

        $network = Get-CimInstance `
            -ClassName Win32_NetworkAdapterConfiguration `
            -ComputerName $computer `
            -Filter "IPEnabled = TRUE" `
            -ErrorAction SilentlyContinue

        Write-Host "КОМПЬЮТЕР" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"

        Write-Host ("Имя:              {0}" -f $cs.Name)
        Write-Host ("Пользователь:     {0}" -f $cs.UserName)
        Write-Host ("Производитель:    {0}" -f $cs.Manufacturer)
        Write-Host ("Модель:           {0}" -f $cs.Model)

        Write-Host ""

        Write-Host "WINDOWS" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"

        Write-Host ("ОС:               {0}" -f $os.Caption)
        Write-Host ("Версия:           {0}" -f $os.Version)
        Write-Host ("Сборка:           {0}" -f $os.BuildNumber)

        Write-Host ""

        Write-Host "BIOS" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"

        Write-Host ("Производитель:    {0}" -f $bios.Manufacturer)
        Write-Host ("Версия:           {0}" -f $bios.SMBIOSBIOSVersion)
        Write-Host ("Дата:             {0}" -f $bios.ReleaseDate)

        Write-Host ""

        Write-Host "ПРОЦЕССОР" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"

        Write-Host ("CPU:              {0}" -f $cpu.Name)
        Write-Host ("Ядер:             {0}" -f $cpu.NumberOfCores)
        Write-Host ("Логических:       {0}" -f $cpu.NumberOfLogicalProcessors)

        Write-Host ""

        Write-Host "ПАМЯТЬ" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"

        $ramGB = [math]::Round(
            $cs.TotalPhysicalMemory / 1GB,
            1
        )

        Write-Host ("ОЗУ:              {0} GB" -f $ramGB)

        Write-Host ""

        Write-Host "СЕТЬ" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"

        foreach ($adapter in $network) {

            if ($adapter.IPAddress) {

                foreach ($ip in $adapter.IPAddress) {

                    if ($ip -notmatch ':') {
                        Write-Host ("IPv4:             {0}" -f $ip)
                    }
                }
            }
        }

        Write-Host ""

        $bootTime = $os.LastBootUpTime
        $uptime = (Get-Date) - $bootTime

        Write-Host "ЗАГРУЗКА" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"

        Write-Host ("Последняя загрузка: {0}" -f $bootTime)
        Write-Host (
            "Время работы:       {0} д. {1} ч. {2} мин." -f `
            [int]$uptime.TotalDays,
            $uptime.Hours,
            $uptime.Minutes
        )
    }
    catch {
        Show-Error "Не удалось получить информацию: $($_.Exception.Message)"
    }
}


# ============================================================
# ПОЛЬЗОВАТЕЛИ
# ============================================================

function Show-RemoteUsers {

    Show-ToolkitHeader "ПОЛЬЗОВАТЕЛИ УДАЛЁННОГО КОМПЬЮТЕРА"

    $computer = $Script:RemoteComputer

    if ([string]::IsNullOrWhiteSpace($computer)) {
        Show-Error "Удалённый компьютер не выбран."
        return
    }

    try {

        $users = @(
            Get-CimInstance `
                -ClassName Win32_UserAccount `
                -ComputerName $computer `
                -Filter "LocalAccount = TRUE" `
                -ErrorAction Stop |
            Sort-Object Name
        )

        if ($users.Count -eq 0) {
            Show-Warning "Локальные пользователи не найдены."
            return
        }

        $users |
            Select-Object `
                Name,
                @{
                    Name = "Состояние"
                    Expression = {
                        if ($_.Disabled) {
                            "Отключен"
                        }
                        else {
                            "Активен"
                        }
                    }
                },
                @{
                    Name = "Пароль обязателен"
                    Expression = {
                        if ($_.PasswordRequired) {
                            "Да"
                        }
                        else {
                            "Нет"
                        }
                    }
                } |
            Format-Table -AutoSize
    }
    catch {
        Show-Error "Не удалось получить список пользователей: $($_.Exception.Message)"
    }
}


# ============================================================
# УДАЛЁННЫЕ СЛУЖБЫ
# ============================================================

$Script:RemoteServices = @(
    @{ Name="RpcSs";             DisplayName="RPC" },
    @{ Name="EventLog";          DisplayName="Журнал событий" },
    @{ Name="Winmgmt";           DisplayName="WMI" },
    @{ Name="Dhcp";              DisplayName="DHCP Client" },
    @{ Name="Dnscache";          DisplayName="DNS Client" },
    @{ Name="LanmanWorkstation"; DisplayName="Рабочая станция" },
    @{ Name="LanmanServer";      DisplayName="Сервер" },
    @{ Name="BITS";              DisplayName="BITS" },
    @{ Name="wuauserv";          DisplayName="Windows Update" },
    @{ Name="Spooler";           DisplayName="Диспетчер печати" },
    @{ Name="WinDefend";         DisplayName="Microsoft Defender" },
    @{ Name="MpsSvc";            DisplayName="Брандмауэр Windows" },
    @{ Name="CryptSvc";          DisplayName="Cryptographic Services" },
    @{ Name="TrustedInstaller";  DisplayName="Windows Modules Installer" }
)


function Get-RemoteServices {

    $computer = $Script:RemoteComputer

    try {

        $names = $Script:RemoteServices.Name

        $filter = ($names | ForEach-Object {
            "Name='$_'"
        }) -join " OR "

        return @(
            Get-CimInstance `
                -ClassName Win32_Service `
                -ComputerName $computer `
                -Filter $filter `
                -ErrorAction Stop |
            Sort-Object Name
        )
    }
    catch {
        throw
    }
}


function Get-RemoteServiceStateName {
    param([string]$State)

    switch ($State) {
        'Running' { return 'Запущена' }
        'Stopped' { return 'Остановлена' }
        'Start Pending' { return 'Запускается' }
        'Stop Pending' { return 'Останавливается' }
        default { return $State }
    }
}


function Get-RemoteServiceStartModeName {
    param([string]$StartMode)

    switch ($StartMode) {
        'Auto'     { return 'Авто' }
        'Manual'   { return 'Вручную' }
        'Disabled' { return 'Отключена' }
        default    { return $StartMode }
    }
}


function Manage-RemoteService {

    param(
        [Parameter(Mandatory)]
        $Service
    )

    while ($true) {

        Show-ToolkitHeader "УПРАВЛЕНИЕ УДАЛЁННОЙ СЛУЖБОЙ"

        Write-Host "Компьютер: " -NoNewline
        Write-Host $Script:RemoteComputer -ForegroundColor Cyan

        Write-Host ""
        Write-Host "Служба:     " -NoNewline
        Write-Host $Service.DisplayName -ForegroundColor Cyan

        Write-Host ""
        Write-Host ("Состояние:  {0}" -f (
            Get-RemoteServiceStateName $Service.State
        ))

        Write-Host ("Запуск:     {0}" -f (
            Get-RemoteServiceStartModeName $Service.StartMode
        ))

        Write-Host ""

        Show-ToolkitMenuItem "1." "Запустить"
        Show-ToolkitMenuItem "2." "Остановить"
        Show-ToolkitMenuItem "3." "Перезапустить"
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {
                try {
                    $result = Invoke-CimMethod `
                        -InputObject $Service `
                        -MethodName StartService `
                        -ErrorAction Stop

                    if ($result.ReturnValue -eq 0) {
                        Show-Success "Команда запуска отправлена."
                    }
                    else {
                        Show-Warning "Код результата: $($result.ReturnValue)"
                    }
                }
                catch {
                    Show-Error "Не удалось запустить службу: $($_.Exception.Message)"
                }

                Read-ToolkitKey
            }

            '2' {
                try {
                    $result = Invoke-CimMethod `
                        -InputObject $Service `
                        -MethodName StopService `
                        -ErrorAction Stop

                    if ($result.ReturnValue -eq 0) {
                        Show-Success "Команда остановки отправлена."
                    }
                    else {
                        Show-Warning "Код результата: $($result.ReturnValue)"
                    }
                }
                catch {
                    Show-Error "Не удалось остановить службу: $($_.Exception.Message)"
                }

                Read-ToolkitKey
            }

            '3' {
                try {

                    $stopResult = Invoke-CimMethod `
                        -InputObject $Service `
                        -MethodName StopService `
                        -ErrorAction Stop

                    if ($stopResult.ReturnValue -ne 0) {
                        Show-Warning "Остановка вернула код: $($stopResult.ReturnValue)"
                    }

                    Start-Sleep -Seconds 2

                    $startResult = Invoke-CimMethod `
                        -InputObject $Service `
                        -MethodName StartService `
                        -ErrorAction Stop

                    if ($startResult.ReturnValue -eq 0) {
                        Show-Success "Команда перезапуска отправлена."
                    }
                    else {
                        Show-Warning "Запуск вернул код: $($startResult.ReturnValue)"
                    }
                }
                catch {
                    Show-Error "Не удалось перезапустить службу: $($_.Exception.Message)"
                }

                Read-ToolkitKey
            }

            'R' {
                try {
                    $newService = Get-CimInstance `
                        -ClassName Win32_Service `
                        -ComputerName $Script:RemoteComputer `
                        -Filter "Name='$($Service.Name)'" `
                        -ErrorAction Stop

                    $Service = $newService
                }
                catch {
                    Show-Error "Не удалось обновить состояние службы."
                    Read-ToolkitKey
                }
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


function Start-RemoteServices {

    while ($true) {

        Show-ToolkitHeader "СЛУЖБЫ УДАЛЁННОГО КОМПЬЮТЕРА"

        try {
            $services = @(Get-RemoteServices)
        }
        catch {
            Show-Error "Не удалось получить службы: $($_.Exception.Message)"
            Read-ToolkitKey
            return
        }

        if ($services.Count -eq 0) {
            Show-Warning "Службы не найдены."
            Read-ToolkitKey
            return
        }

        Write-Host "Компьютер: " -NoNewline
        Write-Host $Script:RemoteComputer -ForegroundColor Cyan

        Write-Host ""

        for ($i = 0; $i -lt $services.Count; $i++) {

            $service = $services[$i]

            $state = Get-RemoteServiceStateName $service.State
            $start = Get-RemoteServiceStartModeName $service.StartMode

            $color = if ($service.State -eq 'Running') {
                'Green'
            }
            elseif (
                $service.StartMode -eq 'Auto' -and
                $service.State -eq 'Stopped'
            ) {
                'Yellow'
            }
            else {
                'Gray'
            }

            Write-Host (
                "  {0,2}. {1,-30} {2,-15} {3}" -f `
                ($i + 1),
                $service.DisplayName,
                $state,
                $start
            ) -ForegroundColor $color
        }

        Write-Host ""
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        if ($choice.ToUpperInvariant() -eq '0') {
            return
        }

        if ($choice.ToUpperInvariant() -eq 'R') {
            continue
        }

        $number = 0

        if (
            [int]::TryParse(
                $choice,
                [ref]$number
            ) -and
            $number -ge 1 -and
            $number -le $services.Count
        ) {

            Manage-RemoteService $services[$number - 1]
        }
        else {
            Show-Error "Неверный номер службы."
            Start-Sleep -Milliseconds 800
        }
    }
}


# ============================================================
# ОТПРАВИТЬ СООБЩЕНИЕ
# ============================================================

function Send-RemoteMessage {

    Show-ToolkitHeader "ОТПРАВКА СООБЩЕНИЯ"

    $computer = $Script:RemoteComputer

    if ([string]::IsNullOrWhiteSpace($computer)) {
        Show-Error "Удалённый компьютер не выбран."
        return
    }

    Write-Host "Компьютер: " -NoNewline
    Write-Host $computer -ForegroundColor Cyan

    Write-Host ""

    $message = Read-Host "Введите сообщение"

    if ([string]::IsNullOrWhiteSpace($message)) {
        Show-Warning "Сообщение не указано."
        return
    }

    try {

        & "$env:SystemRoot\System32\msg.exe" `
            * `
            "/SERVER:$computer" `
            $message

        if ($LASTEXITCODE -eq 0) {
            Show-Success "Сообщение отправлено."
        }
        else {
            Show-Error "Не удалось отправить сообщение. Код: $LASTEXITCODE"
        }
    }
    catch {
        Show-Error "Ошибка отправки сообщения: $($_.Exception.Message)"
    }
}


# ============================================================
# ПЕРЕЗАГРУЗКА
# ============================================================

function Restart-RemoteComputer {

    Show-ToolkitHeader "ПЕРЕЗАГРУЗКА КОМПЬЮТЕРА"

    $computer = $Script:RemoteComputer

    if ([string]::IsNullOrWhiteSpace($computer)) {
        Show-Error "Удалённый компьютер не выбран."
        return
    }

    Write-Host "Компьютер: " -NoNewline
    Write-Host $computer -ForegroundColor Cyan

    if (-not (Confirm-ToolkitAction "Компьютер будет немедленно перезагружен.")) {
        Show-Info "Операция отменена."
        return
    }

    try {

        Restart-Computer `
            -ComputerName $computer `
            -Force `
            -ErrorAction Stop

        Show-Success "Команда перезагрузки отправлена."
    }
    catch {
        Show-Error "Не удалось перезагрузить компьютер: $($_.Exception.Message)"
    }
}


# ============================================================
# ВЫКЛЮЧЕНИЕ
# ============================================================

function Stop-RemoteComputer {

    Show-ToolkitHeader "ВЫКЛЮЧЕНИЕ КОМПЬЮТЕРА"

    $computer = $Script:RemoteComputer

    if ([string]::IsNullOrWhiteSpace($computer)) {
        Show-Error "Удалённый компьютер не выбран."
        return
    }

    Write-Host "Компьютер: " -NoNewline
    Write-Host $computer -ForegroundColor Cyan

    if (-not (Confirm-ToolkitAction "Компьютер будет немедленно выключен.")) {
        Show-Info "Операция отменена."
        return
    }

    try {

        Stop-Computer `
            -ComputerName $computer `
            -Force `
            -ErrorAction Stop

        Show-Success "Команда выключения отправлена."
    }
    catch {
        Show-Error "Не удалось выключить компьютер: $($_.Exception.Message)"
    }
}


# ============================================================
# WINRM
# ============================================================

function Test-RemoteWinRM {

    Show-ToolkitHeader "ПРОВЕРКА WINRM"

    $computer = $Script:RemoteComputer

    if ([string]::IsNullOrWhiteSpace($computer)) {
        Show-Error "Удалённый компьютер не выбран."
        return
    }

    Write-Host "Компьютер: " -NoNewline
    Write-Host $computer -ForegroundColor Cyan

    Write-Host ""

    Write-Host "TCP 5985: " -NoNewline

    if (Test-RemotePort `
        -ComputerName $computer `
        -Port 5985) {

        Write-Host "открыт" -ForegroundColor Green
    }
    else {
        Write-Host "недоступен" -ForegroundColor Red
    }

    Write-Host "WinRM:     " -NoNewline

    try {

        $null = Test-WSMan `
            -ComputerName $computer `
            -ErrorAction Stop

        Write-Host "работает" -ForegroundColor Green

        Write-Host ""
        Show-Success "WinRM доступен."
    }
    catch {
        Write-Host "недоступен" -ForegroundColor Red

        Write-Host ""
        Show-Warning "WinRM не отвечает: $($_.Exception.Message)"
    }
}


# ============================================================
# POWERSHELL REMOTING
# ============================================================

function Start-RemotePowerShell {

    Show-ToolkitHeader "POWERSHELL REMOTING"

    $computer = $Script:RemoteComputer

    if ([string]::IsNullOrWhiteSpace($computer)) {
        Show-Error "Удалённый компьютер не выбран."
        return
    }

    Write-Host "Компьютер: " -NoNewline
    Write-Host $computer -ForegroundColor Cyan

    Write-Host ""

    try {

        $null = Test-WSMan `
            -ComputerName $computer `
            -ErrorAction Stop
    }
    catch {
        Show-Error "WinRM недоступен: $($_.Exception.Message)"
        return
    }

    Show-ToolkitMenuItem "1." "Выполнить команду"
    Show-ToolkitMenuItem "2." "Интерактивная PowerShell-сессия"
    Show-ToolkitMenuItem "0" "Назад"

    $choice = Read-ToolkitChoice

    switch ($choice.ToUpperInvariant()) {

        '1' {

            $command = Read-Host "Введите PowerShell-команду"

            if ([string]::IsNullOrWhiteSpace($command)) {
                Show-Warning "Команда не указана."
                return
            }

            Write-Host ""

            try {

                Invoke-Command `
                    -ComputerName $computer `
                    -ScriptBlock (
                        [scriptblock]::Create($command)
                    ) `
                    -ErrorAction Stop |
                    Out-Host
            }
            catch {
                Show-Error "Ошибка выполнения команды: $($_.Exception.Message)"
            }

            Read-ToolkitKey
        }

        '2' {

            Write-Host ""
            Write-Host "Для выхода из удалённой сессии выполните:" -ForegroundColor Yellow
            Write-Host "Exit-PSSession" -ForegroundColor Cyan
            Write-Host ""

            try {

                Enter-PSSession `
                    -ComputerName $computer `
                    -ErrorAction Stop
            }
            catch {
                Show-Error "Не удалось подключиться: $($_.Exception.Message)"
                Read-ToolkitKey
            }
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


# ============================================================
# ПРОЦЕССЫ
# ============================================================

function Start-RemoteProcesses {

    while ($true) {

        Show-ToolkitHeader "ПРОЦЕССЫ УДАЛЁННОГО КОМПЬЮТЕРА"

        $computer = $Script:RemoteComputer

        if ([string]::IsNullOrWhiteSpace($computer)) {
            Show-Error "Удалённый компьютер не выбран."
            return
        }

        Write-Host "Компьютер: " -NoNewline
        Write-Host $computer -ForegroundColor Cyan

        Write-Host ""

        Show-ToolkitMenuItem "1." "Список процессов"
        Show-ToolkitMenuItem "2." "Поиск процесса"
        Show-ToolkitMenuItem "3." "Завершить процесс"
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {

                try {

                    $processes = @(
                        Get-CimInstance `
                            -ClassName Win32_Process `
                            -ComputerName $computer `
                            -ErrorAction Stop |
                        Sort-Object WorkingSetSize -Descending |
                        Select-Object -First 50
                    )

                    Write-Host ""
                    Write-Host "ТОП-50 ПРОЦЕССОВ ПО ПАМЯТИ" -ForegroundColor Cyan
                    Write-Host "────────────────────────────────────────────────────────────"

                    $processes |
                        Select-Object `
                            ProcessId,
                            Name,
                            @{
                                Name = "RAM_MB"
                                Expression = {
                                    [math]::Round(
                                        $_.WorkingSetSize / 1MB,
                                        1
                                    )
                                }
                            },
                            @{
                                Name = "Путь"
                                Expression = {
                                    $_.ExecutablePath
                                }
                            } |
                        Format-Table -AutoSize

                }
                catch {
                    Show-Error "Не удалось получить процессы: $($_.Exception.Message)"
                }

                Read-ToolkitKey
            }

            '2' {

                $name = Read-Host "Имя процесса (например chrome)"

                if ([string]::IsNullOrWhiteSpace($name)) {
                    Show-Warning "Имя процесса не указано."
                    Read-ToolkitKey
                    continue
                }

                try {

                    $processes = @(
                        Get-CimInstance `
                            -ClassName Win32_Process `
                            -ComputerName $computer `
                            -ErrorAction Stop |
                        Where-Object {
                            $_.Name -like "*$name*"
                        }
                    )

                    if ($processes.Count -eq 0) {
                        Show-Warning "Процессы не найдены."
                    }
                    else {

                        Write-Host ""
                        Write-Host "НАЙДЕННЫЕ ПРОЦЕССЫ" -ForegroundColor Cyan
                        Write-Host "────────────────────────────────────────────────────────────"

                        $processes |
                            Select-Object `
                                ProcessId,
                                Name,
                                @{
                                    Name = "RAM_MB"
                                    Expression = {
                                        [math]::Round(
                                            $_.WorkingSetSize / 1MB,
                                            1
                                        )
                                    }
                                },
                                ExecutablePath |
                            Format-Table -AutoSize
                    }

                }
                catch {
                    Show-Error "Не удалось получить процессы: $($_.Exception.Message)"
                }

                Read-ToolkitKey
            }

            '3' {

                $pidText = Read-Host "Введите PID процесса"

                $processId = 0

                if (
                    -not [int]::TryParse(
                        $pidText,
                        [ref]$processId
                    ) -or
                    $processId -le 0
                ) {
                    Show-Error "Некорректный PID."
                    Read-ToolkitKey
                    continue
                }

                try {

                    $process = Get-CimInstance `
                        -ClassName Win32_Process `
                        -ComputerName $computer `
                        -Filter "ProcessId = $processId" `
                        -ErrorAction Stop

                    if (-not $process) {
                        Show-Warning "Процесс с PID $processId не найден."
                        Read-ToolkitKey
                        continue
                    }

                    Write-Host ""
                    Write-Host "Процесс: " -NoNewline
                    Write-Host $process.Name -ForegroundColor Cyan

                    Write-Host "PID:      $($process.ProcessId)"

                    Write-Host ""

                    if (
                        -not (
                            Confirm-ToolkitAction `
                                "Процесс будет принудительно завершён."
                        )
                    ) {
                        Show-Info "Операция отменена."
                        Read-ToolkitKey
                        continue
                    }

                    $result = Invoke-CimMethod `
                        -InputObject $process `
                        -MethodName Terminate `
                        -ErrorAction Stop

                    if ($result.ReturnValue -eq 0) {
                        Show-Success "Процесс завершён."
                    }
                    else {
                        Show-Error "Не удалось завершить процесс. Код: $($result.ReturnValue)"
                    }

                }
                catch {
                    Show-Error "Ошибка завершения процесса: $($_.Exception.Message)"
                }

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


# ============================================================
# ДИСКИ
# ============================================================

function Show-RemoteDisks {

    Show-ToolkitHeader "ДИСКИ УДАЛЁННОГО КОМПЬЮТЕРА"

    $computer = $Script:RemoteComputer

    if ([string]::IsNullOrWhiteSpace($computer)) {
        Show-Error "Удалённый компьютер не выбран."
        return
    }

    try {

        $disks = @(
            Get-CimInstance `
                -ClassName Win32_LogicalDisk `
                -ComputerName $computer `
                -Filter "DriveType = 3" `
                -ErrorAction Stop |
            Sort-Object DeviceID
        )

        if ($disks.Count -eq 0) {
            Show-Warning "Локальные диски не найдены."
            return
        }

        Write-Host "Компьютер: " -NoNewline
        Write-Host $computer -ForegroundColor Cyan

        Write-Host ""

        foreach ($disk in $disks) {

            if ($disk.Size -le 0) {
                continue
            }

            $totalGB = $disk.Size / 1GB
            $freeGB  = $disk.FreeSpace / 1GB
            $freePct = ($disk.FreeSpace / $disk.Size) * 100

            $freeText = "{0:N1}%" -f $freePct

            if ($freePct -lt 10) {
                $color = "Red"
                $status = "КРИТИЧНО"
            }
            elseif ($freePct -lt 20) {
                $color = "Yellow"
                $status = "МАЛО"
            }
            else {
                $color = "Green"
                $status = "OK"
            }

            Write-Host ""
            Write-Host (
                "{0}  {1:N1} GB / свободно {2:N1} GB  ({3})  " -f `
                $disk.DeviceID,
                $totalGB,
                $freeGB,
                $freeText
            ) -NoNewline

            Write-Host "[$status]" -ForegroundColor $color
        }

        Write-Host ""
    }
    catch {
        Show-Error "Не удалось получить информацию о дисках: $($_.Exception.Message)"
    }
}


# ============================================================
# ГЛАВНОЕ МЕНЮ УДАЛЁННОГО УПРАВЛЕНИЯ
# ============================================================

function Start-RemoteMenu {

    if ([string]::IsNullOrWhiteSpace($Script:RemoteComputer)) {
        if (-not (Read-RemoteComputer)) {
            return
        }
    }

    while ($true) {

        Show-ToolkitHeader "УДАЛЁННОЕ УПРАВЛЕНИЕ"

        Write-Host "Удаленный компьютер: " -NoNewline
        Write-Host $Script:RemoteComputer -ForegroundColor Cyan

        Write-Host ""

        Show-ToolkitMenuItem "1." "Диагностика компьютера"
        Show-ToolkitMenuItem "2." "Системная информация"
        Show-ToolkitMenuItem "3." "Пользователи"
        Show-ToolkitMenuItem "4." "Службы"
        Show-ToolkitMenuItem "5." "Отправить сообщение"
        Show-ToolkitMenuItem "6." "Перезагрузить"
        Show-ToolkitMenuItem "7." "Выключить"
        Show-ToolkitMenuItem "8." "Проверить WinRM"
        Show-ToolkitMenuItem "9." "PowerShell Remoting"
        Show-ToolkitMenuItem "10." "Процессы"
        Show-ToolkitMenuItem "11." "Диски"

        Write-Host ""
        Show-ToolkitMenuItem "C" "Сменить компьютер"
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {
                Start-RemoteDiagnostics
                Read-ToolkitKey
            }

            '2' {
                Show-RemoteSystemInfo
                Read-ToolkitKey
            }

            '3' {
                Show-RemoteUsers
                Read-ToolkitKey
            }

            '4' {
                Start-RemoteServices
            }

            '5' {
                Send-RemoteMessage
                Read-ToolkitKey
            }

            '6' {
                Restart-RemoteComputer
                Read-ToolkitKey
            }

            '7' {
                Stop-RemoteComputer
                Read-ToolkitKey
            }

            '8' {
                Test-RemoteWinRM
                Read-ToolkitKey
            }

            '9' {
                Start-RemotePowerShell
            }

            '10' {
                Start-RemoteProcesses
            }

            '11' {
                Show-RemoteDisks
                Read-ToolkitKey
            }

            'C' {
                Read-RemoteComputer
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