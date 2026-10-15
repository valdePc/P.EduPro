param([switch]$WaitForServer)

$ErrorActionPreference = 'Stop'
$site = 'http://localhost:55595'
$debugPort = 52610
$profile = Join-Path $env:LOCALAPPDATA 'ValMich\EduProChromeDev'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
if (-not (Test-Path -LiteralPath $chrome -PathType Leaf)) {
  throw 'No se encontró Google Chrome en la ruta esperada.'
}

if (-not $WaitForServer) {
  $scriptPath = $MyInvocation.MyCommand.Path
  Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $scriptPath + '"'), '-WaitForServer'
  ) -WindowStyle Hidden | Out-Null
  return
}

$ready = $false
for ($attempt = 0; $attempt -lt 90; $attempt++) {
  try {
    $response = Invoke-WebRequest -Uri $site -UseBasicParsing -TimeoutSec 2
    if ($response.StatusCode -eq 200) { $ready = $true; break }
  } catch { }
  Start-Sleep -Seconds 1
}
if (-not $ready) { return }

New-Item -ItemType Directory -Path $profile -Force | Out-Null
Start-Process -FilePath $chrome -ArgumentList @(
  "--user-data-dir=$profile",
  "--remote-debugging-port=$debugPort",
  '--no-first-run',
  '--no-default-browser-check',
  $site
) -WindowStyle Normal | Out-Null
