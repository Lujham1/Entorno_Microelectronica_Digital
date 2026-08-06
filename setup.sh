#!/usr/bin/env bash
# =============================================================================
#  Entorno VLSI - Microelectronica Digital
#  Ubuntu 24.04 LTS (noble) - instalacion NATIVA (sin docker/podman/distrobox)
# -----------------------------------------------------------------------------
#  Herramientas: KLayout, Xschem, NGSpice, Magic, Netgen-LVS, OpenVAF
#  PDK: IHP SG13G2 (BiCMOS 130 nm)
#
#  Uso:
#     ./setup.sh          -> corre todos los pasos (0 a 8)
#     ./setup.sh 3        -> corre SOLO el paso 3
#     ./setup.sh 3 6      -> corre los pasos 3 al 6
#     ./setup.sh verify   -> solo verifica que todo este bien instalado
# =============================================================================

set -uo pipefail   # NO usamos -e: cada paso maneja su propio error

# --- Configuracion -----------------------------------------------------------
REPO_URL="https://github.com/Lujham1/Entorno_Microelectronica_Digital"
OPENVAF_URL="$REPO_URL/releases/download/v1.0/openvaf_23_5_0_linux_amd64.tar.gz"

KLAYOUT_VER="0.30.10"    # ultima estable: https://www.klayout.de/build.html
KLAYOUT_MD5="674a26b464841ac7385dec3cc47c2c60"

PDK_DIR="$HOME/IHP-Open-PDK"
XSCHEM_DIR="$HOME/src/xschem"
ENV_FILE="/etc/profile.d/vlsi-env.sh"

# --- Colores y helpers -------------------------------------------------------
RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YEL=$'\033[1;33m'; CYA=$'\033[0;36m'; RST=$'\033[0m'

paso()  { echo; echo "${CYA}==========================================${RST}";
          echo "${CYA} [$1] $2${RST}";
          echo "${CYA}==========================================${RST}"; }
ok()    { echo "${GRN}  OK  ${RST} $*"; }
warn()  { echo "${YEL} AVISO${RST} $*"; }
err()   { echo "${RED}ERROR ${RST} $*"; }

# =============================================================================
# [0] Chequeos previos: confirma que estamos en una distro limpia
# =============================================================================
paso_0_chequeos() {
    paso 0 "Chequeos previos"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "Sistema: $PRETTY_NAME"
        [ "${VERSION_ID:-}" = "24.04" ] || warn "Este script esta pensado para Ubuntu 24.04."
    fi

    echo "Distro WSL: ${WSL_DISTRO_NAME:-(no es WSL)}"
    echo "Usuario:    $(whoami)"
    echo "Home:       $HOME"

    # Un entorno contaminado por otra instalacion rompe todo lo que sigue
    if [ -d /foss ] || command -v distrobox >/dev/null 2>&1; then
        err "Se detecto un entorno previo (/foss o distrobox)."
        err "Esta distro no esta limpia. Reinstala con install-wsl.ps1."
        return 1
    fi
    ok "Entorno limpio."

    sudo -n true 2>/dev/null || sudo -v || { err "Se necesita sudo."; return 1; }
    ok "sudo disponible."
    return 0
}

# =============================================================================
# [1] Dependencias del sistema (librerias para compilar Xschem, Tcl/Tk, X11)
# =============================================================================
paso_1_dependencias() {
    paso 1 "Dependencias del sistema"

    sudo apt-get update -y
    sudo apt-get upgrade -y

    sudo apt-get install -y \
        build-essential git wget curl unzip pkg-config \
        python3 python3-pip python3-venv python3-psutil \
        libx11-6 libx11-dev libxrender1 libxrender-dev \
        libxcb1 libx11-xcb-dev libxpm4 libxpm-dev \
        libcairo2 libcairo2-dev \
        tcl8.6 tcl8.6-dev tk8.6 tk8.6-dev \
        flex bison gawk xterm x11-apps \
    || { err "Fallo apt-get install."; return 1; }

    ok "Dependencias instaladas."
    return 0
}

# =============================================================================
# [2] Simuladores y verificacion: NGSpice, Magic, Netgen-LVS
# =============================================================================
paso_2_simuladores() {
    paso 2 "NGSpice, Magic y Netgen-LVS"

    # OJO: en Ubuntu el paquete 'netgen' es un mallador de elementos finitos.
    # La herramienta de LVS se llama 'netgen-lvs' y su binario tambien.
    sudo apt-get install -y ngspice magic netgen-lvs \
        || { err "Fallo la instalacion de simuladores."; return 1; }

    # OSDI (necesario para los modelos Verilog-A del PDK) existe desde ngspice 39
    local nv
    nv=$(dpkg-query -W -f='${Version}' ngspice 2>/dev/null)
    echo "NGSpice version: ${nv:-desconocida}"

    ok "NGSpice, Magic y Netgen-LVS instalados."
    return 0
}

