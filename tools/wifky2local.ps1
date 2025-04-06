if ( $args.Length -lt 2 ){
    Write-Host "Usage: pwsh wifky2html.ps1 SRCDIR DSTDIR"
    exit 1
}
$srcdir = $args[0]
$dstdir = $args[1]
if ( -not (Test-Path -Path $srcdir -PathType Container) ){
    Write-Host "${srcdir}: not a directory"
    exit 2
}
if ( -not (Test-Path -Path $dstdir -PathType Container) ){
    Write-Host "${dstdir}: not directory"
    exit 3
}

if ( $srcdir -like "*.dat" ){
    $enc = [System.Text.Encoding]::GetEncoding("euc-jp")
} else {
    $enc = [System.Text.Encoding]::UTF8
}

function unpack($name){
    $bytes = @()
    for ( $i = 0 ; $i -lt $name.Length ; $i += 2 ) {
        $bytes +=
            ([Convert]::ToInt32( $name.Substring($i  ,1),16) +
             [Convert]::ToInt32( $name.Substring($i+1,1),16) * 16 )
    }
    return $enc.GetString($bytes)
}

function Sanitize-FileName([string] $name) {
    $map = @{
        '<' = '＜'
        '>' = '＞'
        ':' = '：'
        '"' = '”'
        '/' = '／'
        '\' = '￥'
        '|' = '｜'
        '?' = '？'
        '*' = '＊'
    }
    foreach ($key in $map.Keys) {
        $name = $name -replace [Regex]::Escape($key), $map[$key]
    }
    $name = $name -replace '[\s\.]+$', ''
    return $name
}

Get-ChildItem -Path $srcdir | Where-Object {
    $_.Name -match "^[0-9a-fA-F]+$" -and
    $_.Name.Length % 2 -eq 0
} | ForEach-Object {
    $new_name = (Sanitize-FileName (unpack $_.Name))
    $from = $_.FullName
    $to = (Join-Path -Path $dstdir -ChildPath ($new_name+".txt"))
    Write-Host ("From: {0}" -f $from)
    Write-Host ("  To: {0}" -f $to)
    $content = [System.IO.File]::ReadAllText($from, $enc)
    [System.IO.File]::WriteAllText($to, $content, [System.Text.Encoding]::UTF8)
} | Out-Null

$mkdired = @{}

Get-ChildItem -Path $srcdir | Where-Object {
    $_.Name -match "^[0-9a-fA-F]+__[0-9a-fA-F]+$" -and
    $_.Name.Length % 2 -eq 0
} | ForEach-Object {
    $names  = $_.Name -split "__"
    $page   = (Sanitize-FileName (unpack $names[0]))
    if ( $names[1] -like "00*" ){
        $attach = ("00-" + (Sanitize-FileName (unpack ($names[1].Substring(2)))))
    } else {
        $attach = (Sanitize-FileName (unpack $names[1]))
    }
    $files_dir = (Join-Path -Path $dstdir -ChildPath ($page + ".files"))
    if ( -not $mkdired.ContainsKey($page) ){
        $mkdired[$page] = $true
        New-Item -ItemType Directory -Path $files_dir
    }
    $from = $_.FullName
    $to = (Join-Path -Path $files_dir -ChildPath $attach)

    Write-Host ("From: {0}" -f $from)
    Write-Host ("  To: {0}" -f $to)

    if ( $attach -match "^comment.[0-9]+$" -or
         $attach -match "^~[0-9]{6}_[0-9]{6}\.txt$" ){
        $content = [System.IO.File]::ReadAllText($from, $enc)
        [System.IO.File]::WriteAllText($to, $content, [System.Text.Encoding]::UTF8)
    } else {
        Copy-Item -Path $from -Destination $to
    }
} | Out-Null
