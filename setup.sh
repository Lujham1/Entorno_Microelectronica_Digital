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

echo "=========================================="
echo " [4/6] Descargando IHP SG13G2 Open PDK... "
echo "=========================================="
cd $HOME
# Borramos la carpeta si ya existe para evitar errores si un alumno reinstala
rm -rf $HOME/IHP-Open-PDK
# Clonado exacto como pide la documentación oficial
git clone --branch dev --recurse-submodules https://github.com/IHP-GmbH/IHP-Open-PDK.git


echo "=========================================="
echo " [5/6] Configurando variables de entorno  "
echo "=========================================="
# Inyectamos las rutas directamente en el .bashrc del alumno
echo 'export PDK_ROOT=$HOME/IHP-Open-PDK' >> ~/.bashrc
echo 'export PDK=ihp-sg13g2' >> ~/.bashrc
echo 'export KLAYOUT_PATH=$HOME/.klayout:$PDK_ROOT/$PDK/libs.tech/klayout' >> ~/.bashrc
echo 'export KLAYOUT_HOME=$HOME/.klayout' >> ~/.bashrc


echo "=========================================="
echo " [6/6] Instalando dependencias Python y   "
echo "       compilando modelos Verilog-A       "
echo "=========================================="
# Aseguramos que tengan pip instalado
sudo apt-get install python3-pip -y

# Instalamos los paquetes de Python que pide KLayout/IHP
# (El flag --break-system-packages es un salvavidas si usan Ubuntu 24.04)
pip3 install -r $HOME/IHP-Open-PDK/requirements.txt --break-system-packages

# Navegamos a la carpeta de Verilog-A y compilamos los modelos para NGSpice
cd $HOME/IHP-Open-PDK/ihp-sg13g2/libs.tech/verilog-a
chmod +x openvaf-compile-va.sh
./openvaf-compile-va.sh

echo "=========================================="
echo " ¡Entorno VLSI configurado con éxito! 🎉  "
echo "=========================================="
echo "Por favor, CIERRA esta ventana de terminal y vuelve a abrirla "
echo "para que se apliquen las nuevas variables de entorno."
