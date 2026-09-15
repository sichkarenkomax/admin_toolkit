#Requires -Version 5.1

# ============================================================
# AdminToolkit
# Программное обеспечение / Winget
# ============================================================

$Script:StandardSoftware = @(
    @{ Id = "Notepad++.Notepad++";  Name = "Notepad++" },
    @{ Id = "Google.Chrome.EXE";    Name = "Google Chrome" },
    @{ Id = "uvncbvba.UltraVNC";    Name = "UltraVNC" },
    @{ Id = "RARLab.WinRAR";        Name = "WinRAR" },
    @{ Id = "7zip.7zip";            Name = "7-Zip" },
    @{ Id = "voidtools.Everything"; Name = "Everything" }
)

# ============================================================
# Winget helpers
# ============================================================

function Test-WingetAvailable {

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue

    if ($null -eq $winget) {
        Show-Error "winget не найден в системе."
        Write-Host ""
        Write-Host "Установите или обновите App Installer из Microsoft Store." `
            -ForegroundColor Yellow
        return $false
    }

    return $true
}


function Invoke-Winget {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    & winget.exe @Arguments

    return $LASTEXITCODE
}



function Get-WingetInstalled {

    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $output = & winget.exe list `
        --id $Id `
        --exact `
        --accept-source-agreements `
        2>$null

    return ($LASTEXITCODE -eq 0 -and $output)
}


# ============================================================
# Установка стандартного ПО
# ============================================================

function Install-StandardSoftware {

    Show-ToolkitHeader "УСТАНОВКА СТАНДАРТНОГО ПО"

    if (-not (Test-WingetAvailable)) {
        Read-ToolkitKey
        return
    }

    Write-Host "Будет проверено стандартное ПО:" -ForegroundColor White
    Write-Host ""

    foreach ($software in $Script:StandardSoftware) {

        $installed = Get-WingetInstalled -Id $software.Id

        if ($installed) {
            Write-Host ("  [OK] {0}" -f $software.Name) `
                -ForegroundColor Green
        }
        else {
            Write-Host ("  [ ]  {0}" -f $software.Name)
        }
    }

    Write-Host ""

    if (-not (Confirm-ToolkitAction "Установить отсутствующее ПО?")) {
        Show-Info "Установка отменена."
        Read-ToolkitKey
        return
    }

    Write-Host ""

    $installedCount = 0
    $skippedCount   = 0
    $failedCount    = 0

    foreach ($software in $Script:StandardSoftware) {

        Write-Host ""
        Write-Host "------------------------------------------------------------"
        Write-Host ("{0}" -f $software.Name) -ForegroundColor Cyan
        Write-Host ("ID: {0}" -f $software.Id)
        Write-Host ""

        if (Get-WingetInstalled -Id $software.Id) {

            Write-Host "Уже установлено." -ForegroundColor Green
            $skippedCount++
            continue
        }

        Write-Host "Установка..." -ForegroundColor Cyan
        Write-Host ""

        $exitCode = Invoke-Winget @(
            "install",
            "--id", $software.Id,
            "--exact",
            "--accept-source-agreements",
            "--accept-package-agreements"
        )

        if ($exitCode -eq 0) {
            Write-Host ""
            Write-Host "Установлено." -ForegroundColor Green
            $installedCount++
        }
        else {
            Write-Host ""
            Write-Host "Ошибка установки. Код: $exitCode" `
                -ForegroundColor Red
            $failedCount++
        }
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "РЕЗУЛЬТАТ" -ForegroundColor Cyan
    Write-Host "============================================================"
    Write-Host ""

    Write-Host "Установлено:       $installedCount" -ForegroundColor Green
    Write-Host "Уже было установлено: $skippedCount"
    Write-Host "Ошибок:            $failedCount" `
        -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "Green" })
}


# ============================================================
# Обновление всего ПО
# ============================================================

