<#
===============================================================================
  Entorno VLSI - Microelectronica Digital
  Instalador completo para Windows
  -----------------------------------------------------------------------------
  Crea una distro Ubuntu 24.04 AISLADA, con nombre y usuario propios, e instala
  todas las herramientas del curso sin intervencion del alumno.

  Uso (PowerShell como Administrador):
     irm https://raw.githubusercontent.com/Lujham1/Entorno_Microelectronica_Digital/main/install-wsl.ps1 | iex
===============================================================================
#>

$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = 1   # wsl.exe imprime UTF-8 y no UTF-16 con bytes nulos

# --- Parametros -------------------------------------------------------------
$RepoRaw     = 'https://raw.githubusercontent.com/Lujham1/Entorno_Microelectronica_Digital/main'
$DistroBase  = 'Ubuntu-24.04'
$DistroName  = 'Microelectronica_Digital'
$LinuxUser   = 'microelectronica_digital'
$InstallDir  = Join-Path $env:LOCALAPPDATA "WSL\$DistroName"
$SetupUrl    = "$RepoRaw/setup.sh"

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

# --- [0] Auto-elevacion a Administrador -------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Se necesitan permisos de Administrador." -ForegroundColor Yellow
    Write-Host "Acepta el cartel de Windows que va a aparecer." -ForegroundColor Yellow
    $cmd = "irm $RepoRaw/install-wsl.ps1 | iex"
    Start-Process powershell.exe -Verb RunAs -ArgumentList `
        '-NoExit','-ExecutionPolicy','Bypass','-Command',$cmd
    return
}

# --- [1] WSL presente y actualizado -----------------------------------------
Write-Paso 1 "Comprobando WSL"

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "WSL no esta instalado. Instalando componentes base..."
    wsl --install --no-distribution
    Write-Host ""
    Write-Host "REINICIA WINDOWS y volve a pegar la misma linea." -ForegroundColor Yellow
    return
}

Write-Host "Actualizando WSL..."
wsl --update 2>&1 | Out-Host

$verOut = (wsl --version 2>&1) -join "`n"
Write-Host $verOut

# El flag --name existe desde WSL 2.4.8; sin el no podemos aislar la distro
$m = [regex]::Match($verOut, 'WSL[^\d]*(\d+)\.(\d+)\.(\d+)')
if ($m.Success) {
    $v = [version]("{0}.{1}.{2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value)
    if ($v -lt [version]'2.4.8') {
        Write-Host ""
        Write-Host "ERROR: tu WSL es $v y se necesita 2.4.8 o superior." -ForegroundColor Red
        Write-Host "Actualiza Windows y volve a intentar." -ForegroundColor Red
        return
    }
}

# --- [2] Instalacion previa con el mismo nombre ------------------------------
Write-Paso 2 "Buscando instalaciones previas"

$instaladas = @(wsl --list --quiet 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($instaladas.Count -gt 0) {
    Write-Host "Distros registradas actualmente:"
    $instaladas | ForEach-Object { Write-Host "   - $_" }
} else {
    Write-Host "No hay ninguna distro registrada."
}

if ($instaladas -contains $DistroName) {
    Write-Host ""
    Write-Host "Ya existe una distro llamada '$DistroName'." -ForegroundColor Yellow
    Write-Host "Si continuas se BORRARA por completo (archivos, usuario, todo)." -ForegroundColor Yellow
    $r = Read-Host "Escribi BORRAR para reinstalar desde cero, o ENTER para cancelar"
    if ($r -ne 'BORRAR') { Write-Host "Cancelado. No se modifico nada."; return }
    wsl --terminate $DistroName 2>$null | Out-Null
    wsl --shutdown
    wsl --unregister $DistroName
    Write-Host "Distro previa eliminada."
}

# --- [2b] Blindaje contra cloud-init ajeno + creacion del usuario -----------
# Ubuntu para WSL lee %USERPROFILE%\.cloud-init\ y aplica esa configuracion a
# CADA instancia nueva. Un default.user-data dejado por otro instalador se
# colaria en nuestra distro (usuario ajeno, contenedores, PATH contaminado).
# Como cloud-init prioriza el archivo mas especifico, escribimos uno con el
# nombre exacto de la instancia: ese gana siempre.
Write-Paso "2b" "Preparando configuracion de la instancia"

$ciDir = Join-Path $env:USERPROFILE '.cloud-init'
New-Item -ItemType Directory -Force -Path $ciDir | Out-Null

$ajenos = @(Get-ChildItem $ciDir -Filter '*.user-data' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "$DistroName.user-data" })
if ($ajenos.Count -gt 0) {
    Write-Host "Se detecto configuracion cloud-init de otra instalacion:" -ForegroundColor Yellow
    $ajenos | ForEach-Object { Write-Host "   - $($_.Name)" -ForegroundColor Yellow }
    Write-Host "No se borra (puede ser de otra materia), pero queda anulada aqui." -ForegroundColor Yellow
}

$ciFile = Join-Path $ciDir "$DistroName.user-data"
$ciBody = @"
#cloud-config
# Perfil de la distro '$DistroName'.
# Tiene prioridad sobre cualquier default.user-data global.
users:
  - name: $LinuxUser
    gecos: Entorno Microelectronica Digital
    groups: [adm, dialout, cdrom, floppy, sudo, audio, dip, video, plugdev, netdev]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
write_files:
  - path: /etc/wsl.conf
    append: true
    content: |
      [user]
      default=$LinuxUser
"@
Set-Content -Path $ciFile -Value $ciBody -Encoding UTF8
Write-Host "Perfil escrito. Usuario Linux: $LinuxUser"

# --- [3] Instalar la distro --------------------------------------------------
Write-Paso 3 "Instalando $DistroBase como '$DistroName'"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Write-Host "Ubicacion del disco: $InstallDir"
Write-Host "Descargando Ubuntu (~1 GB, puede tardar varios minutos)..."

wsl --install $DistroBase --name $DistroName --location $InstallDir --no-launch
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "La instalacion fallo (codigo $LASTEXITCODE)." -ForegroundColor Red
    Write-Host "Si el error menciona un reinicio pendiente: reinicia y reintenta." -ForegroundColor Red
    Write-Host "Si la descarga se cuelga: desactiva VPN y antivirus." -ForegroundColor Red
    return
}

