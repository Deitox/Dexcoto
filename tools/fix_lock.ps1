$ErrorActionPreference = 'Stop'
$path = 'scripts\main.gd'
$lines = [System.IO.File]::ReadAllLines($path)
for ($i = 0; $i -lt $lines.Length - 5; $i++) {
    $t = $lines[$i].Trim()
    if ($t -eq 'elif locked:') {
        $lines[$i+1] = "`t`t`tlabel = `"[LOCKED] %s`" % label"
        # Clean up any later prefix override if present
        if ($lines[$i+3].Trim().StartsWith('if locked and not sold:')) {
            $lines[$i+3] = ''
            if ($i+4 -lt $lines.Length) { $lines[$i+4] = '' }
        }
        break
    }
}
[System.IO.File]::WriteAllLines($path, $lines, (New-Object System.Text.UTF8Encoding($false)))
Write-Output 'Fixed locked label line in scripts/main.gd'
