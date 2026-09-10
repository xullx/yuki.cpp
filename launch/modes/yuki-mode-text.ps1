$ErrorActionPreference = "Stop"

$PythonExe  = "C:\Python\Python312\python.exe"
$TextScript = "C:\Yuki\src\yuki_text.py"


if (!(Test-Path $TextScript)) {
    throw "Text client not found: $TextScript"
}


& $PythonExe `
    -u `
    $TextScript
