function Get-FolderSizeBytes {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [int64]0
    }

    try {
        $files = Get-ChildItem `
            -LiteralPath $Path `
            -File `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue

        if (-not $files) {
            return [int64]0
        }

        return [int64](($files | Measure-Object -Property Length -Sum).Sum)
    }
    catch {
        return [int64]0
    }
}


function Format-Size {

    param(
        [Parameter(Mandatory = $true)]
        [int64]$Bytes
    )

    if ($Bytes -ge 1GB) {
        return "{0:N2} ГБ" -f ($Bytes / 1GB)
    }

    if ($Bytes -ge 1MB) {
        return "{0:N2} МБ" -f ($Bytes / 1MB)
    }

    if ($Bytes -ge 1KB) {
        return "{0:N2} КБ" -f ($Bytes / 1KB)
    }

    return "$Bytes Б"
}


function Remove-ToolkitFolderContents {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {

        Get-ChildItem `
            -LiteralPath $Path `
            -Force `
            -ErrorAction SilentlyContinue |
            Remove-Item `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
    }
    catch {
    }
}


function Remove-1CCache {

    Show-ToolkitHeader "ОЧИСТКА КЭША 1С"

    $paths = @(
        (Join-Path $env:LOCALAPPDATA '1C\1Cv8'),
        (Join-Path $env:APPDATA '1C\1Cv8')
    )

    $cacheFolders = @()

    foreach ($basePath in $paths) {

        if (-not (Test-Path -LiteralPath $basePath)) {
            continue
        }

        $folders = @(
            Get-ChildItem `
                -LiteralPath $basePath `
                -Directory `
                -Force `
                -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
            }
        )

        if ($folders.Count -gt 0) {
            $cacheFolders += $folders
        }
    }

    if ($cacheFolders.Count -eq 0) {

        Show-Success "Кэш 1С не найден."
        return
    }

    Write-Host "Найдены каталоги кэша:" -ForegroundColor Cyan
    Write-Host ""

    $totalSize = [int64]0

    foreach ($folder in $cacheFolders) {

        $size = Get-FolderSizeBytes -Path $folder.FullName
        $totalSize += $size

        Write-Host ("  {0}  ({1})" -f `
            $folder.FullName,
            (Format-Size $size))
    }

    Write-Host ""
    Write-Host "Общий размер: $(Format-Size $totalSize)" -ForegroundColor Yellow

    if (-not (Confirm-ToolkitAction "Удалить найденный кэш 1С?")) {
        Show-Info "Очистка отменена."
        return
    }

    $removed = [int64]0

    foreach ($folder in $cacheFolders) {

        $removed += Get-FolderSizeBytes -Path $folder.FullName

        Remove-Item `
            -LiteralPath $folder.FullName `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Show-Success "Кэш 1С очищен. Освобождено: $(Format-Size $removed)"
}


function Remove-Bitrix24Cache {

    Show-ToolkitHeader "ОЧИСТКА КЭША BITRIX24"

    $path = Join-Path `
        $env:APPDATA `
        'Bitrix\Desktop\3.0'

    if (-not (Test-Path -LiteralPath $path)) {

        Show-Success "Каталог Bitrix24 Desktop не найден."
        return
    }

    $size = Get-FolderSizeBytes -Path $path

    Write-Host "Каталог:"
    Write-Host $path

    Write-Host ""
    Write-Host "Размер: $(Format-Size $size)" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "ВНИМАНИЕ!" -ForegroundColor Yellow
    Write-Host "Очистка удалит содержимое Bitrix24 Desktop,"
    Write-Host "включая сохранённые логи." -ForegroundColor Yellow

    Write-Host ""
    Write-Host "1 - Сохранить логи на рабочий стол"
    Write-Host "2 - Удалить всё без сохранения логов"
    Write-Host "3 - Отменить"

    Write-Host ""

    $choice = Read-Host "Выберите действие"

    switch ($choice) {

        '1' {

            $logFiles = @(
                Get-ChildItem `
                    -LiteralPath $path `
                    -Filter '*.log' `
                    -File `
                    -Recurse `
                    -Force `
                    -ErrorAction SilentlyContinue
            )

            if ($logFiles.Count -eq 0) {

                Show-Info "Файлы логов не найдены."
            }
            else {

                $logBackupPath = Join-Path `
                    $env:USERPROFILE `
                    'Desktop\BitrixDesktop_Logs'

                New-Item `
                    -ItemType Directory `
                    -Path $logBackupPath `
                    -Force |
                    Out-Null

                foreach ($logFile in $logFiles) {

                    try {

                        Copy-Item `
                            -LiteralPath $logFile.FullName `
                            -Destination $logBackupPath `
                            -Force `
                            -ErrorAction Stop
                    }
                    catch {

                        Show-Warning (
                            "Не удалось сохранить лог: " +
                            $logFile.Name
                        )
                    }
                }

                Write-Host ""
                Show-Success (
                    "Логи сохранены в:`n$logBackupPath"
                )
            }

            Remove-ToolkitFolderContents -Path $path
        }

        '2' {

            Remove-ToolkitFolderContents -Path $path
        }

        '3' {

            Show-Info "Очистка отменена."
            return
        }

        default {

            Show-Error "Неизвестная команда."
            return
        }
    }

    Write-Host ""
    Show-Success "Кэш Bitrix24 очищен."
}