# --- [4] Esperar a cloud-init -----------------------------------------------
# wsl --install vuelve antes de que cloud-init termine de crear el usuario.
# Sin esta espera, el setup podria correr como root o fallar.
Write-Paso 4 "Esperando la configuracion inicial"
Write-Host "Creando el usuario y aplicando la configuracion..."
wsl -d $DistroName -- cloud-init status --wait 2>&1 | Out-Host

$usuario = (wsl -d $DistroName -- whoami 2>$null)
Write-Host "Usuario activo en la distro: $usuario"
if ($usuario -notmatch $LinuxUser) {
    Write-Host "AVISO: se esperaba '$LinuxUser'. Continuo igual." -ForegroundColor Yellow
}

# --- [5] Instalar las herramientas ------------------------------------------
Write-Paso 5 "Instalando las herramientas del curso"
Write-Host "Esto tarda entre 20 y 40 minutos. No cierres la ventana."
Write-Host ""

$linuxCmd = "cd ~ && curl -fsSL '$SetupUrl' -o setup.sh && chmod +x setup.sh && ./setup.sh"
wsl -d $DistroName -- bash -lc $linuxCmd
$setupExit = $LASTEXITCODE

# --- [6] Cierre --------------------------------------------------------------
Write-Paso 6 "Finalizando"

# Terminar la distro fuerza que la proxima sesion cargue /etc/profile.d
wsl --terminate $DistroName 2>$null | Out-Null

if ($setupExit -ne 0) {
    Write-Host ""
    Write-Host "La instalacion de herramientas termino con errores." -ForegroundColor Red
    Write-Host "Entra con:  wsl -d $DistroName" -ForegroundColor Yellow
    Write-Host "y corre:    ./setup.sh verify" -ForegroundColor Yellow
    Write-Host "para ver que falto. Podes reintentar un paso con ./setup.sh N" -ForegroundColor Yellow
    return
}

Write-Host @"

==========================================
 Entorno VLSI instalado correctamente
==========================================

Para entrar al entorno de trabajo:

    wsl -d $DistroName

Ya adentro, proba las herramientas:

    xschem &        editor de esquematicos
    klayout -e &    editor de layout

Comandos utiles:

    wsl -d $DistroName            entrar
    wsl --shutdown                apagar WSL
    wsl --unregister $DistroName  borrar TODO y empezar de cero

"@ -ForegroundColor Green
