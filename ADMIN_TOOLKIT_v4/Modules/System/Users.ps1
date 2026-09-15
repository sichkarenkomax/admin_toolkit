function Get-ToolkitLocalUsers {

    $administrators = @()

    try {
        $administrators = @(
            Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop |
                ForEach-Object {
                    $_.Name
                }
        )
    }
    catch {
    }

    Get-LocalUser |
        Sort-Object Name |
        ForEach-Object {

            $account = $_

            $fullName = "$env:COMPUTERNAME\$($account.Name)"

            $isAdmin = $administrators | Where-Object {
                $_ -eq $fullName -or
                $_ -match "\\$([regex]::Escape($account.Name))$"
            }

            [PSCustomObject]@{
                Type      = "Локальный"
                Domain    = $env:COMPUTERNAME
                User      = $account.Name
                Enabled   = if ($account.Enabled) { "Да" } else { "Нет" }
                Admin     = if ($isAdmin) { "Да" } else { "Нет" }
                LastLogon = $account.LastLogon
                FullName  = $account.FullName
                SID       = $account.SID.Value
                Profile   = Join-Path $env:SystemDrive "Users\$($account.Name)"
            }
        }
}


function Get-ToolkitProfileUsers {

    $profiles = @()

    try {
        $profiles = @(
            Get-CimInstance Win32_UserProfile -ErrorAction Stop |
                Where-Object {
                    $_.SID -and
                    $_.LocalPath -and
                    -not $_.Special
                }
        )
    }
    catch {
        return @()
    }

    foreach ($profile in $profiles) {

        $sid = $profile.SID

        $domain = $null
        $user = $null

        try {

            $sidObject = New-Object System.Security.Principal.SecurityIdentifier($sid)

            $ntAccount = $sidObject.Translate(
                [System.Security.Principal.NTAccount]
            )

            $accountName = $ntAccount.Value

            if ($accountName -match '^(.+)\\(.+)$') {
                $domain = $matches[1]
                $user   = $matches[2]
            }
            else {
                $user = $accountName
            }
        }
        catch {

            $user = Split-Path $profile.LocalPath -Leaf
        }

        # Определяем локальную учётную запись
        $isLocal = $domain -eq $env:COMPUTERNAME

        # Определяем, загружен ли профиль сейчас
        $loaded = if ($profile.Loaded) {
            "Да"
        }
        else {
            "Нет"
        }

        [PSCustomObject]@{
            Type     = if ($isLocal) { "Локальный" } else { "Доменный" }
            Domain   = $domain
            User     = $user
            Loaded   = $loaded
            Profile  = $profile.LocalPath
            SID      = $sid
            Status   = if ($profile.Status -eq 0) {
                "OK"
            }
            else {
                $profile.Status
            }
        }
    }
}


function Show-Users {

    Show-ToolkitHeader "ПОЛЬЗОВАТЕЛИ НА УСТРОЙСТВЕ"

    # ------------------------------------------------------------
    # ЛОКАЛЬНЫЕ УЧЁТНЫЕ ЗАПИСИ
    # ------------------------------------------------------------

    Write-Host "ЛОКАЛЬНЫЕ УЧЁТНЫЕ ЗАПИСИ" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    try {

        $localUsers = @(Get-ToolkitLocalUsers)

        if ($localUsers.Count -eq 0) {
            Show-Warning "Локальные пользователи не найдены."
        }
        else {

            $localUsers |
                Select-Object Domain,
                              User,
                              Enabled,
                              Admin,
                              LastLogon,
                              FullName |
                Format-Table -AutoSize
        }
    }
    catch {

        Show-Error "Не удалось получить локальных пользователей:`n$($_.Exception.Message)"
    }


    Write-Host ""

    # ------------------------------------------------------------
    # ПРОФИЛИ ПОЛЬЗОВАТЕЛЕЙ
    # ------------------------------------------------------------

    Write-Host "ПОЛЬЗОВАТЕЛЬСКИЕ ПРОФИЛИ НА КОМПЬЮТЕРЕ" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────"

    try {

        $profiles = @(Get-ToolkitProfileUsers)

        if ($profiles.Count -eq 0) {

            Show-Warning "Пользовательские профили не найдены."
        }
        else {

            $profiles |
                Sort-Object Domain, User |
                Select-Object Type,
                              Domain,
                              User,
                              Loaded,
                              Profile |
                Format-Table -Wrap -AutoSize
        }
    }
    catch {

        Show-Error "Не удалось получить пользовательские профили:`n$($_.Exception.Message)"
    }


    Write-Host ""

    # ------------------------------------------------------------
    # ДОМЕННЫЕ ПРОФИЛИ
    # ------------------------------------------------------------

    $domainProfiles = @(
        $profiles |
            Where-Object {
                $_.Type -eq "Доменный"
            }
    )

    if ($domainProfiles.Count -gt 0) {

        Write-Host "ДОМЕННЫЕ ПОЛЬЗОВАТЕЛИ" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────"

        $domainProfiles |
            Sort-Object Domain, User |
            Select-Object Domain,
                          User,
                          Loaded,
                          Profile,
                          SID |
            Format-Table -Wrap -AutoSize
    }
}


