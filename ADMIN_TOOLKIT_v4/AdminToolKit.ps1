#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$Script:ToolkitRoot = $PSScriptRoot



# ============================================================
# Загрузка Core
# ============================================================

. "$ToolkitRoot\Core\Admin.ps1"
. "$ToolkitRoot\Core\Console.ps1"
. "$ToolkitRoot\Core\Helpers.ps1"
. "$ToolkitRoot\Core\Main.ps1"


# ============================================================
# Загрузка System
# ============================================================

. "$ToolkitRoot\Modules\System\System.ps1"
. "$ToolkitRoot\Modules\System\Users.ps1"
. "$ToolkitRoot\Modules\System\Devices.ps1"
. "$ToolkitRoot\Modules\System\Hardware.ps1"
. "$ToolkitRoot\Modules\System\Services.ps1"
. "$ToolkitRoot\Modules\System\Startup.ps1"
. "$ToolkitRoot\Modules\System\ActiveDirectory.ps1"
. "$ToolkitRoot\Modules\System\EventLogs.ps1"
. "$ToolkitRoot\Modules\System\Cleanup.ps1"
. "$ToolkitRoot\Modules\System\Software.ps1"
. "$ToolkitRoot\Modules\System\Repair.ps1"
. "$ToolkitRoot\Modules\System\Remote.ps1"

# ============================================================
# Загрузка Network
# ============================================================

. "$ToolkitRoot\Modules\Network\Network.ps1"


# ============================================================
# Проверка прав администратора
# ============================================================

if (-not (Test-Administrator)) {

    Show-Error "AdminToolkit необходимо запускать от имени администратора."

    Read-ToolkitKey

    exit 1
}


# ============================================================
# Запуск
# ============================================================

Start-AdminToolkit

# by sichkarenkomax