# =============================================================================
# [3] KLayout desde el .deb oficial (el de Ubuntu suele estar atrasado)
# =============================================================================
paso_3_klayout() {
    paso 3 "KLayout"

    local deb="klayout_${KLAYOUT_VER}-1_amd64.deb"
    local url="https://www.klayout.org/downloads/Ubuntu-24/${deb}"

    cd /tmp || return 1
    echo "Descargando el .deb oficial: $url"

    if wget -q --show-progress "$url" -O "$deb"; then
        local md5
        md5=$(md5sum "$deb" | cut -d' ' -f1)
        if [ "$md5" != "$KLAYOUT_MD5" ]; then
            warn "MD5 no coincide (esperado $KLAYOUT_MD5, obtenido $md5)."
            warn "Puede ser descarga corrupta o una version distinta."
        fi
        if sudo apt-get install -y "/tmp/$deb"; then
            rm -f "/tmp/$deb"
            ok "KLayout $KLAYOUT_VER instalado."
            return 0
        fi
        warn "El .deb no se pudo instalar."
    else
        warn "No se pudo descargar el .deb."
        warn "Revisa https://www.klayout.de/build.html y ajusta KLAYOUT_VER."
    fi

    warn "Cayendo al paquete de Ubuntu (puede ser mas viejo)."
    sudo apt-get install -y klayout || { err "No se pudo instalar KLayout."; return 1; }
    ok "KLayout (repo Ubuntu) instalado."
    return 0
}

# =============================================================================
# [4] Xschem compilado desde fuente (no hay paquete en Ubuntu)
# =============================================================================
paso_4_xschem() {
    paso 4 "Xschem (compilado desde fuente)"

    mkdir -p "$(dirname "$XSCHEM_DIR")"
    if [ -d "$XSCHEM_DIR/.git" ]; then
        echo "Repo existente, actualizando..."
        git -C "$XSCHEM_DIR" pull --ff-only || warn "No se pudo actualizar, sigo con lo que hay."
    else
        rm -rf "$XSCHEM_DIR"
        git clone https://github.com/StefanSchippers/xschem.git "$XSCHEM_DIR" \
            || { err "Fallo el clone de Xschem."; return 1; }
    fi

    cd "$XSCHEM_DIR" || return 1
    ./configure       || { err "Fallo ./configure (revisa el paso 1)."; return 1; }
    make -j"$(nproc)" || { err "Fallo la compilacion de Xschem."; return 1; }
    sudo make install || { err "Fallo make install."; return 1; }

    ok "Xschem instalado en $(command -v xschem)"
    return 0
}

# =============================================================================
# [5] OpenVAF: compila los modelos Verilog-A del PDK a formato OSDI
# =============================================================================
paso_5_openvaf() {
    paso 5 "OpenVAF (compilador Verilog-A)"

    if command -v openvaf >/dev/null 2>&1; then
        ok "OpenVAF ya presente: $(command -v openvaf)"
        return 0
    fi

    local tmp="/tmp/openvaf_dl"
    rm -rf "$tmp" && mkdir -p "$tmp" && cd "$tmp" || return 1

    echo "Descargando OpenVAF 23.5.0 (~52 MB)..."
    wget -q --show-progress "$OPENVAF_URL" -O openvaf.tar.gz \
        || { err "Fallo la descarga de OpenVAF desde $OPENVAF_URL"; return 1; }

    tar xzf openvaf.tar.gz \
        || { err "El archivo esta corrupto. Reintenta con: ./setup.sh 5"; return 1; }

    # El binario puede quedar suelto o dentro de una subcarpeta segun la version
    local bin
    bin=$(find "$tmp" -name openvaf -type f | head -1)
    [ -n "$bin" ] || { err "No se encontro el binario dentro del tar."; return 1; }

    sudo install -m 755 "$bin" /usr/local/bin/openvaf \
        || { err "No se pudo instalar el binario."; return 1; }
    cd /tmp && rm -rf "$tmp"

    ok "OpenVAF instalado: $(openvaf --version 2>&1 | head -1)"
    return 0
}

