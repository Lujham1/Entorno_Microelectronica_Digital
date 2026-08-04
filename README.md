# Entorno_Microelectronica_Digital
# Configuración del Entorno

Esta guía te ayudará a configurar el entorno de desarrollo para Microelectrónica Digital con las herramientas open-source (KLayout, Xschem, Ngspice y el PDK de IHP).

## Requisitos Previos

* Sistema operativo basado en Linux o WSL (Ubuntu 24.04 recomendado).
  * En caso de usar Windows, el comando automatizado instalará WSL (Windows Subsystem for Linux) por ti, lo cual es suficiente para correr las herramientas.

---

## Configuración del Entorno

### 1. Instalación Automatizada

Esta sección provee comandos únicos para instalar dependencias, clonar el repositorio y ejecutar el script de configuración sin requerir interacción manual durante el proceso.

**Windows (PowerShell)**

Abre **PowerShell como Administrador** y pega este único comando — instalará WSL + Ubuntu y configurará todo el entorno de diseño automáticamente:

```powershell
irm [https://raw.githubusercontent.com/Lujham1/Entorno_Microelectronica_Digital/refs/heads/main/install-wsl.ps1](https://raw.githubusercontent.com/Lujham1/Entorno_Microelectronica_Digital/refs/heads/main/install-wsl.ps1) | iex