function Update-AllSoftware {

    Show-ToolkitHeader "ОБНОВЛЕНИЕ ВСЕГО ПО"

    if (-not (Test-WingetAvailable)) {
        Read-ToolkitKey
        return
    }

    Write-Host "Поиск доступных обновлений..." -ForegroundColor Cyan
    Write-Host ""

    # ВАЖНО:
    # Не перенаправляем вывод winget.
    # Он должен напрямую идти в консоль.
    & winget.exe upgrade --accept-source-agreements

    $listExitCode = $LASTEXITCODE

    Write-Host ""

    if ($listExitCode -ne 0) {
        Show-Warning "Не удалось получить список обновлений. Код: $listExitCode"
        Read-ToolkitKey
        return
    }

    Write-Host ""

    if (-not (Confirm-ToolkitAction "Установить все доступные обновления?")) {
        Show-Info "Обновление отменено."
        return
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "  ОБНОВЛЕНИЕ ПАКЕТОВ" -ForegroundColor Cyan
    Write-Host "============================================================"
    Write-Host ""

    # Никакого перенаправления вывода.
    # winget сам пишет прогресс непосредственно в консоль.
    & winget.exe upgrade `
        --all `
        --accept-source-agreements `
        --accept-package-agreements

    $exitCode = $LASTEXITCODE

    Write-Host ""
    Write-Host "============================================================"
    Write-Host ""

    if ($exitCode -eq 0) {
        Show-Success "Обновление завершено."
    }
    else {
        Show-Warning "Обновление завершено с кодом: $exitCode"
    }
}


# ============================================================
# Установка пакета
# ============================================================

function Install-WingetPackage {

    Show-ToolkitHeader "УСТАНОВКА ПАКЕТА"

    if (-not (Test-WingetAvailable)) {
        Read-ToolkitKey
        return
    }

    $package = Read-Host "Введите ID или имя пакета"

    if ([string]::IsNullOrWhiteSpace($package)) {
        Show-Warning "Пакет не указан."
        return
    }

    Write-Host ""
    Write-Host "Поиск пакета..." -ForegroundColor Cyan
    Write-Host ""

    & winget.exe search $package `
        --accept-source-agreements

    Write-Host ""

    if (-not (Confirm-ToolkitAction "Продолжить установку?")) {
        Show-Info "Установка отменена."
        return
    }

    Write-Host ""
    Write-Host "Установка..." -ForegroundColor Cyan
    Write-Host ""

    $exitCode = Invoke-Winget @(
        "install",
        $package,
        "--accept-source-agreements",
        "--accept-package-agreements"
    )

    Write-Host ""

    if ($exitCode -eq 0) {
        Show-Success "Установка завершена."
    }
    else {
        Show-Error "Не удалось установить пакет. Код: $exitCode"
    }
}


# ============================================================
# Удаление пакета
# ============================================================

function Remove-WingetPackage {

    Show-ToolkitHeader "УДАЛЕНИЕ ПАКЕТА"

    if (-not (Test-WingetAvailable)) {
        Read-ToolkitKey
        return
    }

    $package = Read-Host "Введите имя или ID пакета"

    if ([string]::IsNullOrWhiteSpace($package)) {
        Show-Warning "Пакет не указан."
        return
    }

    Write-Host ""
    Write-Host "Поиск установленного пакета..." -ForegroundColor Cyan
    Write-Host ""

    & winget.exe list `
        --query $package `
        --accept-source-agreements

    Write-Host ""

    if (-not (Confirm-ToolkitAction "Удалить найденный пакет?")) {
        Show-Info "Удаление отменено."
        return
    }

    Write-Host ""
    Write-Host "Удаление..." -ForegroundColor Cyan
    Write-Host ""

    $exitCode = Invoke-Winget @(
        "uninstall",
        $package,
        "--accept-source-agreements"
    )

    Write-Host ""

    if ($exitCode -eq 0) {
        Show-Success "Удаление завершено."
    }
    else {
        Show-Error "Не удалось удалить пакет. Код: $exitCode"
    }
}


# ============================================================
# Поиск пакета
# ============================================================

function Search-WingetPackage {

    Show-ToolkitHeader "ПОИСК ПАКЕТА"

    if (-not (Test-WingetAvailable)) {
        Read-ToolkitKey
        return
    }

    $query = Read-Host "Введите поисковый запрос"

    if ([string]::IsNullOrWhiteSpace($query)) {
        Show-Warning "Поисковый запрос не указан."
        return
    }

    Write-Host ""
    Write-Host "Поиск: $query" -ForegroundColor Cyan
    Write-Host ""

    & winget.exe search $query `
        --accept-source-agreements
}


# ============================================================
# Pin пакета
# ============================================================

function Set-WingetPin {

    Show-ToolkitHeader "PIN ПАКЕТА"

    if (-not (Test-WingetAvailable)) {
        Read-ToolkitKey
        return
    }

    $package = Read-Host "Введите ID или имя пакета"

    if ([string]::IsNullOrWhiteSpace($package)) {
        Show-Warning "Пакет не указан."
        return
    }

    Write-Host ""
    Write-Host "Текущие Pin:" -ForegroundColor Cyan
    Write-Host ""

    & winget.exe pin list

    Write-Host ""

    if (-not (Confirm-ToolkitAction "Установить Pin для пакета?")) {
        Show-Info "Операция отменена."
        return
    }

    Write-Host ""
    Write-Host "Установка Pin..." -ForegroundColor Cyan
    Write-Host ""

    $exitCode = Invoke-Winget @(
        "pin",
        "add",
        "--id", $package
    )

    Write-Host ""

    if ($exitCode -eq 0) {
        Show-Success "Pin установлен."
    }
    else {
        Show-Error "Не удалось установить Pin. Код: $exitCode"
    }
}


# ============================================================
# Снятие Pin
# ============================================================

function Remove-WingetPin {

    Show-ToolkitHeader "СНЯТИЕ PIN"

    if (-not (Test-WingetAvailable)) {
        Read-ToolkitKey
        return
    }

    Write-Host "Текущие Pin:" -ForegroundColor Cyan
    Write-Host ""

    & winget.exe pin list

    Write-Host ""

    $package = Read-Host "Введите ID пакета"

    if ([string]::IsNullOrWhiteSpace($package)) {
        Show-Warning "Пакет не указан."
        return
    }

    if (-not (Confirm-ToolkitAction "Снять Pin с пакета?")) {
        Show-Info "Операция отменена."
        return
    }

    Write-Host ""
    Write-Host "Снятие Pin..." -ForegroundColor Cyan
    Write-Host ""

    $exitCode = Invoke-Winget @(
        "pin",
        "remove",
        "--id", $package
    )

    Write-Host ""

    if ($exitCode -eq 0) {
        Show-Success "Pin снят."
    }
    else {
        Show-Error "Не удалось снять Pin. Код: $exitCode"
    }
}


# ============================================================
# Обновление источников
# ============================================================

function Update-WingetSources {

    Show-ToolkitHeader "ОБНОВЛЕНИЕ ИСТОЧНИКОВ WINGET"

    if (-not (Test-WingetAvailable)) {
        Read-ToolkitKey
        return
    }

    Write-Host "Текущие источники:" -ForegroundColor Cyan
    Write-Host ""

    & winget.exe source list

    Write-Host ""

    if (-not (Confirm-ToolkitAction "Обновить источники?")) {
        Show-Info "Операция отменена."
        return
    }

    Write-Host ""
    Write-Host "Обновление источников..." -ForegroundColor Cyan
    Write-Host ""

    $exitCode = Invoke-Winget @(
        "source",
        "update"
    )

    Write-Host ""

    if ($exitCode -eq 0) {
        Show-Success "Источники успешно обновлены."
    }
    else {
        Show-Error "Не удалось обновить источники. Код: $exitCode"
    }
}


# ============================================================
# Меню
# ============================================================

function Start-SoftwareMenu {

    while ($true) {

        Show-ToolkitHeader "ПРОГРАММНОЕ ОБЕСПЕЧЕНИЕ / WINGET"

        Show-ToolkitMenuItem "1." "Установить стандартное ПО"
        Show-ToolkitMenuItem "2." "Обновить всё"
        Show-ToolkitMenuItem "3." "Установить пакет"
        Show-ToolkitMenuItem "4." "Удалить пакет"
        Show-ToolkitMenuItem "5." "Поиск пакета"
        Show-ToolkitMenuItem "6." "Pin пакета"
        Show-ToolkitMenuItem "7." "Снять Pin"
        Show-ToolkitMenuItem "8." "Обновить источники"

        Write-Host ""
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {
                Install-StandardSoftware
                Read-ToolkitKey
            }

            '2' {
                Update-AllSoftware
                Read-ToolkitKey
            }

            '3' {
                Install-WingetPackage
                Read-ToolkitKey
            }

            '4' {
                Remove-WingetPackage
                Read-ToolkitKey
            }

            '5' {
                Search-WingetPackage
                Read-ToolkitKey
            }

            '6' {
                Set-WingetPin
                Read-ToolkitKey
            }

            '7' {
                Remove-WingetPin
                Read-ToolkitKey
            }

            '8' {
                Update-WingetSources
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