function Remove-UserTemp {

    Show-ToolkitHeader "ОЧИСТКА TEMP ПОЛЬЗОВАТЕЛЯ"

    $path = $env:TEMP

    if ([string]::IsNullOrWhiteSpace($path)) {

        Show-Error "Переменная TEMP не определена."
        return
    }

    if (-not (Test-Path -LiteralPath $path)) {

        Show-Error "Каталог TEMP не найден:`n$path"
        return
    }

    $sizeBefore = Get-FolderSizeBytes -Path $path

    Write-Host "Каталог:"
    Write-Host $path

    Write-Host ""
    Write-Host "Размер: $(Format-Size $sizeBefore)" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Файлы, используемые работающими программами," `
        -ForegroundColor DarkGray
    Write-Host "могут остаться — это нормально." `
        -ForegroundColor DarkGray

    Write-Host ""

    if (-not (Confirm-ToolkitAction "Очистить TEMP пользователя?")) {

        Show-Info "Очистка отменена."
        return
    }

    Remove-ToolkitFolderContents -Path $path

    $sizeAfter = Get-FolderSizeBytes -Path $path
    $freed = $sizeBefore - $sizeAfter

    if ($freed -lt 0) {
        $freed = [int64]0
    }

    Write-Host ""
    Write-Host "Осталось: $(Format-Size $sizeAfter)"

    Show-Success "TEMP пользователя очищен. Освобождено: $(Format-Size $freed)"
}


function Remove-WindowsTemp {

    Show-ToolkitHeader "ОЧИСТКА WINDOWS TEMP"

    $path = Join-Path $env:SystemRoot 'Temp'

    if (-not (Test-Path -LiteralPath $path)) {

        Show-Error "Каталог Windows TEMP не найден:`n$path"
        return
    }

    $sizeBefore = Get-FolderSizeBytes -Path $path

    Write-Host "Каталог:"
    Write-Host $path

    Write-Host ""
    Write-Host "Размер: $(Format-Size $sizeBefore)" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "ВНИМАНИЕ!" -ForegroundColor Yellow
    Write-Host "Занятые системой файлы будут пропущены." `
        -ForegroundColor DarkGray

    Write-Host ""

    if (-not (Confirm-ToolkitAction "Очистить Windows TEMP?")) {

        Show-Info "Очистка отменена."
        return
    }

    Remove-ToolkitFolderContents -Path $path

    $sizeAfter = Get-FolderSizeBytes -Path $path
    $freed = $sizeBefore - $sizeAfter

    if ($freed -lt 0) {
        $freed = [int64]0
    }

    Write-Host ""
    Write-Host "Осталось: $(Format-Size $sizeAfter)"

    Show-Success "Windows TEMP очищен. Освобождено: $(Format-Size $freed)"
}

function Clear-ToolkitDnsCache {

    Show-ToolkitHeader "ОЧИСТКА DNS CACHE"

    try {

        $cache = @(
            Get-DnsClientCache -ErrorAction Stop
        )

        Write-Host "Записей в DNS Cache: $($cache.Count)"
    }
    catch {

        Write-Host "Не удалось получить содержимое DNS Cache."
    }

    Write-Host ""
    Write-Host "Будет выполнено:"
    Write-Host "  Clear-DnsClientCache"
    Write-Host ""

    if (-not (Confirm-ToolkitAction "Очистить DNS Cache?")) {

        Show-Info "Очистка отменена."
        return
    }

    try {

        Clear-DnsClientCache -ErrorAction Stop

        Write-Host ""
        Show-Success "DNS Cache успешно очищен."
    }
    catch {

        Show-Error "Не удалось очистить DNS Cache:`n$($_.Exception.Message)"
    }
}


