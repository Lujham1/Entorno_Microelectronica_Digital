#!/usr/bin/env bash
# =============================================================================
#  Entorno VLSI - Microelectronica Digital
#  Ubuntu 24.04 LTS (noble) - instalacion NATIVA (sin docker/podman/distrobox)
# -----------------------------------------------------------------------------
#  Herramientas: KLayout, Xschem, NGSpice, Magic, Netgen, OpenVAF, IHP SG13G2
#
#  Uso:
#     ./setup.sh          -> corre todos los pasos
#     ./setup.sh 3        -> corre SOLO el paso 3
#     ./setup.sh 3 6      -> corre los pasos 3 al 6
#     ./setup.sh verify   -> solo verifica que todo este bien instalado
# =============================================================================

set -uo pipefail   # NO usamos -e: cada paso maneja su propio error

# --- Configuracion -----------------------------------------------------------
KLAYOUT_VER="0.30.10"          # verifica la ultima en https://www.klayout.de/build.html
KLAYOUT_MD5="674a26b464841ac7385dec3cc47c2c60"   # MD5 del .deb de Ubuntu-24
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

    if [ -d /foss ] || command -v distrobox >/dev/null 2>&1; then
        err "Se detecto un entorno previo (/foss o distrobox)."
        err "Estas en una instalacion contaminada. Salí y usá una distro limpia."
        return 1
    fi
    ok "Entorno limpio."

    sudo -v || { err "Se necesita sudo."; return 1; }
    ok "sudo disponible."
}

# =============================================================================
paso_1_dependencias() {
    paso 1 "Dependencias del sistema"

    sudo apt-get update -y
    sudo apt-get upgrade -y

    sudo apt-get install -y \
        build-essential git wget curl unzip pkg-config \
        python3 python3-pip python3-venv \
        libx11-6 libx11-dev libxrender1 libxrender-dev \
        libxcb1 libx11-xcb-dev libxpm4 libxpm-dev \
        libcairo2 libcairo2-dev \
        tcl8.6 tcl8.6-dev tk8.6 tk8.6-dev \
        flex bison gawk xterm x11-apps \
    || { err "Fallo apt-get install."; return 1; }

    ok "Dependencias instaladas."
}

# =============================================================================
paso_2_simuladores() {
    paso 2 "NGSpice, Magic y Netgen"

    # OJO: en Ubuntu el paquete 'netgen' es un mallador de elementos finitos.
    # La herramienta de LVS es 'netgen-lvs'.
    sudo apt-get install -y ngspice magic netgen-lvs \
        || { err "Fallo la instalacion de simuladores."; return 1; }

    local nv
    nv=$(ngspice --version 2>/dev/null | head -1)
    echo "NGSpice: $nv"
    # OSDI (necesario para los modelos Verilog-A del PDK) existe desde ngspice 39
    ok "NGSpice, Magic y Netgen-LVS instalados."
}

# =============================================================================
paso_3_klayout() {
    paso 3 "KLayout"

    local deb="klayout_${KLAYOUT_VER}-1_amd64.deb"
    local url="https://www.klayout.org/downloads/Ubuntu-24/${deb}"

    cd /tmp || return 1
    echo "Intentando el .deb oficial: $url"
    if wget -q --show-progress "$url" -O "$deb"; then
        local md5
        md5=$(md5sum "$deb" | cut -d' ' -f1)
        if [ "$md5" != "$KLAYOUT_MD5" ]; then
            warn "MD5 no coincide (esperado $KLAYOUT_MD5, obtenido $md5)."
            warn "Puede ser una descarga corrupta o una version distinta."
        fi
        sudo apt-get install -y "/tmp/$deb" && ok "KLayout $KLAYOUT_VER instalado." && return 0
        warn "El .deb no se pudo instalar."
    else
        warn "No se pudo descargar el .deb (¿cambio la version?)."
        warn "Revisa https://www.klayout.de/build.html y ajusta KLAYOUT_VER."
    fi

    warn "Cayendo al paquete de Ubuntu (puede ser mas viejo)."
    sudo apt-get install -y klayout || { err "No se pudo instalar KLayout."; return 1; }
    ok "KLayout (repo Ubuntu) instalado."
}

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
    ./configure          || { err "Fallo ./configure (revisa las dependencias del paso 1)."; return 1; }
    make -j"$(nproc)"    || { err "Fallo la compilacion de Xschem."; return 1; }
    sudo make install    || { err "Fallo make install."; return 1; }

    ok "Xschem instalado en $(command -v xschem)"
}

