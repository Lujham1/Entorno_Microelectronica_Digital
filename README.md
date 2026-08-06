# Entorno de Microelectrónica Digital

Entorno de diseño VLSI para el cursado, con el PDK **IHP SG13G2** (BiCMOS 130 nm)
y todas las herramientas de código abierto necesarias para esquemático, simulación,
layout y verificación.

---

## Instalación

Abrí **PowerShell como Administrador** (`Win + X` → *Terminal (Administrador)*)
y pegá esta línea:

```powershell
irm https://raw.githubusercontent.com/Lujham1/Entorno_Microelectronica_Digital/main/install-wsl.ps1 | iex
```

Eso es todo. El proceso tarda entre **30 y 50 minutos** según tu conexión.
No cierres la ventana mientras trabaja.

### Requisitos

- Windows 10 (build 19045+) o Windows 11
- 15 GB libres en disco
- Conexión a internet estable

> **Si estás en la red de la facultad o usás VPN**: desactivá la VPN antes de
> empezar. Las descargas grandes suelen cortarse con el tráfico ruteado.

---

## Qué hace el instalador

El comando descarga y ejecuta `install-wsl.ps1`, que trabaja en dos etapas.

### Etapa 1 — Del lado de Windows (`install-wsl.ps1`)

| Paso | Qué hace | Por qué |
|------|----------|---------|
| 0 | Pide permisos de Administrador | WSL necesita privilegios para registrar una distro |
| 1 | Verifica y actualiza WSL | Se necesita WSL 2.4.8+ para poder darle nombre propio a la distro |
| 2 | Busca instalaciones previas | Si ya existe una distro con este nombre, avisa antes de borrarla |
| 2b | Escribe la configuración de la instancia | Crea el usuario y **blinda** la instalación contra configuraciones de otros entornos |
| 3 | Instala Ubuntu 24.04 | Con nombre `Microelectronica_Digital`, aislada de cualquier otra distro |
| 4 | Espera la configuración inicial | El usuario se crea de forma asincrónica; hay que esperarlo |
| 5 | Ejecuta `setup.sh` adentro | Instala todas las herramientas |
| 6 | Reinicia la distro | Para que se carguen las variables de entorno |

**Sobre el paso 2b**: Ubuntu para WSL lee configuración desde
`%USERPROFILE%\.cloud-init\`, y esa carpeta afecta a *todas* las distros nuevas
que crees. Si tenés otro entorno de otra materia instalado, su configuración se
colaría acá. Este paso escribe un archivo específico para esta instancia que
tiene prioridad, sin borrar la configuración de nadie más.

### Etapa 2 — Del lado de Linux (`setup.sh`)

| Paso | Qué instala | Tiempo aprox. |
|------|-------------|---------------|
| 0 | Chequeos previos | instantáneo |
| 1 | Dependencias del sistema (compiladores, X11, Tcl/Tk) | ~5 min |
| 2 | NGSpice, Magic, Netgen-LVS | ~2 min |
| 3 | KLayout 0.30.10 (`.deb` oficial) | ~2 min |
| 4 | Xschem (compilado desde fuente) | ~10 min |
| 5 | OpenVAF (compilador Verilog-A) | ~2 min |
| 6 | PDK IHP SG13G2 + variables de entorno | ~10 min |
| 7 | Compilación de los modelos Verilog-A | ~1 min |
| 8 | Aceleración gráfica | ~1 min |

---

## Las herramientas

| Herramienta | Para qué sirve |
|-------------|----------------|
| **Xschem** | Captura de esquemáticos. Es donde dibujás el circuito. |
| **NGSpice** | Simulador SPICE. Corre las simulaciones del esquemático. |
| **KLayout** | Editor y visor de layout. Incluye DRC y LVS del PDK. |
| **Magic** | Editor de layout alternativo, con extracción de parásitos. |
| **Netgen-LVS** | Comparación layout vs esquemático. |
| **OpenVAF** | Compila los modelos de transistor a formato OSDI. |

### Sobre el paso 7 (Verilog-A)

Los modelos de transistor del IHP (PSP103 para el MOSFET, `r3_cmc` para
resistores, y el varactor) se distribuyen como **código fuente Verilog-A** por
razones de licencia. NGSpice no los entiende directamente: hay que compilarlos
al formato **OSDI** con OpenVAF.

```
psp103_nqs.va  →  [OpenVAF]  →  psp103_nqs.osdi  →  [NGSpice lo carga]
   (fuente)                        (binario)