function Clear-ToolkitThumbnailCache {

    Show-ToolkitHeader "ОЧИСТКА THUMBNAIL CACHE"

    $explorerCachePath = Join-Path `
        $env:LOCALAPPDATA `
        'Microsoft\Windows\Explorer'

    if (-not (Test-Path -LiteralPath $explorerCachePath)) {

        Show-Success "Каталог Thumbnail Cache не найден."
        return
    }

    $cacheFiles = @(
        Get-ChildItem `
            -LiteralPath $explorerCachePath `
            -Filter 'thumbcache_*.db' `
            -File `
            -Force `
            -ErrorAction SilentlyContinue
    )

    if ($cacheFiles.Count -eq 0) {

        Show-Success "Файлы Thumbnail Cache не найдены."
        return
    }

    $sizeBefore = [int64](
        ($cacheFiles |
            Measure-Object -Property Length -Sum).Sum
    )

    Write-Host "Каталог:"
    Write-Host $explorerCachePath

    Write-Host ""
    Write-Host "Файлов: $($cacheFiles.Count)"
    Write-Host "Размер: $(Format-Size $sizeBefore)" `
        -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Для удаления кэша Explorer будет перезапущен." `
        -ForegroundColor DarkGray

    Write-Host ""

    if (-not (Confirm-ToolkitAction "Очистить Thumbnail Cache?")) {

        Show-Info "Очистка отменена."
        return
    }

    $explorerWasRunning = $false

    try {

        $explorerProcesses = @(
            Get-Process -Name explorer -ErrorAction SilentlyContinue
        )

        if ($explorerProcesses.Count -gt 0) {
            $explorerWasRunning = $true
        }

        if ($explorerWasRunning) {

            Write-Host ""
            Write-Host "Завершение Explorer..." -ForegroundColor Cyan

            Stop-Process `
                -Name explorer `
                -Force `
                -ErrorAction SilentlyContinue

            Start-Sleep -Milliseconds 1000
        }

        $deleted = 0
        $failed = 0

        foreach ($file in $cacheFiles) {

            try {

                Remove-Item `
                    -LiteralPath $file.FullName `
                    -Force `
                    -ErrorAction Stop

                $deleted++
            }
            catch {

                $failed++
            }
        }

        if ($explorerWasRunning) {

            Write-Host "Запуск Explorer..." -ForegroundColor Cyan

            Start-Process explorer.exe
            Start-Sleep -Milliseconds 1000
        }

        $remainingFiles = @(
            Get-ChildItem `
                -LiteralPath $explorerCachePath `
                -Filter 'thumbcache_*.db' `
                -File `
                -Force `
                -ErrorAction SilentlyContinue
        )

        $sizeAfter = [int64]0

        if ($remainingFiles.Count -gt 0) {

            $sizeAfter = [int64](
                ($remainingFiles |
                    Measure-Object -Property Length -Sum).Sum
            )
        }

        $freed = $sizeBefore - $sizeAfter

        if ($freed -lt 0) {
            $freed = [int64]0
        }

        Write-Host ""
        Write-Host "Удалено файлов: $deleted"

        if ($failed -gt 0) {

            Write-Host "Не удалось удалить: $failed" `
                -ForegroundColor Yellow
        }

        Write-Host "Осталось: $(Format-Size $sizeAfter)"

        Show-Success (
            "Thumbnail Cache очищен. " +
            "Освобождено: $(Format-Size $freed)"
        )
    }
    catch {

        if ($explorerWasRunning) {

            Start-Process explorer.exe
        }

        Show-Error (
            "Ошибка очистки Thumbnail Cache:`n" +
            $_.Exception.Message
        )
    }
}

