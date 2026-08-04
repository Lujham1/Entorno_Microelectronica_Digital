#!/bin/bash
set -e # Detiene el script si ocurre algún error

echo "========================================"
echo " Iniciando instalación del entorno VLSI "
echo "========================================"

# 1. Actualizar sistema e instalar dependencias
echo "[1/6] Instalando dependencias del sistema..."
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y build-essential git python3 python3-pip \
    libx11-6 libx11-dev libxrender1 libxrender-dev \
    libxcb1 libx11-xcb-dev libcairo2 libcairo2-dev \
    tcl8.6 tcl8.6-dev tk8.6 tk8.6-dev flex bison \
    libxpm4 libxpm-dev gawk wget curl magic netgen

# 2. Instalación de simulador (Ngspice) y KLayout
echo "[2/6] Instalando Ngspice y KLayout..."
sudo apt-get install -y ngspice klayout

# 3. Compilación e instalación de Xschem
echo "[3/6] Instalando Xschem desde el código fuente..."
cd ~
if [ ! -d "xschem" ]; then
    git clone https://github.com/StefanSchippers/xschem.git
fi
cd xschem
./configure
make -j$(nproc)
sudo make install

# 4. Descarga del PDK IHP SG13G2 (Open PDK)
echo "[4/6] Descargando IHP SG13G2 Open PDK..."
mkdir -p ~/pdk
cd ~/pdk
if [ ! -d "openPDK" ]; then
    git clone https://github.com/IHP-microelectronics/openPDK.git
fi

# 5. Configuración de KLayout para DRC y LVS (IHP SG13G2)
echo "[5/6] Configurando DRC y LVS en KLayout..."
# KLayout usa la carpeta 'salt' para cargar paquetes y tecnologías de forma nativa
mkdir -p ~/.klayout/salt
# Creamos un enlace simbólico desde el PDK hacia KLayout
ln -sfn ~/pdk/openPDK/ihp-sg13g2/libs.tech/klayout ~/.klayout/salt/ihp-sg13g2

# 6. Configuración del entorno de Xschem y variables
echo "[6/6] Configurando Xschem y variables de entorno..."
mkdir -p ~/.xschem
cp ~/pdk/openPDK/ihp-sg13g2/libs.tech/xschem/xschemrc ~/.xschem/

# Exportar PDK_ROOT en el bashrc para que las herramientas lo encuentren
if ! grep -q "PDK_ROOT" ~/.bashrc; then
    echo 'export PDK_ROOT=$HOME/pdk/openPDK' >> ~/.bashrc
    echo 'export IHP_TECH_DIR=$PDK_ROOT/ihp-sg13g2' >> ~/.bashrc
fi

echo "========================================"
echo " ¡Instalación completada con éxito!     "
echo " Cierra esta terminal y abre una nueva. "
echo "========================================"
