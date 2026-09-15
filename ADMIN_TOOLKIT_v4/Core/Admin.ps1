function Test-Administrator {

    try {

        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()

        $principal = New-Object `
            Security.Principal.WindowsPrincipal($identity)

        return $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }
    catch {

        return $false
    }
}