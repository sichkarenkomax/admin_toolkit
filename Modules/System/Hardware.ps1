#Requires -Version 5.1

# ============================================================
# AdminToolkit - Hardware
# ============================================================

$Script:LhmInitialized = $false
$Script:LhmAvailable   = $false
$Script:LhmError       = $null


# ============================================================
# Libre Hardware Monitor
# ============================================================

function Initialize-Lhm {

    if ($Script:LhmInitialized) {
        return $Script:LhmAvailable
    }

    $Script:LhmInitialized = $true
    $Script:LhmAvailable = $false
    $Script:LhmError = $null

    $additionalPath = Join-Path $Script:ToolkitRoot "Additional"

    if (-not (Test-Path -LiteralPath $additionalPath)) {
        $Script:LhmError = "Папка Additional не найдена."
        return $false
    }

    # RAMSPDToolkit-NDD.dll намеренно НЕ загружаем.
    # Он требует BlackSharp.Core 1.0.4.0.
    # LibreHardwareMonitor использует BlackSharp.Core 1.0.7.0.

    $dlls = @(
        "System.Runtime.CompilerServices.Unsafe.dll",
        "System.Memory.dll",
        "BlackSharp.Core.dll",
        "DiskInfoToolkit.dll",
        "HidSharp.dll",
        "LibreHardwareMonitorLib.dll"
    )

    foreach ($dll in $dlls) {

        $path = Join-Path $additionalPath $dll

        if (-not (Test-Path -LiteralPath $path)) {
            $Script:LhmError = "Не найдена библиотека: $dll"
            return $false
        }
    }

    try {

        # --------------------------------------------------------
        # AssemblyResolve для PowerShell 5.1 / .NET Framework
        # --------------------------------------------------------

        if (-not $Script:LhmAssemblyResolveRegistered) {

            $handler = {
                param(
                    [object]$sender,
                    [System.ResolveEventArgs]$args
                )

                $requestedName = $args.Name.Split(',')[0]
                $candidate = Join-Path $additionalPath ($requestedName + ".dll")

                if (Test-Path -LiteralPath $candidate) {

                    try {
                        return [System.Reflection.Assembly]::LoadFrom(
                            $candidate
                        )
                    }
                    catch {
                        return $null
                    }
                }

                return $null
            }

            [System.AppDomain]::CurrentDomain.add_AssemblyResolve($handler)

            $Script:LhmAssemblyResolveHandler = $handler
            $Script:LhmAssemblyResolveRegistered = $true
        }

        # --------------------------------------------------------
        # Загрузка библиотек
        # --------------------------------------------------------

        foreach ($dll in $dlls) {

            $path = Join-Path $additionalPath $dll
            $assemblyName = [System.IO.Path]::GetFileNameWithoutExtension($dll)

            $alreadyLoaded = [System.AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object {
                    $_.GetName().Name -eq $assemblyName
                }

            if (-not $alreadyLoaded) {
                [void][System.Reflection.Assembly]::LoadFrom($path)
            }
        }

        $lhmAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object {
                $_.GetName().Name -eq "LibreHardwareMonitorLib"
            } |
            Select-Object -First 1

        if (-not $lhmAssembly) {
            throw "LibreHardwareMonitorLib не загружена."
        }

        $computerType = $lhmAssembly.GetType(
            "LibreHardwareMonitor.Hardware.Computer",
            $false
        )

        if (-not $computerType) {
            throw "Тип LibreHardwareMonitor.Hardware.Computer не найден."
        }

        $Script:LhmAvailable = $true

        return $true
    }
    catch {

        $Script:LhmAvailable = $false
        $Script:LhmError = $_.Exception.Message

        return $false
    }
}


function Get-LhmData {

    if (-not (Initialize-Lhm)) {
        return @()
    }

    $monitor = $null

    try {

        $monitor = [LibreHardwareMonitor.Hardware.Computer]::new()

        $monitor.IsCPUEnabled = $true
        $monitor.IsGPUEnabled = $true
        $monitor.IsStorageEnabled = $true

        $monitor.Open()

        $data = @()

        foreach ($hw in $monitor.Hardware) {

            try {
                $hw.Update()
            }
            catch {
            }

            foreach ($sensor in $hw.Sensors) {

                if ($null -eq $sensor.Value) {
                    continue
                }

                $data += [PSCustomObject]@{
                    Sensor     = [string]$sensor.Name
                    SensorType = [string]$sensor.SensorType
                    Value      = [double]$sensor.Value
                    HwType     = [string]$hw.HardwareType
                    HwName     = [string]$hw.Name
                }
            }
        }

        return $data
    }
    catch {

        $Script:LhmAvailable = $false
        $Script:LhmError = $_.Exception.Message

        return @()
    }
    finally {

        if ($null -ne $monitor) {

            try {
                $monitor.Close()
            }
            catch {
            }
        }
    }
}


# ============================================================
# Общие функции
# ============================================================

function Format-ToolkitSize {

    param(
        [Nullable[long]]$Bytes
    )

    if ($null -eq $Bytes) {
        return "Н/Д"
    }

    if ($Bytes -ge 1TB) {
        return "{0:N1} ТБ" -f ($Bytes / 1TB)
    }

    if ($Bytes -ge 1GB) {
        return "{0:N1} ГБ" -f ($Bytes / 1GB)
    }

    if ($Bytes -ge 1MB) {
        return "{0:N1} МБ" -f ($Bytes / 1MB)
    }

    return "{0:N0} Б" -f $Bytes
}


function Format-ToolkitPercent {

    param(
        [Nullable[double]]$Value
    )

    if ($null -eq $Value) {
        return "Н/Д"
    }

    return "{0:N0} %" -f $Value
}


function Format-Temperature {

    param(
        [Nullable[double]]$Temperature
    )

    if ($null -eq $Temperature) {
        return "Н/Д"
    }

    return "{0:N0} °C" -f $Temperature
}


function Get-ToolkitTemperatureForHardware {

    param(
        [array]$LhmData,
        [string[]]$HardwareTypes
    )

    if (-not $LhmData) {
        return $null
    }

    $sensors = @(
        $LhmData |
            Where-Object {
                $_.SensorType -eq "Temperature" -and
                $_.HwType -in $HardwareTypes -and
                $null -ne $_.Value
            }
    )

    if ($sensors.Count -eq 0) {
        return $null
    }

    $preferredNames = @(
        "CPU Package",
        "CPU Core",
        "Core Average",
        "GPU Core",
        "GPU Temperature",
        "Temperature"
    )

    foreach ($name in $preferredNames) {

        $found = $sensors |
            Where-Object {
                $_.Sensor -eq $name
            } |
            Select-Object -First 1

        if ($found) {
            return [double]$found.Value
        }
    }

    return [double]$sensors[0].Value
}


# ============================================================
# CPU
# ============================================================

function Get-ToolkitCpuInfo {

    try {

        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop |
            Select-Object -First 1

        if (-not $cpu) {
            return $null
        }

        return [PSCustomObject]@{
            Name        = $cpu.Name.Trim()
            Load        = $cpu.LoadPercentage
            Cores       = $cpu.NumberOfCores
            Logical     = $cpu.NumberOfLogicalProcessors
            MaxClockMHz = $cpu.MaxClockSpeed
        }
    }
    catch {

        return [PSCustomObject]@{
            Name        = "Н/Д"
            Load        = $null
            Cores       = $null
            Logical     = $null
            MaxClockMHz = $null
        }
    }
}


# ============================================================
# RAM
# ============================================================

function Get-ToolkitMemoryInfo {

    try {

        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop

        $total = [double]$os.TotalVisibleMemorySize * 1KB
        $free = [double]$os.FreePhysicalMemory * 1KB
        $used = $total - $free

        $usedPercent = $null

        if ($total -gt 0) {
            $usedPercent = ($used / $total) * 100
        }

        return [PSCustomObject]@{
            Total       = $total
            Used        = $used
            Free        = $free
            UsedPercent = $usedPercent
        }
    }
    catch {

        return [PSCustomObject]@{
            Total       = $null
            Used        = $null
            Free        = $null
            UsedPercent = $null
        }
    }
}


# ============================================================
# GPU
# ============================================================

function Get-ToolkitGpuInfo {

    try {

        return @(
            Get-CimInstance Win32_VideoController -ErrorAction Stop |
                Where-Object {
                    $_.Name -and
                    $_.Name -notmatch "Microsoft Basic Display"
                }
        )
    }
    catch {

        return @()
    }
}


# ============================================================
# Логические диски
# ============================================================

function Get-ToolkitLogicalDisks {

    try {

        $disks = @(
            Get-CimInstance Win32_LogicalDisk `
                -Filter "DriveType=3" `
                -ErrorAction Stop
        )

        $result = @()

        foreach ($disk in $disks) {

            $used = $null
            $usedPercent = $null

            if ($disk.Size -gt 0) {

                $used = [double]$disk.Size - [double]$disk.FreeSpace

                $usedPercent =
                    ($used / [double]$disk.Size) * 100
            }

            $result += [PSCustomObject]@{
                Drive       = $disk.DeviceID
                Label       = if ($disk.VolumeName) {
                    $disk.VolumeName
                }
                else {
                    "-"
                }
                FileSystem  = $disk.FileSystem
                Total       = $disk.Size
                Free        = $disk.FreeSpace
                Used        = $used
                UsedPercent = $usedPercent
            }
        }

        return $result
    }
    catch {

        return @()
    }
}


# ============================================================
# Физические диски / Storage Reliability
# ============================================================

function Get-ToolkitDiskHealth {

    $result = @()

    if (-not (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
        return $result
    }

    try {
        $disks = @(Get-PhysicalDisk -ErrorAction Stop)
    }
    catch {
        return $result
    }

    foreach ($disk in $disks) {

        $item = [PSCustomObject]@{
            DiskName          = $disk.FriendlyName
            SerialNumber      = $disk.SerialNumber
            MediaType         = $disk.MediaType
            BusType           = $disk.BusType
            Health            = $disk.HealthStatus
            OperationalStatus = $disk.OperationalStatus
            Size              = $disk.Size

            Temperature       = $null
            Wear              = $null
            PowerOnHours      = $null
            StartStopCount    = $null
            UnsafeShutdowns   = $null
            ReadErrors        = $null
            WriteErrors       = $null
            ReadLatencyMax    = $null
            WriteLatencyMax   = $null

            Reliability       = "Н/Д"
        }

        if (Get-Command Get-StorageReliabilityCounter `
                -ErrorAction SilentlyContinue) {

            try {

                $counter = Get-StorageReliabilityCounter `
                    -PhysicalDisk $disk `
                    -ErrorAction Stop

                if ($counter) {

                    $item.Temperature = $counter.Temperature
                    $item.Wear = $counter.Wear
                    $item.PowerOnHours = $counter.PowerOnHours
                    $item.StartStopCount = $counter.StartStopCycleCount
                    $item.UnsafeShutdowns = $counter.UnsafeShutdownCount
                    $item.ReadErrors = $counter.ReadErrorsTotal
                    $item.WriteErrors = $counter.WriteErrorsTotal
                    $item.ReadLatencyMax = $counter.ReadLatencyMax
                    $item.WriteLatencyMax = $counter.WriteLatencyMax

                    $hasError = $false

                    if ($null -ne $counter.ReadErrorsTotal) {
                        if ([double]$counter.ReadErrorsTotal -gt 0) {
                            $hasError = $true
                        }
                    }

                    if ($null -ne $counter.WriteErrorsTotal) {
                        if ([double]$counter.WriteErrorsTotal -gt 0) {
                            $hasError = $true
                        }
                    }

                    if ($hasError) {
                        $item.Reliability = "Есть ошибки"
                    }
                    else {
                        $item.Reliability = "OK"
                    }
                }
            }
            catch {
            }
        }

        $result += $item
    }

    return $result
}


# ============================================================
# Сбор общей информации
# ============================================================

function Get-ToolkitHardwareStatus {

    # LHM является необязательным.
    $lhmData = @(Get-LhmData)

    $cpu = Get-ToolkitCpuInfo
    $ram = Get-ToolkitMemoryInfo
    $gpu = @(Get-ToolkitGpuInfo)
    $logicalDisks = @(Get-ToolkitLogicalDisks)
    $physicalDisks = @(Get-ToolkitDiskHealth)

    $cpuTemperature = Get-ToolkitTemperatureForHardware `
        -LhmData $lhmData `
        -HardwareTypes @("Cpu")

    $gpuTemperatures = @()

    if ($lhmData) {

        $gpuTemperatures = @(
            $lhmData |
                Where-Object {
                    $_.SensorType -eq "Temperature" -and
                    $_.HwType -match "Gpu" -and
                    $null -ne $_.Value
                }
        )
    }

    $storageTemperatures = @()

    if ($lhmData) {

        $storageTemperatures = @(
            $lhmData |
                Where-Object {
                    $_.SensorType -eq "Temperature" -and
                    $_.HwType -match "Storage" -and
                    $null -ne $_.Value
                }
        )
    }

    return [PSCustomObject]@{
        CPU                 = $cpu
        RAM                 = $ram
        GPU                 = $gpu
        LogicalDisks        = $logicalDisks
        PhysicalDisks       = $physicalDisks
        CpuTemperature      = $cpuTemperature
        GpuTemperatures     = $gpuTemperatures
        StorageTemperatures = $storageTemperatures
        LhmAvailable        = $Script:LhmAvailable
        LhmError            = $Script:LhmError
        LhmData             = $lhmData
    }
}


# ============================================================
# Экран состояния устройств
# ============================================================

function Show-HardwareStatus {

    Show-ToolkitHeader "СОСТОЯНИЕ УСТРОЙСТВ"

    $data = Get-ToolkitHardwareStatus

    # ========================================================
    # CPU
    # ========================================================

    Write-Host "ПРОЦЕССОР" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    if ($data.CPU) {

        Write-Host "Модель:        $($data.CPU.Name)"

        if ($null -ne $data.CPU.Load) {
            Write-Host "Загрузка:      $($data.CPU.Load) %"
        }
        else {
            Write-Host "Загрузка:      Н/Д"
        }

        if ($null -ne $data.CPU.Cores) {
            Write-Host "Ядра:          $($data.CPU.Cores)"
        }

        if ($null -ne $data.CPU.Logical) {
            Write-Host "Потоки:        $($data.CPU.Logical)"
        }

        $cpuTempText = Format-Temperature $data.CpuTemperature

        Write-Host "Температура:   $cpuTempText"
    }
    else {

        Show-Warning "Информация о процессоре недоступна."
    }

    Write-Host ""


    # ========================================================
    # RAM
    # ========================================================

    Write-Host "ОПЕРАТИВНАЯ ПАМЯТЬ" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    if ($data.RAM) {

        Write-Host (
            "Всего:         {0}" -f
            (Format-ToolkitSize $data.RAM.Total)
        )

        Write-Host (
            "Используется:   {0}" -f
            (Format-ToolkitSize $data.RAM.Used)
        )

        Write-Host (
            "Свободно:       {0}" -f
            (Format-ToolkitSize $data.RAM.Free)
        )

        Write-Host (
            "Использование:  {0}" -f
            (Format-ToolkitPercent $data.RAM.UsedPercent)
        )
    }

    Write-Host ""


    # ========================================================
    # GPU
    # ========================================================

    Write-Host "ВИДЕОАДАПТЕРЫ" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    if ($data.GPU.Count -eq 0) {

        Show-Warning "Видеоадаптеры не обнаружены."
    }
    else {

        foreach ($gpu in $data.GPU) {

            Write-Host "Модель:        $($gpu.Name)"

            if ($gpu.AdapterRAM) {

                $gpuMemory = Format-ToolkitSize `
                    ([long]$gpu.AdapterRAM)

                Write-Host "Память:        $gpuMemory"
            }

            $gpuTempValue = $null

            $gpuTemp = $data.GpuTemperatures |
                Where-Object {
                    $_.HwName -eq $gpu.Name
                } |
                Select-Object -First 1

            if (-not $gpuTemp) {

                $gpuTemp = $data.GpuTemperatures |
                    Select-Object -First 1
            }

            if ($gpuTemp) {
                $gpuTempValue = [double]$gpuTemp.Value
            }

            $gpuTempText = Format-Temperature $gpuTempValue

            Write-Host "Температура:   $gpuTempText"
            Write-Host ""
        }
    }


    # ========================================================
    # Логические диски
    # ========================================================

    Write-Host "ЛОГИЧЕСКИЕ ДИСКИ" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    if ($data.LogicalDisks.Count -eq 0) {

        Show-Warning "Логические диски не обнаружены."
    }
    else {

        $logicalRows = @()

        foreach ($disk in $data.LogicalDisks) {

            $logicalRows += [PSCustomObject]@{
                Диск         = $disk.Drive
                Том          = $disk.Label
                ФС           = $disk.FileSystem
                Всего        = Format-ToolkitSize $disk.Total
                Свободно     = Format-ToolkitSize $disk.Free
                Использовано = Format-ToolkitPercent $disk.UsedPercent
            }
        }

        $logicalRows | Format-Table -AutoSize
    }

    Write-Host ""


    # ========================================================
    # Физические диски
    # ========================================================

    Write-Host "ФИЗИЧЕСКИЕ ДИСКИ" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    if ($data.PhysicalDisks.Count -eq 0) {

        Show-Warning "Физические диски через Storage API не обнаружены."
    }
    else {

        $physicalRows = @()

        foreach ($disk in $data.PhysicalDisks) {

            if ($disk.Health) {
                $health = [string]$disk.Health
            }
            else {
                $health = "Н/Д"
            }

            if ($disk.Reliability) {
                $reliability = $disk.Reliability
            }
            else {
                $reliability = "Н/Д"
            }

            if ($health -eq "Healthy" -and
                $reliability -eq "Н/Д") {

                $reliability = "Данные SMART недоступны"
            }

            $physicalRows += [PSCustomObject]@{
                Диск       = $disk.DiskName
                Тип        = $disk.MediaType
                Интерфейс  = $disk.BusType
                Размер     = Format-ToolkitSize $disk.Size
                Состояние  = $health
                SMART      = $reliability
            }
        }

        $physicalRows |
            Format-Table -Wrap -AutoSize
    }

    Write-Host ""


    # ========================================================
    # Расширенные данные накопителей
    # ========================================================

    $reliabilityDisks = @(
        $data.PhysicalDisks |
            Where-Object {
                $null -ne $_.Temperature -or
                $null -ne $_.Wear -or
                $null -ne $_.PowerOnHours -or
                $null -ne $_.ReadErrors -or
                $null -ne $_.WriteErrors
            }
    )

    if ($reliabilityDisks.Count -gt 0) {

        Write-Host "РАСШИРЕННЫЕ ДАННЫЕ НАКОПИТЕЛЕЙ" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"

        foreach ($disk in $reliabilityDisks) {

            Write-Host "$($disk.DiskName)" -ForegroundColor White

            if ($null -ne $disk.Temperature) {

                $text = Format-Temperature $disk.Temperature

                Write-Host "  Температура:       $text"
            }

            if ($null -ne $disk.Wear) {
                Write-Host "  Износ:             $($disk.Wear) %"
            }

            if ($null -ne $disk.PowerOnHours) {
                Write-Host "  Наработка:         $($disk.PowerOnHours) ч"
            }

            if ($null -ne $disk.StartStopCount) {
                Write-Host "  Циклы запуска:     $($disk.StartStopCount)"
            }

            if ($null -ne $disk.UnsafeShutdowns) {
                Write-Host "  Аварийные выкл.:   $($disk.UnsafeShutdowns)"
            }

            if ($null -ne $disk.ReadErrors) {
                Write-Host "  Ошибки чтения:     $($disk.ReadErrors)"
            }

            if ($null -ne $disk.WriteErrors) {
                Write-Host "  Ошибки записи:     $($disk.WriteErrors)"
            }

            if ($null -ne $disk.ReadLatencyMax) {
                Write-Host "  Макс. чтение:      $($disk.ReadLatencyMax) ms"
            }

            if ($null -ne $disk.WriteLatencyMax) {
                Write-Host "  Макс. запись:      $($disk.WriteLatencyMax) ms"
            }

            Write-Host ""
        }
    }


    # ========================================================
    # LHM
    # ========================================================

    Write-Host "LIBRE HARDWARE MONITOR" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    if ($data.LhmAvailable) {

        Show-Success "LHM доступен. Дополнительные датчики получены."

        $temperatureRows = @(
            $data.LhmData |
                Where-Object {
                    $_.SensorType -eq "Temperature"
                } |
                ForEach-Object {

                    [PSCustomObject]@{
                        Устройство  = $_.HwName
                        Датчик      = $_.Sensor
                        Температура = Format-Temperature $_.Value
                    }
                }
        )

        if ($temperatureRows.Count -gt 0) {

            $temperatureRows |
                Format-Table -Wrap -AutoSize
        }
        else {

            Show-Info "Температурные датчики LHM не обнаружены."
        }
    }
    else {

        Show-Info "Libre Hardware Monitor недоступен."

        if ($data.LhmError) {
            Write-Host "Причина: $($data.LhmError)" -ForegroundColor DarkGray
        }
    }
}