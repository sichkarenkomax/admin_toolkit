function Get-PnpDeviceStatusData {
    Get-PnpDevice -PresentOnly:$false |
        Sort-Object Class, FriendlyName
}

function Show-Devices {
    Show-ToolkitHeader "СПИСОК УСТРОЙСТВ"

    try {
        $devices = @(Get-PnpDeviceStatusData)
    }
    catch {
        Show-Error "Не удалось получить список устройств: $($_.Exception.Message)"
        return
    }

    if ($devices.Count -eq 0) {
        Show-Warning "Устройства не найдены."
        return
    }

    # Проблемные устройства выводим первыми
    $problemDevices = @(
        $devices | Where-Object {
            $_.Status -and
            $_.Status -ne 'OK' -and
            $_.Status -ne 'Unknown'
        }
    )

    if ($problemDevices.Count -gt 0) {
        Write-Host "ПРОБЛЕМНЫЕ УСТРОЙСТВА" -ForegroundColor Yellow
        Write-Host "────────────────────────────────────────────────────────────"

        $problemDevices |
            Select-Object Status, Class, FriendlyName, InstanceId |
            Format-Table -AutoSize

        Write-Host ""
    }
    else {
        Show-Success "Проблемных устройств не обнаружено."
        Write-Host ""
    }

    Write-Host "ВСЕ УСТРОЙСТВА"
    Write-Host "────────────────────────────────────────────────────────────"

    $devices |
        Select-Object Status, Class, FriendlyName |
        Format-Table -AutoSize
}