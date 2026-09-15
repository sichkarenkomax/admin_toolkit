function Start-AdminToolkit {

    while ($true) {

        Show-ToolkitHeader "ГЛАВНОЕ МЕНЮ"

        Show-ToolkitMenuItem "1." "Система"
        Show-ToolkitMenuItem "2." "Сеть"
        Show-ToolkitMenuItem "3." "Очистка"
        Show-ToolkitMenuItem "4." "Программное обеспечение"
		Show-ToolkitMenuItem "5." "Ремонт Windows"
		Show-ToolkitMenuItem "6." "Удаленное управление"

        Write-Host ""
        Show-ToolkitMenuItem "0" "Выход"

        $choice = Read-ToolkitChoice

        switch ($choice.ToUpperInvariant()) {

            '1' {
                Start-SystemMenu
            }
            '2' {
                Start-NetworkMenu
            }
			'3' {
				Start-CleanupMenu
			}

			'4' {
				Start-SoftwareMenu
			}
			
			'5' {
			Start-RepairMenu
			}
			
			'6' { 
			Start-RemoteMenu 
			}

            '0' {
                Clear-ToolkitScreen
                return
            }

            default {
                Show-Error "Неизвестная команда."
                Start-Sleep -Milliseconds 800
            }
        }
    }
}

# by sichkarenkomax