# =============================================================================
paso_5_openvaf() {
    paso 5 "OpenVAF (compilador Verilog-A)"

    if command -v openvaf >/dev/null 2>&1; then
        ok "OpenVAF ya presente: $(command -v openvaf)"
        return 0
    fi

    local url="https://github.com/Lujham1/Entorno_Microelectronica_Digital/releases/download/v1.0/openvaf_23_5_0_linux_amd64.tar.gz"
    local tmp="/tmp/openvaf_dl"

    rm -rf "$tmp" && mkdir -p "$tmp" && cd "$tmp" || return 1
    echo "Descargando OpenVAF 23.5.0 (55 MB)..."
    wget -q --show-progress "$url" -O openvaf.tar.gz \
        || { err "Fallo la descarga de OpenVAF."; return 1; }

    tar xzf openvaf.tar.gz || { err "El archivo esta corrupto."; return 1; }

    local bin
    bin=$(find "$tmp" -name openvaf -type f | head -1)
    [ -n "$bin" ] || { err "No se encontro el binario dentro del tar."; return 1; }

    sudo install -m 755 "$bin" /usr/local/bin/openvaf || return 1
    rm -rf "$tmp"

    ok "OpenVAF instalado: $(openvaf --version 2>&1 | head -1)"
}
# =============================================================================
paso_6_pdk() {
    paso 6 "IHP SG13G2 Open PDK"

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
    ok "PDK en $PDK_DIR (branch dev)"

    # --- Variables de entorno, en /etc/profile.d para no duplicar en .bashrc ---
    echo "Escribiendo $ENV_FILE ..."
    sudo tee "$ENV_FILE" > /dev/null <<'EOF'
# Entorno VLSI - Microelectronica Digital
export PDK_ROOT="$HOME/IHP-Open-PDK"
export PDK="ihp-sg13g2"
export KLAYOUT_HOME="$HOME/.klayout"
export KLAYOUT_PATH="$HOME/.klayout:$PDK_ROOT/$PDK/libs.tech/klayout"
EOF
    sudo chmod 644 "$ENV_FILE"
    ok "Variables en $ENV_FILE (se aplican en cada login, sin duplicarse)."

    # cargarlas en esta misma sesion
    # shellcheck source=/dev/null
    . "$ENV_FILE"

    # --- Configuracion de Xschem ---
    local xrc="$PDK_ROOT/$PDK/libs.tech/xschem/xschemrc"
    if [ -f "$xrc" ]; then
        mkdir -p "$HOME/.xschem"
        ln -sf "$xrc" "$HOME/.xschem/xschemrc"
        ok "Xschem enlazado al xschemrc del PDK."
    else
        warn "No se encontro $xrc"
    fi

    # --- Dependencias Python del PDK ---
    if [ -f "$PDK_DIR/requirements.txt" ]; then
        pip3 install -r "$PDK_DIR/requirements.txt" --break-system-packages \
            || warn "Algunas dependencias Python fallaron (no siempre es critico)."
    fi
}