function Get-ToolkitServiceState {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        return (Get-Service -Name $Name -ErrorAction Stop).Status
    }
    catch {
        return $null
    }
}


function Stop-ToolkitService {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {

        $service = Get-Service -Name $Name -ErrorAction Stop

        if ($service.Status -eq 'Running') {

            Stop-Service `
                -Name $Name `
                -Force `
                -ErrorAction Stop

            $service.WaitForStatus(
                [System.ServiceProcess.ServiceControllerStatus]::Stopped,
                [TimeSpan]::FromSeconds(20)
            )
        }

        return $true
    }
    catch {

        Show-Warning (
            "Не удалось остановить службу '$Name': " +
            $_.Exception.Message
        )

        return $false
    }
}


function Start-ToolkitService {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {

        $service = Get-Service -Name $Name -ErrorAction Stop

        if ($service.Status -ne 'Running') {

            Start-Service `
                -Name $Name `
                -ErrorAction Stop

            $service.WaitForStatus(
                [System.ServiceProcess.ServiceControllerStatus]::Running,
                [TimeSpan]::FromSeconds(20)
            )
        }

        return $true
    }
    catch {

        Show-Warning (
            "Не удалось запустить службу '$Name': " +
            $_.Exception.Message
        )

        return $false
    }
}


function Remove-WindowsUpdateCache {

    Show-ToolkitHeader "ОЧИСТКА WINDOWS UPDATE CACHE"

    $path = Join-Path `
        $env:SystemRoot `
        'SoftwareDistribution\Download'

    if (-not (Test-Path -LiteralPath $path)) {

        Show-Success "Кэш Windows Update не найден."
        return
    }

    $sizeBefore = Get-FolderSizeBytes -Path $path

    Write-Host "Каталог:"
    Write-Host $path

    Write-Host ""
    Write-Host "Размер: $(Format-Size $sizeBefore)" `
        -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Будет очищено только содержимое Download." `
        -ForegroundColor DarkGray
    Write-Host "Компоненты Windows Update будут остановлены" `
        -ForegroundColor DarkGray
    Write-Host "на время операции." `
        -ForegroundColor DarkGray

    Write-Host ""

    if (-not (Confirm-ToolkitAction "Очистить Windows Update Cache?")) {

        Show-Info "Очистка отменена."
        return
    }

    $wuauservState = Get-ToolkitServiceState -Name 'wuauserv'
    $bitsState = Get-ToolkitServiceState -Name 'BITS'

    Write-Host ""
    Write-Host "Остановка служб..." -ForegroundColor Cyan

    $wuauservStopped = Stop-ToolkitService -Name 'wuauserv'

    if (-not $wuauservStopped) {

        Show-Error "Не удалось остановить Windows Update."
        return
    }

    $bitsStopped = Stop-ToolkitService -Name 'BITS'

    if (-not $bitsStopped) {

        if ($wuauservState -eq 'Running') {
            Start-ToolkitService -Name 'wuauserv' | Out-Null
        }

        Show-Error "Не удалось остановить BITS."
        return
    }

    try {

        Write-Host ""
        Write-Host "Очистка кэша..." -ForegroundColor Cyan

        Remove-ToolkitFolderContents -Path $path

        $sizeAfter = Get-FolderSizeBytes -Path $path

        $freed = $sizeBefore - $sizeAfter

        if ($freed -lt 0) {
            $freed = [int64]0
        }

        Write-Host ""
        Write-Host "Оставшийся размер: $(Format-Size $sizeAfter)"

        Show-Success (
            "Windows Update Cache очищен. " +
            "Освобождено: $(Format-Size $freed)"
        )
    }
    finally {

        Write-Host ""
        Write-Host "Восстановление служб..." -ForegroundColor Cyan

        if ($bitsState -eq 'Running') {
            Start-ToolkitService -Name 'BITS' | Out-Null
        }

        if ($wuauservState -eq 'Running') {
            Start-ToolkitService -Name 'wuauserv' | Out-Null
        }
    }
}


function Remove-DeliveryOptimizationCache {

    Show-ToolkitHeader "ОЧИСТКА DELIVERY OPTIMIZATION CACHE"

    $path = Join-Path `
        $env:ProgramData `
        'Microsoft\Windows\DeliveryOptimization\Cache'

    if (-not (Test-Path -LiteralPath $path)) {

        Show-Success "Кэш Delivery Optimization не найден."
        return
    }

    $sizeBefore = Get-FolderSizeBytes -Path $path

    Write-Host "Каталог:"
    Write-Host $path

    Write-Host ""
    Write-Host "Размер: $(Format-Size $sizeBefore)" `
        -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Кэш Delivery Optimization используется Windows" `
        -ForegroundColor DarkGray
    Write-Host "для загрузки обновлений и приложений." `
        -ForegroundColor DarkGray

    Write-Host ""

    if (-not (Confirm-ToolkitAction "Очистить Delivery Optimization Cache?")) {

        Show-Info "Очистка отменена."
        return
    }

    $dosvcState = Get-ToolkitServiceState -Name 'DoSvc'

    Write-Host ""
    Write-Host "Остановка Delivery Optimization..." -ForegroundColor Cyan

    if ($dosvcState -eq 'Running') {

        if (-not (Stop-ToolkitService -Name 'DoSvc')) {

            Show-Error "Не удалось остановить службу Delivery Optimization."
            return
        }
    }

    try {

        Write-Host ""
        Write-Host "Очистка кэша..." -ForegroundColor Cyan

        Remove-ToolkitFolderContents -Path $path

        $sizeAfter = Get-FolderSizeBytes -Path $path

        $freed = $sizeBefore - $sizeAfter

        if ($freed -lt 0) {
            $freed = [int64]0
        }

        Write-Host ""
        Write-Host "Оставшийся размер: $(Format-Size $sizeAfter)"

        Show-Success (
            "Delivery Optimization Cache очищен. " +
            "Освобождено: $(Format-Size $freed)"
        )
    }
    finally {

        if ($dosvcState -eq 'Running') {

            Write-Host ""
            Write-Host "Запуск Delivery Optimization..." `
                -ForegroundColor Cyan

            Start-ToolkitService -Name 'DoSvc' | Out-Null
        }
    }
}


