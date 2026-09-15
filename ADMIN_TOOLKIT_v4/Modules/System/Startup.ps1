function Get-ToolkitStartupItems {

    $items = @()

    $locations = @(
        @{
            Path   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
            Source = 'HKCU Run'
        },
        @{
            Path   = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
            Source = 'HKLM Run'
        },
        @{
            Path   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
            Source = 'HKCU RunOnce'
        },
        @{
            Path   = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
            Source = 'HKLM RunOnce'
        }
    )

    foreach ($location in $locations) {

        if (-not (Test-Path -LiteralPath $location.Path)) {
            continue
        }

        try {
            $properties = Get-ItemProperty -LiteralPath $location.Path -ErrorAction Stop
        }
        catch {
            continue
        }

        foreach ($property in $properties.PSObject.Properties) {

            # Служебные свойства PowerShell
            if ($property.Name -in @(
                'PSPath',
                'PSParentPath',
                'PSChildName',
                'PSDrive',
                'PSProvider'
            )) {
                continue
            }

            # Наши отключённые элементы здесь не показываем
            if ($property.Name -like 'AdminToolkit_Disabled_*') {
                continue
            }

            $items += [PSCustomObject]@{
                Name    = $property.Name
                Command = [string]$property.Value
                Source  = $location.Source
                Path    = $location.Path
            }
        }
    }

    return $items
}


function Show-StartupItems {

    Show-ToolkitHeader "АВТОЗАГРУЗКА"

    $items = @(Get-ToolkitStartupItems)

    if ($items.Count -eq 0) {
        Show-Info "Элементы автозагрузки не найдены."
        return
    }

    $items |
        Select-Object Name, Source, Command |
        Format-Table -Wrap -AutoSize
}


function Disable-StartupItem {

    Show-ToolkitHeader "ОТКЛЮЧЕНИЕ АВТОЗАГРУЗКИ"

    $items = @(Get-ToolkitStartupItems)

    if ($items.Count -eq 0) {
        Show-Info "Элементы автозагрузки не найдены."
        return
    }

    for ($i = 0; $i -lt $items.Count; $i++) {

        Write-Host (
            "{0}. {1} [{2}]" -f
            ($i + 1),
            $items[$i].Name,
            $items[$i].Source
        )
    }

    Write-Host ""

    $number = Read-Host "Выберите элемент"

    [int]$index = 0

    if (-not [int]::TryParse($number, [ref]$index)) {
        Show-Error "Некорректный номер."
        return
    }

    $index--

    if ($index -lt 0 -or $index -ge $items.Count) {
        Show-Error "Элемент не найден."
        return
    }

    $item = $items[$index]

    Write-Host ""
    Write-Host "Элемент:" -ForegroundColor Cyan
    Write-Host "  $($item.Name)"
    Write-Host "Источник: $($item.Source)"
    Write-Host "Команда: $($item.Command)"
    Write-Host ""

    if (-not (Confirm-ToolkitAction "Отключить этот элемент автозагрузки?")) {
        return
    }

    try {

        # Сохраняем исходную команду под специальным именем.
        # Это позволяет потом восстановить элемент.
        $disabledName = "AdminToolkit_Disabled_$($item.Name)"

        New-ItemProperty `
            -LiteralPath $item.Path `
            -Name $disabledName `
            -Value $item.Command `
            -PropertyType String `
            -Force `
            -ErrorAction Stop |
            Out-Null

        Remove-ItemProperty `
            -LiteralPath $item.Path `
            -Name $item.Name `
            -ErrorAction Stop

        Show-Success "Элемент '$($item.Name)' отключён."
    }
    catch {

        # Если сохранение прошло, а удаление не удалось,
        # пытаемся убрать резервную запись.
        try {
            Remove-ItemProperty `
                -LiteralPath $item.Path `
                -Name $disabledName `
                -ErrorAction SilentlyContinue
        }
        catch {
        }

        Show-Error "Не удалось отключить элемент:`n$($_.Exception.Message)"
    }
}


function Enable-StartupItem {

    Show-ToolkitHeader "ВКЛЮЧЕНИЕ АВТОЗАГРУЗКИ"

    $locations = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    )

    $items = @()

    foreach ($path in $locations) {

        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        try {
            $properties = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
        }
        catch {
            continue
        }

        foreach ($property in $properties.PSObject.Properties) {

            if ($property.Name -like 'AdminToolkit_Disabled_*') {

                $prefix = 'AdminToolkit_Disabled_'

                $originalName = $property.Name.Substring(
                    $prefix.Length
                )

                $items += [PSCustomObject]@{
                    Name       = $originalName
                    BackupName = $property.Name
                    Command    = [string]$property.Value
                    Path       = $path
                }
            }
        }
    }

    if ($items.Count -eq 0) {
        Show-Info "Отключённых элементов AdminToolkit не найдено."
        return
    }

    for ($i = 0; $i -lt $items.Count; $i++) {

        Write-Host (
            "{0}. {1}" -f
            ($i + 1),
            $items[$i].Name
        )
    }

    Write-Host ""

    $number = Read-Host "Выберите элемент"

    [int]$index = 0

    if (-not [int]::TryParse($number, [ref]$index)) {
        Show-Error "Некорректный номер."
        return
    }

    $index--

    if ($index -lt 0 -or $index -ge $items.Count) {
        Show-Error "Элемент не найден."
        return
    }

    $item = $items[$index]

    Write-Host ""
    Write-Host "Элемент:" -ForegroundColor Cyan
    Write-Host "  $($item.Name)"
    Write-Host "Команда: $($item.Command)"
    Write-Host ""

    if (-not (Confirm-ToolkitAction "Включить этот элемент автозагрузки?")) {
        return
    }

    try {

        # Восстанавливаем оригинальную запись
        New-ItemProperty `
            -LiteralPath $item.Path `
            -Name $item.Name `
            -Value $item.Command `
            -PropertyType String `
            -Force `
            -ErrorAction Stop |
            Out-Null

        # Удаляем нашу резервную запись
        Remove-ItemProperty `
            -LiteralPath $item.Path `
            -Name $item.BackupName `
            -ErrorAction Stop

        Show-Success "Элемент '$($item.Name)' включён."
    }
    catch {

        Show-Error "Не удалось включить элемент:`n$($_.Exception.Message)"
    }
}


function Start-StartupMenu {

    while ($true) {

        Show-ToolkitHeader "АВТОЗАГРУЗКА"

        Show-ToolkitMenuItem "1." "Список автозагрузки"
        Show-ToolkitMenuItem "2." "Отключить элемент"
        Show-ToolkitMenuItem "3." "Включить ранее отключённый элемент"

        Write-Host ""
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {
                Show-StartupItems
                Read-ToolkitKey
            }

            '2' {
                Disable-StartupItem
                Read-ToolkitKey
            }

            '3' {
                Enable-StartupItem
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