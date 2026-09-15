function Format-Size {
    param(
        [Parameter(Mandatory)]
        [double]$Bytes
    )

    if ($Bytes -ge 1TB) {
        return "{0:N1} TB" -f ($Bytes / 1TB)
    }

    if ($Bytes -ge 1GB) {
        return "{0:N1} GB" -f ($Bytes / 1GB)
    }

    if ($Bytes -ge 1MB) {
        return "{0:N1} MB" -f ($Bytes / 1MB)
    }

    if ($Bytes -ge 1KB) {
        return "{0:N1} KB" -f ($Bytes / 1KB)
    }

    return "{0:N0} B" -f $Bytes
}