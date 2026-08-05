<#
===============================================================================
  Entorno Microelectronica Digital - Instalador WSL
  -----------------------------------------------------------------------------
  Crea una distro Ubuntu 24.04 LIMPIA con nombre propio, de modo que NUNCA
  colisione con otras instalaciones de WSL que el alumno ya tenga.

  Uso:  irm <url-raw-de-este-archivo> | iex
===============================================================================
#>

$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = 1   # hace que wsl.exe imprima UTF-8 y no UTF-16 con bytes nulos

# --- Parametros -------------------------------------------------------------
$DistroBase = 'Ubuntu-24.04'
$DistroName = 'Microelectronica_Digital'
$InstallDir = Join-Path $env:LOCALAPPDATA "WSL\$DistroName"

function Write-Paso($n, $txt) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host " [$n] $txt" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "  Entorno VLSI - Microelectronica Digital" -ForegroundColor Green
Write-Host "  Distro destino: $DistroName" -ForegroundColor Green
Write-Host ""

# --- [0] Permisos de administrador ------------------------------------------
Write-Paso 0 "Verificando permisos"
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: abri PowerShell como Administrador y volve a ejecutar." -ForegroundColor Red
    return
}
Write-Host "OK - ejecutando como administrador."

# --- [1] WSL presente y actualizado -----------------------------------------
Write-Paso 1 "Comprobando WSL"

$wslPresente = $null -ne (Get-Command wsl.exe -ErrorAction SilentlyContinue)
if (-not $wslPresente) {
    Write-Host "WSL no esta instalado. Instalando componentes base..."
    wsl --install --no-distribution
    Write-Host ""
    Write-Host "REINICIA WINDOWS y volve a ejecutar esta misma linea." -ForegroundColor Yellow
    return
}

Write-Host "Actualizando WSL a la ultima version..."
wsl --update 2>&1 | Out-Host

$verOut = (wsl --version 2>&1) -join "`n"
Write-Host $verOut

# El flag --name existe desde WSL 2.4.8. Sin el, no podemos aislar la distro.
$verMatch = [regex]::Match($verOut, 'WSL[^\d]*(\d+)\.(\d+)\.(\d+)')
if ($verMatch.Success) {
    $v = [version]("{0}.{1}.{2}" -f $verMatch.Groups[1].Value, `
                                    $verMatch.Groups[2].Value, `
                                    $verMatch.Groups[3].Value)
    if ($v -lt [version]'2.4.8') {
        Write-Host ""
        Write-Host "ERROR: tu WSL es $v y se necesita 2.4.8 o superior." -ForegroundColor Red
        Write-Host "Actualiza Windows / la app 'Windows Subsystem for Linux' desde la Store." -ForegroundColor Red
        return
    }
}

# --- [2] Limpiar instalacion previa con el mismo nombre ---------------------
Write-Paso 2 "Buscando instalaciones previas"

$instaladas = @(wsl --list --quiet 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($instaladas.Count -gt 0) {
    Write-Host "Distros actualmente registradas:"
    $instaladas | ForEach-Object { Write-Host "   - $_" }
} else {
    Write-Host "No hay ninguna distro registrada."
}

if ($instaladas -contains $DistroName) {
    Write-Host ""
    Write-Host "Ya existe una distro llamada '$DistroName'." -ForegroundColor Yellow
    Write-Host "Si continuas se BORRARA por completo (archivos, usuario, todo)." -ForegroundColor Yellow
    $r = Read-Host "Escribi BORRAR para reinstalar desde cero, o ENTER para cancelar"
    if ($r -ne 'BORRAR') {
        Write-Host "Cancelado. No se modifico nada."
        return
    }
    wsl --terminate $DistroName 2>$null | Out-Null
    wsl --shutdown
    wsl --unregister $DistroName
    Write-Host "Distro previa eliminada."
}

# --- [3] Instalar la distro --------------------------------------------------
Write-Paso 3 "Instalando $DistroBase como '$DistroName'"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Write-Host "Ubicacion del disco: $InstallDir"
Write-Host "Descargando (puede tardar varios minutos)..."

wsl --install $DistroBase --name $DistroName --location $InstallDir --no-launch

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "La instalacion fallo (codigo $LASTEXITCODE)." -ForegroundColor Red
    Write-Host "Si el error menciona un reinicio pendiente: reinicia Windows y reintenta." -ForegroundColor Red
    return
}

# --- [4] Instrucciones finales ----------------------------------------------
Write-Paso 4 "Listo"

Write-Host @"

La distro '$DistroName' quedo instalada y AISLADA de cualquier otra.

PASO SIGUIENTE - ejecuta este comando para entrar por primera vez:

    wsl -d $DistroName

Te va a pedir crear un usuario y contraseña de Linux (anotala, la vas a
necesitar para sudo). Una vez adentro, pega el comando de Linux del
instructivo para instalar las herramientas.

Comandos utiles:
    wsl -d $DistroName            entrar al entorno
    wsl --shutdown                apagar WSL
    wsl --unregister $DistroName  borrar TODO y empezar de cero

"@ -ForegroundColor Green