# =============================================================================
# [6] PDK IHP SG13G2 + variables de entorno + configuracion de Xschem
# =============================================================================
paso_6_pdk() {
    paso 6 "IHP SG13G2 Open PDK"

    # La rama 'dev' es obligatoria: los ejemplos de ngspice no andan en 'main'
    if [ -d "$PDK_DIR/.git" ]; then
        echo "PDK existente, actualizando..."
        git -C "$PDK_DIR" pull --ff-only || warn "No se pudo actualizar."
        git -C "$PDK_DIR" submodule update --init --recursive
    else
        rm -rf "$PDK_DIR"
        git clone --branch dev --recurse-submodules \
            https://github.com/IHP-GmbH/IHP-Open-PDK.git "$PDK_DIR" \
            || { err "Fallo el clone del PDK."; return 1; }
    fi
    ok "PDK en $PDK_DIR (rama dev)"

    # Variables en /etc/profile.d: se aplican en cada login y NO se duplican
    # si el script se corre dos veces (a diferencia de agregarlas al .bashrc)
    echo "Escribiendo $ENV_FILE ..."
    sudo tee "$ENV_FILE" > /dev/null <<'EOF'
# Entorno VLSI - Microelectronica Digital
export PDK_ROOT="$HOME/IHP-Open-PDK"
export PDK="ihp-sg13g2"
export KLAYOUT_HOME="$HOME/.klayout"
export KLAYOUT_PATH="$HOME/.klayout:$PDK_ROOT/$PDK/libs.tech/klayout"
EOF
    sudo chmod 644 "$ENV_FILE"
    ok "Variables escritas en $ENV_FILE"

    # shellcheck source=/dev/null
    . "$ENV_FILE"

    # --- Xschem: config propia que hereda la del PDK ---
    # No editamos el xschemrc del PDK porque un 'git pull' lo pisaria
    local xrc="$PDK_ROOT/$PDK/libs.tech/xschem/xschemrc"
    mkdir -p "$HOME/.xschem"
    if [ -f "$xrc" ]; then
        rm -f "$HOME/.xschem/xschemrc"
        cat > "$HOME/.xschem/xschemrc" <<EOF
# Config local. Hereda la del PDK y agrega ajustes del curso.
source $xrc

# Las celdas parametricas del PDK usan scripts TCL embebidos.
# Sin esto, Xschem pregunta en cada arranque.
set xschem_execute_scripts yes
EOF
        ok "Xschem configurado (hereda el xschemrc del PDK)."
    else
        warn "No se encontro $xrc"
    fi

    # --- Dependencias Python del PDK ---
    if [ -f "$PDK_DIR/requirements.txt" ]; then
        pip3 install -r "$PDK_DIR/requirements.txt" --break-system-packages \
            || warn "Algunas dependencias Python fallaron (no siempre es critico)."
    fi
    return 0
}

# =============================================================================
# [7] Compilacion de los modelos Verilog-A a OSDI
# =============================================================================
paso_7_verilog_a() {
    paso 7 "Compilando modelos Verilog-A (OSDI para NGSpice)"

    [ -f "$ENV_FILE" ] && . "$ENV_FILE"

    if ! command -v openvaf >/dev/null 2>&1; then
        err "OpenVAF no esta instalado. Corre primero: ./setup.sh 5"
        return 1
    fi

    local vadir="$PDK_ROOT/$PDK/libs.tech/verilog-a"
    [ -d "$vadir" ] || { err "No existe $vadir (falta el paso 6)."; return 1; }

    cd "$vadir" || return 1
    chmod +x openvaf-compile-va.sh
    # 'source' y no './': el script del IHP setea variables en la sesion actual.
    # Los warnings sobre $simparam en r3_cmc son normales y no afectan nada.
    # shellcheck source=/dev/null
    source ./openvaf-compile-va.sh \
        || { err "Fallo la compilacion Verilog-A."; return 1; }

    if find "$PDK_ROOT/$PDK" -name 'psp103_nqs.osdi' | grep -q .; then
        ok "psp103_nqs.osdi generado correctamente."
    else
        warn "No se encontro psp103_nqs.osdi. Los MOSFET no van a simular."
    fi

    # .spiceinit permite simular circuitos del PDK desde cualquier carpeta.
    # OJO: hay varios .spiceinit en el PDK (tests de gnucap). El bueno es este.
    local si="$PDK_ROOT/$PDK/libs.tech/ngspice/.spiceinit"
    if [ -f "$si" ]; then
        ln -sf "$si" "$HOME/.spiceinit"
        ok ".spiceinit enlazado."
    else
        warn "No se encontro $si"
    fi

    return 0   # sin esto, el ultimo test definiria el codigo de salida
}

