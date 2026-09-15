function Clear-ToolkitScreen {
    Clear-Host
}

function Show-ToolkitHeader {
    param(
        [string]$Title
    )

    Clear-ToolkitScreen

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host "  ADMIN TOOLKIT" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-ToolkitMenuItem {
    param(
        [string]$Key,
        [string]$Text
    )

    Write-Host ("  {0,-4} {1}" -f $Key, $Text)
}

function Read-ToolkitChoice {
    Write-Host ""
    return (Read-Host "Выберите действие")
}

function Read-ToolkitKey {
    Write-Host ""
    [void](Read-Host "Нажмите Enter для продолжения")
}

function Show-Error {
    param(
        [string]$Message
    )

    Write-Host ""
    Write-Host "ОШИБКА: $Message" -ForegroundColor Red
}

function Show-Info {
    param(
        [string]$Message
    )

    Write-Host ""
    Write-Host $Message -ForegroundColor Cyan
}

function Show-Success {
    param(
        [string]$Message
    )

    Write-Host ""
    Write-Host $Message -ForegroundColor Green
}

function Show-Warning {
    param(
        [string]$Message
    )

    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
}

function Confirm-ToolkitAction {
    param(
        [string]$Message
    )

    Write-Host ""
    Write-Host "$Message" -ForegroundColor Yellow
    $answer = Read-Host "Продолжить? [Y/N]"

    return ($answer.Trim().ToUpperInvariant() -eq 'Y')
}