```

Sin este paso, **no se puede simular ningún transistor del PDK**.

Durante la compilación vas a ver tres *warnings* sobre `$simparam` en el modelo
`r3_cmc`. Son normales y le aparecen a todo el mundo: no afectan los resultados.

---

## Uso diario

Para entrar al entorno:

```powershell
wsl -d Microelectronica_Digital
```

Ya adentro:

```bash
xschem &        # esquemáticos
klayout -e &    # layout
ngspice         # simulador por consola
```

### Dónde guardar tu trabajo

Trabajá siempre dentro de tu carpeta personal de Linux (`~`), **no** en
`/mnt/c/...`. El acceso al disco de Windows desde WSL es mucho más lento y puede
triplicar los tiempos de compilación.

```bash
cd ~
mkdir mis_disenos
```

Para abrir esos archivos desde el Explorador de Windows, poné esto en la barra
de direcciones:

```
\\wsl$\Microelectronica_Digital\home\microelectronica_digital
```

### Variables de entorno

Quedan configuradas en `/etc/profile.d/vlsi-env.sh` y se cargan solas en cada
sesión:

```bash
echo $PDK_ROOT   # /home/microelectronica_digital/IHP-Open-PDK
echo $PDK        # ihp-sg13g2
```

Si alguna sale vacía, cerrá la terminal y abrila de nuevo.

---

## Verificación

Para confirmar que todo quedó bien:

```bash
cd ~
./setup.sh verify
```

Tenés que ver la ruta de cada herramienta y el mensaje
*"Entorno VLSI verificado correctamente"*.

---

## Problemas frecuentes

### La descarga de Ubuntu se cuelga

Casi siempre es una VPN (Tailscale, la VPN de la facultad) o un antivirus de
terceros. Desactivalos, corré `wsl --shutdown` y volvé a pegar la línea.

### Un paso falló

Cada paso se puede reintentar por separado sin rehacer todo:

```bash
cd ~
./setup.sh 4      # reintenta solo el paso 4
./setup.sh 4 8    # reintenta del 4 al 8
```

### Aparece un usuario que no es el mío

Si al entrar ves un usuario distinto de `microelectronica_digital`, es que hay
configuración de otro entorno en tu máquina. Revisá:

```powershell
dir $env:USERPROFILE\.cloud-init
```

### KLayout va lento

El paso 8 intenta activar la aceleración por GPU automáticamente, pero no todas
las máquinas la soportan. Si te tocó render por software, en KLayout andá a
**File → Setup → Display → Cells** y bajá *Max. hierarchy levels* a 3. Es lo que
más se nota.

### Las ventanas gráficas no abren

En Windows 11 no hace falta instalar nada: WSLg viene incluido. Probá primero:

```bash
xeyes
```

Si eso no abre, actualizá WSL con `wsl --update` desde PowerShell.

---

## Empezar de cero

Si querés reinstalar todo desde el principio:

```powershell
wsl --shutdown
wsl --unregister Microelectronica_Digital
```

Eso borra el entorno completo, incluyendo tus archivos. **Hacé una copia de tu
trabajo antes.** Después volvés a pegar la línea de instalación.

---

## Créditos

- [IHP Open PDK](https://github.com/IHP-GmbH/IHP-Open-PDK) — IHP GmbH
- [Xschem](https://github.com/StefanSchippers/xschem) — Stefan Schippers
- [KLayout](https://www.klayout.de) — Matthias Köfferlein
- [NGSpice](https://ngspice.sourceforge.io)
- [OpenVAF](https://openvaf.semimod.de) — SemiMod