# =============================================================================
# [8] Aceleracion grafica: activa la GPU solo si funciona en esta maquina
# =============================================================================
paso_8_gpu() {
    paso 8 "Aceleracion grafica"

    sudo apt-get install -y mesa-utils mesa-vulkan-drivers || true

    local actual
    actual=$(glxinfo -B 2>/dev/null | grep -i "OpenGL renderer" || echo "")
    echo "Renderer actual: ${actual:-desconocido}"

    # llvmpipe = render por software (lento). Probamos si D3D12 anda.
    if echo "$actual" | grep -qi llvmpipe; then
        local probado
        probado=$(GALLIUM_DRIVER=d3d12 glxinfo -B 2>/dev/null | grep -i "OpenGL renderer" || echo "")
        if echo "$probado" | grep -qi d3d12; then
            grep -q GALLIUM_DRIVER "$ENV_FILE" 2>/dev/null || \
                echo 'export GALLIUM_DRIVER=d3d12' | sudo tee -a "$ENV_FILE" > /dev/null
            ok "Aceleracion GPU activada."
            echo "   $probado"
        else
            warn "Sin aceleracion GPU en esta maquina. Se usa render por software."
            warn "El entorno funciona igual, solo que KLayout va mas lento."
        fi
    else
        ok "Ya hay aceleracion grafica activa."
    fi
    return 0
}

# =============================================================================
# Verificacion final
# =============================================================================
verificar() {
    paso "V" "Verificacion final"

    [ -f "$ENV_FILE" ] && . "$ENV_FILE"

    local fallos=0
    # netgen-lvs: el binario se llama asi, no 'netgen'
    for t in git python3 ngspice klayout xschem magic netgen-lvs openvaf; do
        if command -v "$t" >/dev/null 2>&1; then
            printf "  %-12s %s\n" "$t" "$(command -v "$t")"
        else
            printf "  %-12s ${RED}NO ENCONTRADO${RST}\n" "$t"
            fallos=$((fallos+1))
        fi
    done

    echo
    echo "PDK_ROOT = ${PDK_ROOT:-(sin definir)}"
    echo "PDK      = ${PDK:-(sin definir)}"

    if [ -d "${PDK_ROOT:-/nonexistent}/${PDK:-x}" ]; then
        ok "PDK presente."
    else
        err "PDK ausente."; fallos=$((fallos+1))
    fi

    if find "${PDK_ROOT:-/nonexistent}" -name '*.osdi' 2>/dev/null | grep -q .; then
        ok "Modelos OSDI compilados."
    else
        err "Faltan los .osdi (paso 7)."; fallos=$((fallos+1))
    fi

    [ -e "$HOME/.spiceinit" ] && ok ".spiceinit presente." || warn "Falta .spiceinit."

    echo
    if [ "$fallos" -eq 0 ]; then
        echo "${GRN}=========================================="
        echo " Entorno VLSI verificado correctamente"
        echo "==========================================${RST}"
        echo "Proba la interfaz grafica con:  xschem &  o  klayout -e &"
    else
        echo "${YEL}Quedaron $fallos puntos por resolver (ver arriba).${RST}"
    fi
    return 0
}

# =============================================================================
main() {
    local pasos=(paso_0_chequeos paso_1_dependencias paso_2_simuladores \
                 paso_3_klayout paso_4_xschem paso_5_openvaf \
                 paso_6_pdk paso_7_verilog_a paso_8_gpu)
    local ultimo=8

    if [ "${1:-}" = "verify" ]; then verificar; return; fi

    local ini="${1:-0}" fin="${2:-$ultimo}"
    [ -n "${1:-}" ] && [ -z "${2:-}" ] && fin="$ini"   # ./setup.sh 3 -> solo el 3

    for i in $(seq "$ini" "$fin"); do
        if ! "${pasos[$i]}"; then
            echo
            err "El paso $i fallo. Corregi y reintenta con:  ./setup.sh $i"
            exit 1
        fi
    done

    # La verificacion completa solo tiene sentido si se corrio todo
    if [ "$ini" -eq 0 ] && [ "$fin" -eq "$ultimo" ]; then
        verificar
        echo
        echo "${GRN}Listo. Cerra esta terminal y abrila de nuevo${RST}"
        echo "${GRN}para que se carguen las variables de entorno.${RST}"
    fi
}

main "$@"