# =============================================================================
paso_7_verilog_a() {
    paso 7 "Compilando modelos Verilog-A (OSDI para NGSpice)"

    [ -f "$ENV_FILE" ] && . "$ENV_FILE"

    if ! command -v openvaf >/dev/null 2>&1; then
        err "OpenVAF no esta instalado. Corre primero: ./setup.sh 5"
        return 1
    fi

    local vadir="$PDK_ROOT/$PDK/libs.tech/verilog-a"
    [ -d "$vadir" ] || { err "No existe $vadir (¿corriste el paso 6?)"; return 1; }

    cd "$vadir" || return 1
    chmod +x openvaf-compile-va.sh
    # 'source' y no './' porque el script setea variables y crea el link a .spiceinit
    # shellcheck source=/dev/null
    source ./openvaf-compile-va.sh \
        || { err "Fallo la compilacion Verilog-A."; return 1; }

    if find "$PDK_ROOT/$PDK" -name 'psp103_nqs.osdi' | grep -q .; then
        ok "psp103_nqs.osdi generado correctamente."
    else
        warn "No se encontro psp103_nqs.osdi. Los MOSFET no van a simular."
    fi

    # .spiceinit permite simular circuitos del PDK desde cualquier directorio.
    # OJO: hay varios .spiceinit en el PDK (tests de gnucap, etc). El bueno es
    # el de libs.tech/ngspice, que es el que indica la documentacion del IHP.
    local si="$PDK_ROOT/$PDK/libs.tech/ngspice/.spiceinit"
    if [ -f "$si" ]; then
        ln -sf "$si" "$HOME/.spiceinit"
        ok ".spiceinit enlazado desde $si"
    else
        warn "No se encontro $si"
        warn "Vas a poder simular solo desde la carpeta que contenga los .osdi."
    fi

    return 0   # sin esto, el ultimo test define el codigo de salida de la funcion
}

# =============================================================================
verificar() {
    paso "V" "Verificacion final"

    [ -f "$ENV_FILE" ] && . "$ENV_FILE"

    local fallos=0
    # OJO: el paquete netgen-lvs instala el binario como 'netgen-lvs',
    # no como 'netgen' (ese nombre lo ocupa el mallador de elementos finitos).
    for t in git python3 ngspice klayout xschem magic netgen-lvs openvaf; do
        if command -v "$t" >/dev/null 2>&1; then
            printf "  %-10s %s\n" "$t" "$(command -v "$t")"
        else
            printf "  %-10s ${RED}NO ENCONTRADO${RST}\n" "$t"
            fallos=$((fallos+1))
        fi
    done

    echo
    echo "PDK_ROOT = ${PDK_ROOT:-(sin definir)}"
    echo "PDK      = ${PDK:-(sin definir)}"
    [ -d "${PDK_ROOT:-/nonexistent}/${PDK:-x}" ] && ok "PDK presente." || { err "PDK ausente."; fallos=$((fallos+1)); }

    find "${PDK_ROOT:-/nonexistent}" -name '*.osdi' 2>/dev/null | grep -q . \
        && ok "Modelos OSDI compilados." || { warn "Faltan los .osdi (paso 7)."; fallos=$((fallos+1)); }

    echo
    if [ "$fallos" -eq 0 ]; then
        echo "${GRN}Entorno VLSI verificado correctamente.${RST}"
        echo "Probá la interfaz grafica con:  xschem &"
    else
        echo "${YEL}Quedaron $fallos puntos por resolver (ver arriba).${RST}"
    fi
}

# =============================================================================
main() {
    local pasos=(paso_0_chequeos paso_1_dependencias paso_2_simuladores \
                 paso_3_klayout paso_4_xschem paso_5_openvaf \
                 paso_6_pdk paso_7_verilog_a)

    if [ "${1:-}" = "verify" ]; then verificar; return; fi

    local ini="${1:-0}" fin="${2:-7}"
    [ -n "${1:-}" ] && [ -z "${2:-}" ] && fin="$ini"   # ./setup.sh 3 -> solo el 3

    for i in $(seq "$ini" "$fin"); do
        if ! "${pasos[$i]}"; then
            echo
            err "El paso $i fallo. Corregi y reintentá con:  ./setup.sh $i"
            exit 1
        fi
    done

    verificar
    echo
    echo "${GRN}CERRA esta terminal y abrila de nuevo para cargar las variables.${RST}"
}

main "$@"