function Add-UserToLocalAdministrators {

    Show-ToolkitHeader "ДОБАВЛЕНИЕ В ЛОКАЛЬНЫЕ АДМИНИСТРАТОРЫ"

    try {
        $users = @(Get-LocalUser | Sort-Object Name)
    }
    catch {
        Show-Error "Не удалось получить список локальных пользователей:`n$($_.Exception.Message)"
        return
    }

    if ($users.Count -eq 0) {
        Show-Warning "Пользователи не найдены."
        return
    }

    for ($i = 0; $i -lt $users.Count; $i++) {

        $status = if ($users[$i].Enabled) {
            "включён"
        }
        else {
            "отключён"
        }

        Write-Host (
            "{0}. {1} [{2}]" -f
            ($i + 1),
            $users[$i].Name,
            $status
        )
    }

    Write-Host ""

    $number = Read-Host "Выберите пользователя"

    [int]$index = 0

    if (-not [int]::TryParse($number, [ref]$index)) {
        Show-Error "Некорректный номер."
        return
    }

    $index--

    if ($index -lt 0 -or $index -ge $users.Count) {
        Show-Error "Пользователь не найден."
        return
    }

    $user = $users[$index]

    try {

        $members = @(
            Get-LocalGroupMember `
                -Group "Administrators" `
                -ErrorAction Stop
        )

        $alreadyAdmin = $members | Where-Object {
            $_.Name -match "\\$([regex]::Escape($user.Name))$"
        }

        if ($alreadyAdmin) {

            Show-Info (
                "Пользователь '$($user.Name)' уже является " +
                "локальным администратором."
            )

            return
        }
    }
    catch {

        Show-Error (
            "Не удалось проверить группу Administrators:`n" +
            $_.Exception.Message
        )

        return
    }

    Write-Host ""
    Write-Host "Пользователь:" -ForegroundColor Cyan
    Write-Host "  $env:COMPUTERNAME\$($user.Name)"
    Write-Host ""

    if (-not (
        Confirm-ToolkitAction `
            "Добавить пользователя в локальные администраторы?"
    )) {
        return
    }

    try {

        Add-LocalGroupMember `
            -Group "Administrators" `
            -Member $user.Name `
            -ErrorAction Stop

        $verify = Get-LocalGroupMember `
            -Group "Administrators" `
            -ErrorAction Stop |
            Where-Object {
                $_.Name -match "\\$([regex]::Escape($user.Name))$"
            }

        if ($verify) {

            Show-Success (
                "Пользователь '$($user.Name)' добавлен " +
                "в локальные администраторы."
            )
        }
        else {

            Show-Warning (
                "Команда выполнена, но проверить добавление не удалось."
            )
        }
    }
    catch {

        Show-Error (
            "Не удалось добавить пользователя:`n" +
            $_.Exception.Message
        )
    }
}


function Open-LocalUserManagement {

    try {
        Start-Process "lusrmgr.msc"
    }
    catch {

        Show-Error (
            "Не удалось запустить управление локальными пользователями:`n" +
            $_.Exception.Message
        )
    }
}