function Invoke-ToolkitSafeCleanup {

    Show-ToolkitHeader "ОЧИСТКА ВСЕХ БЕЗОПАСНЫХ"

    $local1C  = Join-Path $env:LOCALAPPDATA "1C\1Cv8"
    $roam1C   = Join-Path $env:APPDATA "1C\1Cv8"
    $userTemp = $env:TEMP
    $winTemp  = Join-Path $env:SystemRoot "Temp"
    $thumbDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer"

    # ---------------------------------------------------------
    # Предварительный расчёт
    # ---------------------------------------------------------

    $size1C = 0

    foreach ($root in @($local1C, $roam1C)) {

        if (Test-Path -LiteralPath $root) {

            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -match '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
                } |
                ForEach-Object {
                    $size1C += Get-FolderSizeBytes $_.FullName
                }
        }
    }

    $sizeUserTemp = 0
    if (Test-Path -LiteralPath $userTemp) {
        $sizeUserTemp = Get-FolderSizeBytes $userTemp
    }

    $sizeWindowsTemp = 0
    if (Test-Path -LiteralPath $winTemp) {
        $sizeWindowsTemp = Get-FolderSizeBytes $winTemp
    }

    $thumbFiles = @()

    if (Test-Path -LiteralPath $thumbDir) {
        $thumbFiles = @(
            Get-ChildItem -LiteralPath $thumbDir -Filter "thumbcache_*.db" -File -ErrorAction SilentlyContinue
        )
    }

    $sizeThumbnail = ($thumbFiles | Measure-Object -Property Length -Sum).Sum

    if ($null -eq $sizeThumbnail) {
        $sizeThumbnail = 0
    }

    $dnsCount = 0

    try {
        $dnsCount = @(Get-DnsClientCache -ErrorAction Stop).Count
    }
    catch {
        $dnsCount = 0
    }

    $totalSize = $size1C + $sizeUserTemp + $sizeWindowsTemp + $sizeThumbnail

    # ---------------------------------------------------------
    # Предпросмотр
    # ---------------------------------------------------------

    Write-Host "Будут очищены:" -ForegroundColor White
    Write-Host ""

    Write-Host ("  [1] Кэш 1С             {0}" -f (Format-Size $size1C))
    Write-Host ("  [2] TEMP пользователя  {0}" -f (Format-Size $sizeUserTemp))
    Write-Host ("  [3] Windows TEMP       {0}" -f (Format-Size $sizeWindowsTemp))
    Write-Host ("  [4] DNS Cache           {0} записей" -f $dnsCount)
    Write-Host ("  [5] Thumbnail Cache     {0}" -f (Format-Size $sizeThumbnail))

    Write-Host ""
    Write-Host "────────────────────────────────────────────────────────────"
    Write-Host ("Потенциально будет освобождено: {0}" -f (Format-Size $totalSize)) -ForegroundColor Cyan
    Write-Host ""

    if (-not (Confirm-ToolkitAction "Запустить очистку?")) {
        Show-Info "Очистка отменена."
        return
    }

    # ---------------------------------------------------------
    # Результаты
    # ---------------------------------------------------------

    $results = @()
    $totalFreed = 0

    # ---------------------------------------------------------
    # 1. Кэш 1С
    # ---------------------------------------------------------

    Write-Host ""
    Write-Host "[1/5] Кэш 1С..." -ForegroundColor Cyan

    $before = $size1C

    try {

        foreach ($root in @($local1C, $roam1C)) {

            if (-not (Test-Path -LiteralPath $root)) {
                continue
            }

            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -match '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
                } |
                ForEach-Object {

                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
        }

        $after = 0

        foreach ($root in @($local1C, $roam1C)) {

            if (Test-Path -LiteralPath $root) {

                Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.Name -match '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
                    } |
                    ForEach-Object {
                        $after += Get-FolderSizeBytes $_.FullName
                    }
            }
        }

        $freed = [Math]::Max(0, $before - $after)
        $totalFreed += $freed

        $results += [PSCustomObject]@{
            Name   = "Кэш 1С"
            Result = "освобождено $(Format-Size $freed)"
            Freed  = $freed
        }

        Write-Host "      Освобождено: $(Format-Size $freed)" -ForegroundColor Green
    }
    catch {
        $results += [PSCustomObject]@{
            Name   = "Кэш 1С"
            Result = "ошибка"
            Freed  = 0
        }

        Write-Host "      Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }

    # ---------------------------------------------------------
    # 2. TEMP пользователя
    # ---------------------------------------------------------

    Write-Host "[2/5] TEMP пользователя..." -ForegroundColor Cyan

    try {

        $before = Get-FolderSizeBytes $userTemp

        Remove-ToolkitFolderContents $userTemp

        $after = Get-FolderSizeBytes $userTemp
        $freed = [Math]::Max(0, $before - $after)

        $totalFreed += $freed

        $results += [PSCustomObject]@{
            Name   = "TEMP пользователя"
            Result = "освобождено $(Format-Size $freed)"
            Freed  = $freed
        }

        Write-Host "      Освобождено: $(Format-Size $freed)" -ForegroundColor Green
    }
    catch {
        $results += [PSCustomObject]@{
            Name   = "TEMP пользователя"
            Result = "ошибка"
            Freed  = 0
        }

        Write-Host "      Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }

    # ---------------------------------------------------------
    # 3. Windows TEMP
    # ---------------------------------------------------------

    Write-Host "[3/5] Windows TEMP..." -ForegroundColor Cyan

    try {

        $before = Get-FolderSizeBytes $winTemp

        Remove-ToolkitFolderContents $winTemp

        $after = Get-FolderSizeBytes $winTemp
        $freed = [Math]::Max(0, $before - $after)

        $totalFreed += $freed

        $results += [PSCustomObject]@{
            Name   = "Windows TEMP"
            Result = "освобождено $(Format-Size $freed)"
            Freed  = $freed
        }

        Write-Host "      Освобождено: $(Format-Size $freed)" -ForegroundColor Green
    }
    catch {
        $results += [PSCustomObject]@{
            Name   = "Windows TEMP"
            Result = "ошибка"
            Freed  = 0
        }

        Write-Host "      Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }

    # ---------------------------------------------------------
    # 4. DNS Cache
    # ---------------------------------------------------------

    Write-Host "[4/5] DNS Cache..." -ForegroundColor Cyan

    try {

        $beforeDns = @(Get-DnsClientCache -ErrorAction Stop).Count

        if ($beforeDns -gt 0) {
            Clear-DnsClientCache -ErrorAction Stop
        }

        $afterDns = @(Get-DnsClientCache -ErrorAction SilentlyContinue).Count

        $clearedDns = [Math]::Max(0, $beforeDns - $afterDns)

        $results += [PSCustomObject]@{
            Name   = "DNS Cache"
            Result = "очищено записей $clearedDns"
            Freed  = 0
        }

        Write-Host "      Очищено записей: $clearedDns" -ForegroundColor Green
    }
    catch {
        $results += [PSCustomObject]@{
            Name   = "DNS Cache"
            Result = "ошибка"
            Freed  = 0
        }

        Write-Host "      Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }

    # ---------------------------------------------------------
    # 5. Thumbnail Cache
    # ---------------------------------------------------------

    Write-Host "[5/5] Thumbnail Cache..." -ForegroundColor Cyan

    try {

        $before = Get-FolderSizeBytes $thumbDir

        $explorerWasRunning = @(Get-Process -Name explorer -ErrorAction SilentlyContinue).Count -gt 0

        if ($explorerWasRunning) {
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }

        try {
            Get-ChildItem -LiteralPath $thumbDir `
                -Filter "thumbcache_*.db" `
                -File `
                -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
        finally {

            if ($explorerWasRunning) {
                Start-Process explorer.exe
            }
        }

        $after = Get-FolderSizeBytes $thumbDir
        $freed = [Math]::Max(0, $before - $after)

        $totalFreed += $freed

        $results += [PSCustomObject]@{
            Name   = "Thumbnail Cache"
            Result = "освобождено $(Format-Size $freed)"
            Freed  = $freed
        }

        Write-Host "      Освобождено: $(Format-Size $freed)" -ForegroundColor Green
    }
    catch {
        $results += [PSCustomObject]@{
            Name   = "Thumbnail Cache"
            Result = "ошибка"
            Freed  = 0
        }

        Write-Host "      Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }

    # ---------------------------------------------------------
    # Итог
    # ---------------------------------------------------------

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host "  РЕЗУЛЬТАТ ОЧИСТКИ" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host ""

    foreach ($result in $results) {

        Write-Host ("  {0,-24} {1}" -f $result.Name, $result.Result)
    }

    Write-Host ""
    Write-Host "────────────────────────────────────────────────────────────"
    Write-Host ("Освобождено всего: {0}" -f (Format-Size $totalFreed)) -ForegroundColor Green
}


function Start-CleanupMenu {

    while ($true) {

        Show-ToolkitHeader "ОЧИСТКА"

        Show-ToolkitMenuItem "1." "Кэш 1С"
        Show-ToolkitMenuItem "2." "Кэш Bitrix24"
        Show-ToolkitMenuItem "3." "TEMP пользователя"
        Show-ToolkitMenuItem "4." "Windows TEMP"
        Show-ToolkitMenuItem "5." "DNS Cache"
        Show-ToolkitMenuItem "6." "Thumbnail Cache"
        Show-ToolkitMenuItem "7." "Windows Update Cache"
        Show-ToolkitMenuItem "8." "Delivery Optimization Cache"

        Write-Host ""
        Show-ToolkitMenuItem "9." "Очистить всё безопасное"

        Write-Host ""
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {
                Remove-1CCache
                Read-ToolkitKey
            }

            '2' {
                Remove-Bitrix24Cache
                Read-ToolkitKey
            }

            '3' {
                Remove-UserTemp
                Read-ToolkitKey
            }

            '4' {
                Remove-WindowsTemp
                Read-ToolkitKey
            }

			'5' {
				Clear-ToolkitDnsCache
				Read-ToolkitKey
			}

			'6' {
				Clear-ToolkitThumbnailCache
				Read-ToolkitKey
			}

			'7' {
				Remove-WindowsUpdateCache
				Read-ToolkitKey
			}

			'8' {
				Remove-DeliveryOptimizationCache
				Read-ToolkitKey
			}

			'9' {
				Invoke-ToolkitSafeCleanup
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