# Mantenimiento y Limpieza de Windows

Script de mantenimiento para **Windows 10 y 11** escrito en PowerShell. Automatiza la limpieza segura de archivos temporales, cachés de navegadores y de aplicaciones, y tareas de mantenimiento básicas del sistema (verificación de disco, escaneo de Defender, optimización de unidad), con confirmación explícita para cualquier acción irreversible.

> **Versión:** 2.0 · **Requiere:** Windows 10/11 (detección automática), PowerShell 5.1+, permisos de Administrador (se solicitan automáticamente)

---

## Índice

- [¿Qué hace y qué no hace?](#qué-hace-y-qué-no-hace)
- [Características](#características)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Uso](#uso)
- [Parámetros](#parámetros)
- [Qué limpia el script](#qué-limpia-el-script)
- [Acciones opcionales con confirmación](#acciones-opcionales-con-confirmación)
- [Modo simulación (Dry Run)](#modo-simulación-dry-run)
- [Ejecución automática programada](#ejecución-automática-programada)
- [Seguridad y reversibilidad](#seguridad-y-reversibilidad)
- [Logs](#logs)
- [Actualizar desde una versión anterior](#actualizar-desde-una-versión-anterior)
- [Historial de versiones](#historial-de-versiones)
- [Aviso legal](#aviso-legal)
- [Licencia](#licencia)

---

## ¿Qué hace y qué no hace?

Este script se centra en **limpieza de disco y mantenimiento**, no en tocar el *scheduler* de CPU, prioridades de proceso o la gestión interna de memoria de Windows. Por eso se describe como "mantenimiento" y no como "optimización de rendimiento": es una distinción deliberada para no generar expectativas que el script no cumple.

Todas las operaciones están pensadas para ser **seguras por defecto**:
- No desactiva componentes críticos de Windows (Defender, Firewall, UAC, Windows Update, Secure Boot, etc.).
- No modifica servicios del sistema salvo detenciones temporales estrictamente necesarias para liberar una caché en uso (p. ej. `wuauserv` mientras se limpia la caché de Windows Update).
- Cualquier acción irreversible (borrar contraseñas guardadas, redes WiFi, `Windows.old`) requiere **confirmación explícita** del usuario y nunca se ejecuta en modo automático/silencioso.

## Características

- ✅ Detección automática de Windows 10/11, equipo portátil/escritorio, nivel de batería y reinicios pendientes.
- ✅ Punto de restauración de seguridad automático antes de cualquier cambio.
- ✅ Modo **Dry Run** (simulación): muestra qué se haría sin modificar nada.
- ✅ Reporte de espacio liberado, desglosado por categoría.
- ✅ Resumen final de todas las acciones y escaneos realizados.
- ✅ Logs con fecha y hora, con rotación automática (se conservan los 20 más recientes).
- ✅ Compatible con Chrome, Edge, Firefox y Brave — **nunca toca favoritos/marcadores**.
- ✅ Programación opcional de ejecución automática (semanal o mensual) vía Tarea Programada de Windows.
- ✅ Diagnóstico de solo lectura de servicios de terceros en inicio automático (no modifica nada, solo informa).

## Requisitos

- Windows 10 o Windows 11 (x64/ARM64).
- PowerShell 5.1 o superior (incluido de serie en Windows).
- Permisos de administrador (el script se autoeleva mediante UAC).

## Instalación

1. Descarga o clona este repositorio.
2. Asegúrate de que `Mantenimiento_Windows.ps1` y `Ejecutar_Mantenimiento.bat` estén en la **misma carpeta**.
3. Ejecuta `Ejecutar_Mantenimiento.bat` con doble clic, o lanza el script directamente desde PowerShell (ver [Uso](#uso)).

```bash
git clone https://github.com/<tu-usuario>/<tu-repositorio>.git
```

## Uso

### Modo interactivo (recomendado para la primera ejecución)

```powershell
.\Mantenimiento_Windows.ps1
```

Se te preguntará si quieres ejecutar en modo simulación, y se pedirá confirmación individual para cada acción sensible (contraseñas, redes WiFi, `Windows.old`, programas de inicio, apps en segundo plano).

### Modo silencioso (usado por la Tarea Programada)

```powershell
.\Mantenimiento_Windows.ps1 -Silent
```

Omite toda pregunta interactiva y todo lo que requiera confirmación manual (contraseñas, WiFi, `Windows.old`, programas de inicio, apps en segundo plano, diagnóstico de servicios).

### Modo silencioso mensual

```powershell
.\Mantenimiento_Windows.ps1 -Silent -Monthly
```

Igual que `-Silent`, pero además ejecuta `chkdsk /scan` y el escaneo rápido de Windows Defender (se omiten en la ejecución silenciosa semanal para no alargarla). En portátiles con batería baja y sin cargador conectado, estos dos pasos se omiten automáticamente incluso en modo mensual.

## Parámetros

| Parámetro  | Tipo    | Descripción |
|------------|---------|-------------|
| `-Silent`  | switch  | Ejecución desatendida, sin preguntas. Pensado para la Tarea Programada. |
| `-Monthly` | switch  | Indica que la ejecución silenciosa es la mensual (habilita chkdsk y el escaneo de Defender). Sin efecto si no se combina con `-Silent`. |

## Qué limpia el script

| Categoría | Detalle |
|---|---|
| Papelera de reciclaje | Vaciado completo |
| Archivos temporales | `%TEMP%`, `%WINDIR%\Temp`, `%LOCALAPPDATA%\Temp` |
| Caché de Windows Update | `SoftwareDistribution\Download` |
| Miniaturas y reportes de error | Caché de thumbnails, WER de usuario y de sistema |
| Navegadores | Caché, historial, cookies, autocompletado (Chrome, Edge, Brave, Firefox) — **favoritos nunca se tocan** |
| Microsoft Teams | Caché de la versión clásica y de la nueva (si están instaladas) |
| Microsoft Store | Caché (`wsreset.exe`) |
| Delivery Optimization | Caché de actualizaciones compartidas |
| Iconos y fuentes | Caché de iconos y de fuentes (soluciona iconos rotos/borrosos) |
| OneDrive | Solo logs internos de la app — nunca los archivos sincronizados |
| Portapapeles | Historial del portapapeles de Windows |
| Liberador de espacio (cleanmgr) | Perfil de limpieza configurado automáticamente (archivos temporales de instalación, volcados de memoria, logs de actualización, etc.) |

## Acciones opcionales con confirmación

Estas acciones **nunca** se ejecutan sin que el usuario lo apruebe explícitamente, y se omiten por completo en modo `-Silent`:

- Puntos de restauración de más de 1 año (se conserva al menos uno siempre).
- Carpetas de actualización antigua (`Windows.old`, `$Windows.~BT`, `$Windows.~WS`) — **eliminación permanente**, impide volver a la versión anterior de Windows.
- Programas que inician con Windows (deshabilitar, no desinstalar).
- Apps con permiso de ejecución en segundo plano (ahorro de CPU/RAM/batería).
- Verificación de disco (`chkdsk /scan`, de solo lectura).
- Escaneo rápido de Windows Defender.
- Contraseñas guardadas en navegadores — **eliminación permanente**.
- Perfiles de redes WiFi guardadas — **eliminación permanente**.

## Modo simulación (Dry Run)

Al ejecutar el script en modo interactivo, puedes elegir el modo **Dry Run**: se muestra exactamente qué se eliminaría o modificaría, incluyendo tamaños estimados en MB, **sin borrar ni cambiar nada real**. Útil para revisar el impacto antes de la primera ejecución real.

## Ejecución automática programada

Al final de una ejecución interactiva (sin `-Silent` ni Dry Run), el script ofrece programar su propia ejecución automática:

- **Semanal:** todos los domingos a las 20:00 (sin chkdsk ni Defender).
- **Mensual:** el día 1 de cada mes a las 20:00 (incluye chkdsk y Defender).

La tarea (`MantenimientoWindows` en el Programador de tareas de Windows) se crea para ejecutarse como `SYSTEM`, por lo que no depende de que el usuario tenga una sesión iniciada a esa hora. En la primera ejecución, el script se copia automáticamente a `C:\optimizer\` para que la tarea programada siempre use esa copia fija, sin importar desde dónde se ejecutó originalmente. Si detecta una tarea programada de una versión anterior del script, la elimina automáticamente antes de crear la nueva.

## Seguridad y reversibilidad

- Se crea un **punto de restauración del sistema** antes de cualquier cambio (si System Restore está disponible).
- Ninguna optimización desactiva Windows Defender, el Firewall, UAC, SmartScreen, Secure Boot ni la integridad de memoria.
- Las eliminaciones de shadow copies antiguas se filtran por contexto `ClientAccessible`, para no afectar copias usadas por software de backup de terceros.
- El diagnóstico de servicios de terceros es de **solo lectura**: lista lo que encuentra, pero no modifica ni desactiva nada automáticamente.

## Logs

Cada ejecución genera un log con fecha y hora en `C:\optimizer\LimpiezaWindows_Log_<timestamp>.txt`, y el resultado de `chkdsk` (si se ejecuta) en `ChkDsk_Resultado_<timestamp>.txt`. Se conservan automáticamente los 20 archivos más recientes de cada tipo; los más antiguos se purgan al inicio de cada ejecución.

## Actualizar desde una versión anterior

Si vienes de una versión anterior a la 2.0 (nombre de archivo `Limpiar_Optimizar_Windows11.ps1`), simplemente sustituye los archivos por los de este repositorio. La próxima vez que programes la ejecución automática, el script detectará y eliminará la tarea programada antigua (`LimpiezaOptimizacionWindows11`) automáticamente.

## Historial de versiones

Ver la cabecera de [`Mantenimiento_Windows.ps1`](Mantenimiento_Windows.ps1) para el changelog detallado de cada versión (1.5 a 2.0).

**Resumen de la v2.0:**
- Corrección de un filtro de seguridad en la eliminación de puntos de restauración antiguos.
- Corrección del paso de Liberador de espacio en disco, que antes no limpiaba nada por falta de configuración previa.
- Eliminada la limpieza de Prefetch (no aporta beneficio de rendimiento real).
- Tareas programadas creadas como `SYSTEM` para mayor fiabilidad.
- Nueva detección de entorno (versión de Windows, portátil/batería, reinicios pendientes).
- Nuevos pasos: gestión de apps en segundo plano y diagnóstico de servicios de terceros.
- Renombrado del proyecto para reflejar con precisión su alcance real.

## Aviso legal

Este script modifica archivos y configuración del sistema. Aunque incluye un punto de restauración automático, modo simulación y confirmaciones para toda acción irreversible, **se usa bajo tu propia responsabilidad**. Revisa el código antes de ejecutarlo y realiza una copia de seguridad de tus datos importantes si vas a usar las opciones de eliminación permanente (`Windows.old`, contraseñas, redes WiFi).

## Licencia

Sin licencia definida todavía. Si vas a publicar este repositorio, añade un archivo `LICENSE` (por ejemplo, MIT) para dejar claro cómo puede usarse y modificarse el código.

---

<sub>Desarrollado por TheMikeWare · kaelvior.online — con la asistencia de Claude (Anthropic).</sub>
