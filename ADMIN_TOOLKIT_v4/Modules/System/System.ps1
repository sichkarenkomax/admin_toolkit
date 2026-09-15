function Start-SystemMenu {
    while ($true) {
        Show-ToolkitHeader "СИСТЕМА"

        Show-ToolkitMenuItem "1." "Пользователи на устройстве"
        Show-ToolkitMenuItem "2." "Добавить пользователя в локальные администраторы"
        Show-ToolkitMenuItem "3." "Список устройств"
        Show-ToolkitMenuItem "4." "Состояние устройств"
        Show-ToolkitMenuItem "5." "Службы"
        Show-ToolkitMenuItem "6." "Автозагрузка"
        Show-ToolkitMenuItem "7." "Управление локальными пользователями"
		Show-ToolkitMenuItem "8." "Active Directory / домен"
		Show-ToolkitMenuItem "9." "Ошибки журналов событий"

        Write-Host ""
        Show-ToolkitMenuItem "R" "Обновить"
        Show-ToolkitMenuItem "0" "Назад"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {
            '1' {
                Show-Users
                Read-ToolkitKey
            }

            '2' {
                Add-UserToLocalAdministrators
                Read-ToolkitKey
            }

            '3' {
                Show-Devices
                Read-ToolkitKey
            }

            '4' {
                Show-HardwareStatus
                Read-ToolkitKey
            }

            '5' {
                Start-ServicesMenu
            }

            '6' {
                Start-StartupMenu
            }

            '7' {
                Open-LocalUserManagement
            }
			
			'8' {
				Start-ActiveDirectoryMenu
			}
			
			'9' {
				Start-EventLogsMenu
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