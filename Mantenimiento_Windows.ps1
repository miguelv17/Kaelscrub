# ============================================================
#
#   MANTENIMIENTO Y LIMPIEZA DE WINDOWS
#   ---------------------------------------------------------
#   Version:      2.0
#   Fecha:        2026-09-08
#   Requiere:     Windows 10 o 11 (deteccion automatica),
#                 PowerShell 5.1 o superior
#   Permisos:     Administrador (se solicitan automaticamente)
#
#   DESCRIPCION:
#   Script de mantenimiento que limpia archivos temporales,
#   papelera de reciclaje, cache de Windows Update, miniaturas,
#   navegadores (Chrome/Edge/Firefox/Brave), Microsoft Teams,
#   Tienda Windows, Delivery Optimization, iconos/fuentes,
#   OneDrive y portapapeles. Ademas gestiona de forma opcional
#   y con confirmacion: puntos de restauracion antiguos (+1 ano),
#   Windows.old, programas de inicio, apps en segundo plano,
#   contrasenas guardadas en navegadores y perfiles de redes WiFi.
#   Incluye verificacion de errores de disco (chkdsk /scan, solo
#   lectura), un escaneo rapido de Windows Defender y un diagnostico
#   de solo lectura de servicios de terceros en inicio automatico.
#   Al finalizar, muestra el espacio total en disco recuperado y un
#   desglose por categoria.
#
#   NOTA SOBRE EL NOMBRE: este script limpia y mantiene el sistema
#   (espacio en disco, cachés, arranque, procesos en segundo plano).
#   No modifica el scheduler de CPU, prioridades de proceso ni la
#   gestion de memoria de Windows, por lo que se describe como
#   "mantenimiento" y no como "optimizacion" de rendimiento.
#
#   NUEVO EN v1.5:
#   - Crea automaticamente un Punto de Restauracion de seguridad
#     ANTES de limpiar (si System Restore esta disponible).
#   - Modo SIMULACION (Dry Run): muestra que se eliminaria sin
#     borrar nada realmente.
#   - Reporte detallado de espacio liberado por categoria.
#   - Logs con fecha y hora en el nombre (no se sobrescriben).
#   - Opcion de programar el script para ejecutarse solo de
#     forma semanal o mensual (Tarea Programada de Windows).
#
#   NUEVO EN v1.6:
#   - En la primera ejecucion, el script se copia automaticamente
#     a C:\optimizer\ (con su nombre de archivo actual). Si programas
#     la tarea automatica, siempre se ejecutara desde esa copia fija,
#     sin importar desde donde corriste el script originalmente.
#   - La ejecucion automatica (semanal o mensual) queda programada
#     a las 8:00 PM.
#
#   NUEVO EN v1.7:
#   - Resumen final de ESCANEOS Y OPTIMIZACIONES: punto de
#     restauracion, chkdsk, Defender, cleanmgr, DNS, TRIM,
#     puntos de restauracion antiguos, Windows.old, programas
#     de inicio, contrasenas y redes WiFi. Se muestra antes del
#     detalle de espacio por categoria.
#
#   NUEVO EN v1.8:
#   - chkdsk /scan y el escaneo de Windows Defender ahora
#     preguntan confirmacion individual antes de ejecutarse
#     (en modo interactivo). Se omiten automaticamente en modo
#     Silencioso o Simulacion.
#
#   NUEVO EN v1.9:
#   - En la ejecucion silenciosa MENSUAL (tarea programada con
#     -Monthly), chkdsk /scan y el escaneo de Defender se
#     ejecutan automaticamente sin preguntar. En la ejecucion
#     silenciosa SEMANAL, se siguen omitiendo (para no alargar
#     la tarea semanal).
#
#   NUEVO EN v2.0 (tras auditoria tecnica):
#   - Se elimina la limpieza de Prefetch (no aporta rendimiento
#     real; Windows lo gestiona automaticamente).
#   - Los puntos de restauracion antiguos ahora se filtran por
#     contexto ClientAccessible, para no afectar shadow copies
#     usadas por software de backup de terceros.
#   - El Liberador de espacio en disco (cleanmgr /sagerun:1) ahora
#     configura su propio perfil de limpieza antes de ejecutarse,
#     en vez de depender de un perfil preexistente que normalmente
#     no existe (lo cual hacia que el paso no limpiara nada).
#   - La tarea programada (semanal/mensual) ahora se crea para
#     ejecutarse como SYSTEM, evitando que dependa de que el
#     usuario tenga sesion iniciada a esa hora.
#   - Se elimina el $ErrorActionPreference global "SilentlyContinue":
#     cada operacion maneja sus propios errores explicitamente,
#     para no ocultar fallos reales.
#   - Deteccion de entorno: version de Windows, portatil/bateria y
#     reinicio pendiente de Windows Update, mostrados en el resumen.
#   - Nuevo paso: revision (con confirmacion) de apps UWP con
#     permiso de ejecucion en segundo plano.
#   - Nuevo paso: diagnostico (solo lectura, sin cambios) de
#     servicios de terceros configurados en inicio automatico.
#   - Rotacion de logs propios en C:\optimizer (se conservan los
#     20 mas recientes).
#   - Se renombra el script (antes "Limpiar_Optimizar_Windows11.ps1")
#     a "Mantenimiento_Windows.ps1": el nombre anterior sugeria una
#     optimizacion de rendimiento (CPU/RAM) que el script no realiza,
#     y limitaba el nombre a Windows 11 pese a funcionar tambien en
#     Windows 10 (ahora detectado automaticamente).
#
#   USO:
#     .\Mantenimiento_Windows.ps1            (modo normal, interactivo)
#     .\Mantenimiento_Windows.ps1 -Silent    (modo automatico/desatendido,
#                                                    usado por la Tarea Programada;
#                                                    omite todo lo que requiere
#                                                    confirmacion manual)
#
#   NOTA SOBRE SSD:
#   Todas las operaciones son seguras para unidades de estado
#   solido. Optimize-Volume ejecuta TRIM (no desfragmentacion)
#   en SSD, y chkdsk /scan + el escaneo de Defender son
#   mayormente de LECTURA, sin desgaste relevante en la unidad.
#
#   CREDITOS:
#   Desarrollado con la asistencia de Claude (Anthropic)
#   a partir de los requerimientos del usuario.
#   Uso bajo tu propia responsabilidad - sin garantia alguna.
#
# ============================================================

param(
    [switch]$Silent,   # Modo desatendido: usado por la Tarea Programada, omite prompts
    [switch]$Monthly   # Indica que la ejecucion silenciosa proviene de la tarea MENSUAL
                       # (habilita chkdsk y el escaneo de Defender automaticamente)
)

# --- Auto-elevacion a administrador ---
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Solicitando permisos de administrador..." -ForegroundColor Yellow
    $extraArgs = ""
    if ($Silent) { $extraArgs += " -Silent" }
    if ($Monthly) { $extraArgs += " -Monthly" }
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $extraArgs" -Verb RunAs
    exit
}

# Nota (v2.0): ya no se fuerza $ErrorActionPreference = "SilentlyContinue" a nivel
# global. Cada operacion que puede fallar de forma esperada usa su propio
# -ErrorAction SilentlyContinue o un bloque try/catch, para no ocultar errores
# reales en operaciones que no los manejan explicitamente.
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

# --- Carpeta fija del script y de sus logs: C:\optimizer ---
$optimizerDir = "C:\optimizer"
if (-not (Test-Path $optimizerDir)) {
    New-Item -Path $optimizerDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

$logFile = "$optimizerDir\LimpiezaWindows_Log_$timestamp.txt"
"Inicio de limpieza: $(Get-Date)" | Out-File $logFile

function Log($msg) {
    Write-Host $msg -ForegroundColor Cyan
    $msg | Out-File $logFile -Append
}

# --- Rotacion de logs propios: conserva solo los 20 mas recientes de cada tipo ---
function Invoke-LogRotation {
    param([int]$Keep = 20)
    foreach ($pattern in @("LimpiezaWindows_Log_*.txt", "ChkDsk_Resultado_*.txt")) {
        Get-ChildItem -Path $optimizerDir -Filter $pattern -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $Keep |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}
Invoke-LogRotation

function Get-FolderSizeMB($path) {
    if (Test-Path $path) {
        $size = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        return [math]::Round($size / 1MB, 2)
    }
    return 0
}

# --- Copiar el script a una ubicacion estable (C:\optimizer) en la primera ejecucion ---
# Esto asegura que la Tarea Programada (semanal/mensual) siempre tenga una copia
# fija del script, sin importar desde donde el usuario lo ejecuto originalmente.
# NOTA (v2.0): antes el nombre iba hardcodeado; se deriva del nombre real del
# script para no romper esta referencia si el archivo se vuelve a renombrar.
$stableScriptPath = Join-Path $optimizerDir (Split-Path -Leaf $PSCommandPath)
try {
    if (-not (Test-Path $stableScriptPath) -and $PSCommandPath -ne $stableScriptPath) {
        Copy-Item -Path $PSCommandPath -Destination $stableScriptPath -Force -ErrorAction Stop
        Log "Primera ejecucion detectada: copia del script guardada en $stableScriptPath (se usara para la tarea programada)."
    }
} catch {
    Log "No se pudo copiar el script a $optimizerDir (la programacion automatica podria no estar disponible)."
}

$TotalSteps = 21
function Step-Progress($Number, $Message) {
    $percent = [math]::Round(($Number / $TotalSteps) * 100)
    Write-Progress -Activity "Mantenimiento y Limpieza de Windows" -Status "[$Number/$TotalSteps] $Message ($percent%)" -PercentComplete $percent
    Log "`n[$Number/$TotalSteps] $Message"
}

# --- Reporte de espacio liberado por categoria ---
$script:SpaceReport = [ordered]@{}

function Add-SpaceReport($Category, $MB) {
    if ($MB -le 0) { return }
    if (-not $script:SpaceReport.Contains($Category)) { $script:SpaceReport[$Category] = 0 }
    $script:SpaceReport[$Category] += $MB
}

# --- Resumen final de escaneos, optimizaciones y acciones relevantes ---
$script:Summary = New-Object System.Collections.Generic.List[string]
function Add-Summary($Text) {
    $script:Summary.Add($Text)
}

# --- Deteccion de entorno (v2.0): version de Windows, portatil/bateria, reinicio pendiente ---
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$buildNumber = [int]($osInfo.BuildNumber)
$script:WinVersionLabel = if ($buildNumber -ge 22000) { "Windows 11 (build $buildNumber)" }
                          elseif ($buildNumber -gt 0) { "Windows 10 (build $buildNumber)" }
                          else { "Version de Windows no detectada" }

$batteryInfo = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
$script:IsLaptop = [bool]$batteryInfo
$script:OnBattery = $false
$script:BatteryPercent = $null
if ($batteryInfo) {
    $script:BatteryPercent = $batteryInfo | Select-Object -First 1 -ExpandProperty EstimatedChargeRemaining -ErrorAction SilentlyContinue
    # BatteryStatus 1 = descargando (con bateria, sin cargador conectado)
    $script:OnBattery = ($batteryInfo | Select-Object -First 1 -ExpandProperty BatteryStatus -ErrorAction SilentlyContinue) -eq 1
}

$rebootKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
)
$script:PendingReboot = $false
foreach ($rk in $rebootKeys) {
    if (Test-Path $rk -ErrorAction SilentlyContinue) { $script:PendingReboot = $true }
}

Log "Entorno detectado: $script:WinVersionLabel"
Add-Summary "Entorno: $script:WinVersionLabel."
if ($script:IsLaptop) {
    $bateriaTxt = if ($null -ne $script:BatteryPercent) { "$($script:BatteryPercent)%" } else { "desconocido" }
    $fuenteTxt = if ($script:OnBattery) { "con bateria (sin cargador)" } else { "conectado a corriente" }
    Log "Equipo portatil detectado - bateria: $bateriaTxt, $fuenteTxt."
    Add-Summary "Equipo portatil: bateria $bateriaTxt, $fuenteTxt."
} else {
    Add-Summary "Equipo de escritorio (o sin bateria detectada)."
}
if ($script:PendingReboot) {
    Log "AVISO: Windows tiene un reinicio pendiente (actualizacion u operacion de archivos)."
    Add-Summary "Reinicio pendiente de Windows: SI - se recomienda reiniciar el equipo pronto."
} else {
    Add-Summary "Reinicio pendiente de Windows: no detectado."
}

# En ejecucion silenciosa mensual con el portatil en bateria y carga baja, se evitan
# chkdsk y el escaneo de Defender (pueden tardar varios minutos y consumir CPU/disco).
$script:SkipHeavyScansOnBattery = $script:IsLaptop -and $script:OnBattery -and ($null -ne $script:BatteryPercent) -and ($script:BatteryPercent -lt 30)

# Wrapper de limpieza: mide el tamano ANTES de borrar (para el reporte),
# y respeta el modo Dry Run (simulacion) sin eliminar nada realmente.
function Invoke-Clean {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Category,
        [switch]$Recurse
    )
    $sizeMB = 0
    try {
        $matched = Get-Item -Path $Path -Force -ErrorAction SilentlyContinue
        if ($matched) {
            $sum = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if (-not $sum) { $sum = ($matched | Measure-Object -Property Length -Sum).Sum }
            if ($sum) { $sizeMB = [math]::Round($sum / 1MB, 2) }
        }
    } catch { }

    if ($sizeMB -gt 0) { Add-SpaceReport -Category $Category -MB $sizeMB }

    if ($DryRun) {
        if ($sizeMB -gt 0) {
            Log "  [SIMULACION] Se eliminaria (~$sizeMB MB): $Path"
        }
        return
    }

    if ($Recurse) {
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Remove-Item $Path -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "=========================================" -ForegroundColor Green
Write-Host "  MANTENIMIENTO Y LIMPIEZA DE WINDOWS" -ForegroundColor Green
Write-Host "  Version 2.0  |  $(Get-Date -Format 'yyyy-MM-dd')" -ForegroundColor Green
Write-Host "  Desarrollado por TheMikeWare" -ForegroundColor DarkGray
Write-Host "  kaelvior.online" -ForegroundColor DarkGray
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""

# --- Preguntar modo Dry Run (solo si es interactivo, no en ejecucion silenciosa) ---
if (-not $Silent) {
    Write-Host "Puedes ejecutar en modo SIMULACION: se mostrara todo lo que" -ForegroundColor Yellow
    Write-Host "se haria/eliminaria, SIN borrar ni cambiar nada realmente." -ForegroundColor Yellow
    $dryRunResp = Read-Host "Ejecutar en modo SIMULACION (Dry Run)? (S/N)"
    $DryRun = $dryRunResp -match "^[SsYy]"
} else {
    $DryRun = $false
}

if ($DryRun) {
    Write-Host "`n>>> MODO SIMULACION ACTIVADO: no se eliminara ni cambiara nada. <<<`n" -ForegroundColor Magenta
    Log "MODO SIMULACION (Dry Run) ACTIVADO - no se realizan cambios reales."
}

# --- Capturar espacio usado en disco ANTES de limpiar (para mostrar espacio recuperado al final) ---
$driveC = Get-PSDrive C -ErrorAction SilentlyContinue
$usedBefore = if ($driveC) { $driveC.Used } else { 0 }
$freeBefore = if ($driveC) { $driveC.Free } else { 0 }

# --- Punto de Restauracion de seguridad ANTES de limpiar ---
if (-not $DryRun) {
    Log "`n[Preparacion] Creando punto de restauracion de seguridad..."
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Antes de Mantenimiento y Limpieza de Windows" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Log "  -> Punto de restauracion creado correctamente."
        Add-Summary "Punto de restauracion de seguridad: creado correctamente."
    } catch {
        Log "  -> No se pudo crear el punto de restauracion (puede que ya se haya creado uno en las ultimas 24h, o que System Restore este deshabilitado)."
        Add-Summary "Punto de restauracion de seguridad: no se pudo crear (puede que ya exista uno reciente)."
    }
} else {
    Log "`n[Preparacion] Modo simulacion: no es necesario crear un punto de restauracion."
}

# --- 1. Cerrar navegadores comunes (necesario para liberar sus caches) ---
Step-Progress -Number 1 -Message "Cerrando navegadores abiertos..."
$browsers = "chrome","msedge","firefox","brave","opera"
if (-not $DryRun) {
    foreach ($b in $browsers) {
        Stop-Process -Name $b -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
} else {
    Log "  [SIMULACION] Se cerrarian los navegadores abiertos."
}

# --- 2. Vaciar la Papelera de Reciclaje ---
Step-Progress -Number 2 -Message "Vaciando la Papelera de Reciclaje..."
try {
    $shell = New-Object -ComObject Shell.Application
    $recycleBin = $shell.NameSpace(0xA)
    $binSizeMB = 0
    if ($recycleBin) {
        $binSizeMB = [math]::Round((($recycleBin.Items() | ForEach-Object { $_.Size }) | Measure-Object -Sum).Sum / 1MB, 2)
    }
    if ($binSizeMB -gt 0) { Add-SpaceReport -Category "Papelera de Reciclaje" -MB $binSizeMB }

    if ($DryRun) {
        Log "  [SIMULACION] Se vaciaria la papelera (~$binSizeMB MB)."
    } else {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Log "  -> Papelera vaciada correctamente (~$binSizeMB MB liberados)."
    }
} catch {
    Log "  -> No se pudo vaciar automaticamente (puede que ya este vacia)."
}

# --- 3. Archivos temporales del sistema y del usuario ---
Step-Progress -Number 3 -Message "Eliminando archivos temporales..."
$tempPaths = @(
    "$env:TEMP\*",
    "$env:WINDIR\Temp\*",
    "$env:LOCALAPPDATA\Temp\*"
    # NOTA (v2.0): se retiro $env:WINDIR\Prefetch\* de esta lista. Prefetch es
    # gestionado automaticamente por Windows para acelerar el arranque de apps
    # frecuentes; borrarlo no libera espacio relevante y solo penaliza la
    # siguiente ejecucion de cada programa (mito de optimizacion sin beneficio real).
)
foreach ($p in $tempPaths) {
    Invoke-Clean -Path $p -Category "Archivos Temporales" -Recurse
    Log "  -> Procesado: $p"
}

# --- 4. Cache de Windows Update ---
Step-Progress -Number 4 -Message "Limpiando cache de Windows Update..."
if (-not $DryRun) { Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue }
Invoke-Clean -Path "$env:WINDIR\SoftwareDistribution\Download\*" -Category "Cache de Windows Update" -Recurse
if (-not $DryRun) { Start-Service -Name wuauserv -ErrorAction SilentlyContinue }
Log "  -> Cache de Windows Update procesada."

# --- 5. Miniaturas y reportes de errores ---
Step-Progress -Number 5 -Message "Limpiando cache de miniaturas y reportes de error..."
Invoke-Clean -Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Category "Miniaturas y Reportes de Error"
Invoke-Clean -Path "$env:LOCALAPPDATA\Microsoft\Windows\WER\*" -Category "Miniaturas y Reportes de Error" -Recurse
Invoke-Clean -Path "$env:PROGRAMDATA\Microsoft\Windows\WER\*" -Category "Miniaturas y Reportes de Error" -Recurse

# --- 6. Cache de navegadores (limpieza profunda, SIN tocar favoritos/marcadores) ---
Step-Progress -Number 6 -Message "Limpiando navegadores (cache, historial, cookies) - favoritos NO se tocan..."

# Google Chrome
$chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
if (Test-Path $chromePath) {
    Invoke-Clean -Path "$chromePath\Cache\*" -Category "Chrome" -Recurse
    Invoke-Clean -Path "$chromePath\Cache2\*" -Category "Chrome" -Recurse
    Invoke-Clean -Path "$chromePath\Code Cache\*" -Category "Chrome" -Recurse
    Invoke-Clean -Path "$chromePath\GPUCache\*" -Category "Chrome" -Recurse
    Invoke-Clean -Path "$chromePath\Network\Cache\*" -Category "Chrome" -Recurse
    Invoke-Clean -Path "$chromePath\Service Worker\CacheStorage\*" -Category "Chrome" -Recurse
    Invoke-Clean -Path "$chromePath\History" -Category "Chrome"
    Invoke-Clean -Path "$chromePath\History-journal" -Category "Chrome"
    Invoke-Clean -Path "$chromePath\Network\Cookies" -Category "Chrome"
    Invoke-Clean -Path "$chromePath\Web Data" -Category "Chrome"
    Invoke-Clean -Path "$chromePath\Web Data-journal" -Category "Chrome"
    Invoke-Clean -Path "$chromePath\Favicons" -Category "Chrome"
    Invoke-Clean -Path "$chromePath\Sessions\*" -Category "Chrome" -Recurse
    Invoke-Clean -Path "$chromePath\Visited Links" -Category "Chrome"
    # NOTA: "Bookmarks" y "Bookmarks.bak" NO se tocan, para conservar los favoritos
    Log "  -> Chrome: cache, historial, cookies y autocompletado procesados (favoritos conservados)."
}

# Microsoft Edge
$edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
if (Test-Path $edgePath) {
    Invoke-Clean -Path "$edgePath\Cache\*" -Category "Edge" -Recurse
    Invoke-Clean -Path "$edgePath\Cache2\*" -Category "Edge" -Recurse
    Invoke-Clean -Path "$edgePath\Code Cache\*" -Category "Edge" -Recurse
    Invoke-Clean -Path "$edgePath\GPUCache\*" -Category "Edge" -Recurse
    Invoke-Clean -Path "$edgePath\Network\Cache\*" -Category "Edge" -Recurse
    Invoke-Clean -Path "$edgePath\Service Worker\CacheStorage\*" -Category "Edge" -Recurse
    Invoke-Clean -Path "$edgePath\History" -Category "Edge"
    Invoke-Clean -Path "$edgePath\History-journal" -Category "Edge"
    Invoke-Clean -Path "$edgePath\Network\Cookies" -Category "Edge"
    Invoke-Clean -Path "$edgePath\Web Data" -Category "Edge"
    Invoke-Clean -Path "$edgePath\Web Data-journal" -Category "Edge"
    Invoke-Clean -Path "$edgePath\Favicons" -Category "Edge"
    Invoke-Clean -Path "$edgePath\Sessions\*" -Category "Edge" -Recurse
    Invoke-Clean -Path "$edgePath\Visited Links" -Category "Edge"
    # NOTA: "Bookmarks" y "Bookmarks.bak" NO se tocan
    Log "  -> Edge: cache, historial, cookies y autocompletado procesados (favoritos conservados)."
}

# Mozilla Firefox
# NOTA: Firefox guarda favoritos E historial juntos en "places.sqlite", por lo que
# ese archivo NO se toca para no arriesgar los favoritos. Se limpian solo los
# archivos que son exclusivamente cache/cookies/formularios/sesiones.
$firefoxProfiles = "$env:APPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $firefoxProfiles) {
    Get-ChildItem $firefoxProfiles -Directory | ForEach-Object {
        $prof = $_.FullName
        Invoke-Clean -Path "$prof\cache2\*" -Category "Firefox" -Recurse
        Invoke-Clean -Path "$prof\startupCache\*" -Category "Firefox" -Recurse
        Invoke-Clean -Path "$prof\cookies.sqlite" -Category "Firefox"
        Invoke-Clean -Path "$prof\cookies.sqlite-wal" -Category "Firefox"
        Invoke-Clean -Path "$prof\formhistory.sqlite" -Category "Firefox"
        Invoke-Clean -Path "$prof\downloads.sqlite" -Category "Firefox"
        Invoke-Clean -Path "$prof\sessionstore.jsonlz4" -Category "Firefox"
        Invoke-Clean -Path "$prof\sessionstore-backups\*" -Category "Firefox" -Recurse
        Invoke-Clean -Path "$prof\webappsstore.sqlite" -Category "Firefox"
        Invoke-Clean -Path "$prof\favicons.sqlite" -Category "Firefox"
        # places.sqlite (favoritos + historial combinados) NO se elimina
    }
    Log "  -> Firefox: cache, cookies, sesiones y formularios procesados (favoritos conservados)."
    Log "     (el historial de navegacion de Firefox se conserva junto con los favoritos,"
    Log "      ya que ambos comparten el mismo archivo interno)."
}

# Brave
$bravePath = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
if (Test-Path $bravePath) {
    Invoke-Clean -Path "$bravePath\Cache\*" -Category "Brave" -Recurse
    Invoke-Clean -Path "$bravePath\Cache2\*" -Category "Brave" -Recurse
    Invoke-Clean -Path "$bravePath\Code Cache\*" -Category "Brave" -Recurse
    Invoke-Clean -Path "$bravePath\GPUCache\*" -Category "Brave" -Recurse
    Invoke-Clean -Path "$bravePath\Network\Cache\*" -Category "Brave" -Recurse
    Invoke-Clean -Path "$bravePath\History" -Category "Brave"
    Invoke-Clean -Path "$bravePath\History-journal" -Category "Brave"
    Invoke-Clean -Path "$bravePath\Network\Cookies" -Category "Brave"
    Invoke-Clean -Path "$bravePath\Web Data" -Category "Brave"
    Invoke-Clean -Path "$bravePath\Web Data-journal" -Category "Brave"
    Invoke-Clean -Path "$bravePath\Favicons" -Category "Brave"
    Invoke-Clean -Path "$bravePath\Sessions\*" -Category "Brave" -Recurse
    # NOTA: "Bookmarks" y "Bookmarks.bak" NO se tocan
    Log "  -> Brave: cache, historial, cookies y autocompletado procesados (favoritos conservados)."
}

# --- 7. Cache de Microsoft Teams (si esta presente) ---
Step-Progress -Number 7 -Message "Buscando Microsoft Teams..."
$teamsFound = $false

$teamsClassicPath = "$env:APPDATA\Microsoft\Teams"
if (Test-Path $teamsClassicPath) {
    $teamsFound = $true
    Log "  -> Microsoft Teams (clasico) detectado."
    if (-not $DryRun) {
        Stop-Process -Name "Teams" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    $teamsSubfolders = "Cache","GPUCache","Code Cache","blob_storage","Local Storage\leveldb","IndexedDB","tmp"
    foreach ($sub in $teamsSubfolders) {
        Invoke-Clean -Path "$teamsClassicPath\$sub\*" -Category "Microsoft Teams" -Recurse
    }
    Log "  -> Cache de Teams (clasico) procesada."
}

$teamsNewPath = "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"
if (Test-Path $teamsNewPath) {
    $teamsFound = $true
    Log "  -> Microsoft Teams (nuevo) detectado."
    if (-not $DryRun) {
        Stop-Process -Name "ms-teams" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    Invoke-Clean -Path "$teamsNewPath\EBWebView\Default\Cache\*" -Category "Microsoft Teams" -Recurse
    Invoke-Clean -Path "$teamsNewPath\EBWebView\Default\Code Cache\*" -Category "Microsoft Teams" -Recurse
    Log "  -> Cache de Teams (nuevo) procesada."
}

if (-not $teamsFound) {
    Log "  -> Microsoft Teams no esta instalado, se omite este paso."
    Add-Summary "Microsoft Teams: no instalado."
} else {
    Add-Summary "Microsoft Teams: cache procesada."
}

# --- 8. Cache de la Tienda Windows (Microsoft Store) ---
Step-Progress -Number 8 -Message "Limpiando cache de la Tienda Windows (Microsoft Store)..."
if ($DryRun) {
    Log "  [SIMULACION] Se ejecutaria wsreset.exe para limpiar la cache de la Tienda Windows."
    Add-Summary "Tienda Windows (Microsoft Store): omitido en modo simulacion."
} else {
    try {
        Start-Process -FilePath "wsreset.exe" -WindowStyle Hidden -Wait -ErrorAction Stop
        Log "  -> Cache de la Tienda Windows eliminada correctamente."
        Add-Summary "Tienda Windows (Microsoft Store): cache limpiada correctamente."
    } catch {
        Log "  -> No se pudo ejecutar wsreset.exe (puede no estar disponible en este equipo)."
        Add-Summary "Tienda Windows (Microsoft Store): no se pudo ejecutar wsreset.exe."
    }
}

# --- 9. Cache de Delivery Optimization (actualizaciones descargadas/compartidas) ---
Step-Progress -Number 9 -Message "Limpiando cache de Delivery Optimization..."
$doPath = "$env:WINDIR\SoftwareDistribution\DeliveryOptimization"
$doSizeMB = Get-FolderSizeMB $doPath
if ($doSizeMB -gt 0) { Add-SpaceReport -Category "Delivery Optimization" -MB $doSizeMB }

if ($DryRun) {
    Log "  [SIMULACION] Se eliminaria la cache de Delivery Optimization (~$doSizeMB MB)."
    Add-Summary "Delivery Optimization: omitido en modo simulacion (~$doSizeMB MB detectados)."
} else {
    try {
        Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
        Log "  -> Cache de Delivery Optimization eliminada (~$doSizeMB MB)."
        Add-Summary "Delivery Optimization: cache eliminada (~$doSizeMB MB)."
    } catch {
        try {
            Stop-Service -Name dosvc -Force -ErrorAction SilentlyContinue
            Remove-Item "$doPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service -Name dosvc -ErrorAction SilentlyContinue
            Log "  -> Cache de Delivery Optimization eliminada (metodo alternativo, ~$doSizeMB MB)."
            Add-Summary "Delivery Optimization: cache eliminada, metodo alternativo (~$doSizeMB MB)."
        } catch {
            Log "  -> No se pudo limpiar la cache de Delivery Optimization."
            Add-Summary "Delivery Optimization: no se pudo limpiar."
        }
    }
}

# --- 10. Cache de iconos y fuentes (soluciona iconos rotos/borrosos) ---
Step-Progress -Number 10 -Message "Limpiando cache de iconos y fuentes..."
$iconFontSizeMB = (Get-FolderSizeMB "$env:LOCALAPPDATA\Microsoft\Windows\Explorer") +
                  (Get-FolderSizeMB "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache")
if ($iconFontSizeMB -gt 0) { Add-SpaceReport -Category "Cache de Iconos y Fuentes" -MB $iconFontSizeMB }

if ($DryRun) {
    Log "  [SIMULACION] Se limpiaria la cache de iconos y fuentes (~$iconFontSizeMB MB) y se reiniciaria el Explorador."
    Add-Summary "Cache de iconos y fuentes: omitido en modo simulacion."
} else {
    try {
        Stop-Process -ProcessName explorer -Force -ErrorAction SilentlyContinue
        Stop-Service -Name FontCache -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1

        Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache\*.dat" -Force -ErrorAction SilentlyContinue

        Start-Service -Name FontCache -ErrorAction SilentlyContinue
        Start-Process explorer.exe
        Log "  -> Cache de iconos y fuentes eliminada (el escritorio se reinicio brevemente)."
        Add-Summary "Cache de iconos y fuentes: limpiada correctamente."
    } catch {
        Log "  -> No se pudo limpiar completamente la cache de iconos/fuentes."
        Add-Summary "Cache de iconos y fuentes: no se pudo limpiar por completo."
        Start-Process explorer.exe -ErrorAction SilentlyContinue
    }
}

# --- 11. Cache de OneDrive (si esta presente) ---
Step-Progress -Number 11 -Message "Buscando OneDrive..."
$oneDrivePath = "$env:LOCALAPPDATA\Microsoft\OneDrive"
if (Test-Path $oneDrivePath) {
    Log "  -> OneDrive detectado."
    # Solo se limpian logs y cache interna de la app, NUNCA los archivos sincronizados del usuario
    Invoke-Clean -Path "$oneDrivePath\logs\*" -Category "OneDrive (logs)" -Recurse
    Invoke-Clean -Path "$oneDrivePath\setup\logs\*" -Category "OneDrive (logs)" -Recurse
    Log "  -> Logs y archivos temporales de OneDrive procesados (tus archivos sincronizados no se tocan)."
} else {
    Log "  -> OneDrive no esta instalado, se omite este paso."
}

# --- 12. Historial del portapapeles de Windows ---
Step-Progress -Number 12 -Message "Limpiando historial del portapapeles..."
if ($DryRun) {
    Log "  [SIMULACION] Se limpiaria el historial del portapapeles."
} else {
    try {
        [Windows.ApplicationModel.DataTransfer.Clipboard,Windows.ApplicationModel.DataTransfer,ContentType=WindowsRuntime] | Out-Null
        [Windows.ApplicationModel.DataTransfer.Clipboard]::ClearHistory() | Out-Null
        Log "  -> Historial del portapapeles eliminado."
    } catch {
        Log "  -> No se pudo limpiar el historial del portapapeles (puede estar desactivado en este equipo)."
    }
}

# --- 13. Puntos de restauracion de mas de 1 ano ---
Step-Progress -Number 13 -Message "Revisando puntos de restauracion antiguos..."
try {
    # NOTA (v2.0): se filtra por Context = "ClientAccessible", que es el contexto
    # que usa System Restore para sus puntos de restauracion. Sin este filtro,
    # Win32_ShadowCopy devuelve TODAS las shadow copies del volumen, incluyendo
    # las que pueda estar usando software de backup de terceros (VSS), con
    # riesgo de borrarlas sin que el usuario lo sepa.
    $restorePoints = Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction Stop |
        Where-Object { $_.Context -eq "ClientAccessible" } |
        Sort-Object InstallDate
    $totalPoints = $restorePoints.Count
    $rpDeletedCount = 0

    if ($totalPoints -le 1) {
        Log "  -> Solo hay $totalPoints punto(s) de restauracion; no se elimina para conservar al menos uno."
        Add-Summary "Puntos de restauracion antiguos: ninguno eliminado (solo habia $totalPoints en total)."
    } else {
        $oneYearAgo = (Get-Date).AddYears(-1)
        $oldPoints = $restorePoints | Where-Object {
            [Management.ManagementDateTimeConverter]::ToDateTime($_.InstallDate) -lt $oneYearAgo
        }

        if ($oldPoints.Count -eq 0) {
            Log "  -> No hay puntos de restauracion con mas de 1 ano de antiguedad."
            Add-Summary "Puntos de restauracion antiguos: no se encontraron (todos son recientes)."
        } else {
            # Si TODOS los puntos son antiguos, se conserva el mas reciente para no dejar el sistema sin ninguno
            if ($oldPoints.Count -eq $totalPoints) {
                $oldPoints = $oldPoints | Select-Object -SkipLast 1
                Log "  -> Todos los puntos eran antiguos; se conserva el mas reciente."
            }

            foreach ($point in $oldPoints) {
                $fecha = [Management.ManagementDateTimeConverter]::ToDateTime($point.InstallDate)
                if ($DryRun) {
                    Log "  [SIMULACION] Se eliminaria el punto de restauracion del $fecha."
                } else {
                    vssadmin delete shadows /shadow="$($point.ID)" /quiet | Out-Null
                    Log "  -> Eliminado punto de restauracion del $fecha."
                }
                $rpDeletedCount++
            }
            $verbo = if ($DryRun) { "se eliminarian" } else { "eliminados" }
            Add-Summary "Puntos de restauracion antiguos (+1 ano): $rpDeletedCount $verbo."
        }
    }
} catch {
    Log "  -> No se pudo acceder a los puntos de restauracion (puede requerir que System Restore este habilitado)."
    Add-Summary "Puntos de restauracion antiguos: no se pudo verificar (System Restore podria estar deshabilitado)."
}

# --- 14. Windows.old y carpetas de actualizacion antigua (OPCIONAL, con confirmacion) ---
Step-Progress -Number 14 -Message "Revisando archivos de actualizacion antiguos (Windows.old)..."
if ($Silent) {
    Log "  -> Paso omitido en modo automatico/silencioso (requiere confirmacion manual)."
} else {
    $oldWinFolders = @(
        "$env:SystemDrive\Windows.old",
        "$env:SystemDrive\`$Windows.~BT",
        "$env:SystemDrive\`$Windows.~WS"
    ) | Where-Object { Test-Path $_ }

    if ($oldWinFolders.Count -gt 0) {
        Write-Host "`nSe encontraron las siguientes carpetas de actualizacion antigua:"
        $oldWinFolders | ForEach-Object {
            $sizeGB = [math]::Round((Get-FolderSizeMB $_) / 1024, 2)
            Write-Host "   - $_ (~$sizeGB GB)"
        }
        Write-Host "Eliminarlas es PERMANENTE y hara que ya NO puedas volver a la" -ForegroundColor Red
        Write-Host "version anterior de Windows / desactivar la ultima actualizacion." -ForegroundColor Red
        $r = Read-Host "Eliminar estas carpetas y liberar ese espacio? (S/N)"
        if ($r -match "^[SsYy]") {
            $oldWinRemovedCount = 0
            foreach ($folder in $oldWinFolders) {
                $sizeMB = Get-FolderSizeMB $folder
                if ($sizeMB -gt 0) { Add-SpaceReport -Category "Windows.old / Actualizaciones antiguas" -MB $sizeMB }
                if ($DryRun) {
                    Log "  [SIMULACION] Se eliminaria: $folder (~$sizeMB MB)"
                    $oldWinRemovedCount++
                    continue
                }
                try {
                    takeown /F $folder /R /A /D Y | Out-Null
                    icacls $folder /reset /T /C /Q | Out-Null
                    Remove-Item $folder -Recurse -Force -ErrorAction Stop
                    Log "  -> Eliminado: $folder"
                    $oldWinRemovedCount++
                } catch {
                    Log "  -> No se pudo eliminar completamente: $folder (puede requerir Liberador de espacio en disco de Windows manualmente)."
                }
            }
            $verbo = if ($DryRun) { "se eliminarian" } else { "eliminadas" }
            Add-Summary "Windows.old / actualizaciones antiguas: $oldWinRemovedCount de $($oldWinFolders.Count) carpetas $verbo."
        } else {
            Log "  -> Se conservaron las carpetas de actualizacion antigua."
            Add-Summary "Windows.old / actualizaciones antiguas: encontradas pero conservadas (usuario eligio no eliminar)."
        }
    } else {
        Log "  -> No se encontraron carpetas de actualizacion antigua (Windows.old, etc.)."
        Add-Summary "Windows.old / actualizaciones antiguas: no se encontraron."
    }
}

# --- 15. Programas de inicio con Windows (listado + confirmacion individual) ---
Step-Progress -Number 15 -Message "Revisando programas que inician con Windows..."
if ($Silent) {
    Log "  -> Paso omitido en modo automatico/silencioso (requiere confirmacion manual)."
} else {
    try {
        $startupItems = Get-CimInstance -ClassName Win32_StartupCommand -ErrorAction Stop |
            Select-Object Name, Command, Location, User

        if ($startupItems.Count -gt 0) {
            Write-Host "`nPrograma(s) que inician automaticamente con Windows:"
            $i = 1
            foreach ($item in $startupItems) {
                Write-Host "   [$i] $($item.Name)  -  $($item.Location)"
                $i++
            }
            Write-Host "`nSe preguntara de forma individual si deseas DESACTIVAR cada uno."
            Write-Host "Desactivar NO desinstala el programa, solo evita que inicie solo." -ForegroundColor Yellow

            $startupDisabledCount = 0
            $startupKeptCount = 0
            $startupRevisar = $true
            if (-not $DryRun) {
                Write-Host "Si no sabes cual elegir, o son demasiados, puedes omitir este paso" -ForegroundColor DarkGray
                Write-Host "por completo: no se tocara ninguno." -ForegroundColor DarkGray
                $rTodos = Read-Host "Revisar la lista uno por uno (S), u omitir todos sin tocar nada (N)? (S/N)"
                $startupRevisar = $rTodos -match "^[SsYy]"
            }

            if (-not $startupRevisar) {
                Log "  -> Paso omitido por el usuario: no se reviso ningun programa de inicio."
                Add-Summary "Programas de inicio: paso omitido por el usuario ($($startupItems.Count) detectados, ninguno revisado)."
            } else {
            foreach ($item in $startupItems) {
                $r = Read-Host "Desactivar el inicio automatico de '$($item.Name)'? (S/N)"
                if ($r -match "^[SsYy]") {
                    if ($DryRun) {
                        Log "  [SIMULACION] Se desactivaria: $($item.Name)"
                        $startupDisabledCount++
                        continue
                    }
                    try {
                        if ($item.Location -match "Run(Once)?$") {
                            # WMI puede devolver la ruta en forma larga (HKEY_LOCAL_MACHINE\...)
                            # o corta (HKLM\...), y ninguna trae ":" que PowerShell necesita.
                            # Se normaliza a ambos casos para construir una ruta valida (HKLM:\... o HKCU:\...).
                            $regPath = $item.Location
                            $regPath = $regPath -replace "^HKEY_LOCAL_MACHINE\\", "HKLM:\"
                            $regPath = $regPath -replace "^HKEY_CURRENT_USER\\", "HKCU:\"
                            $regPath = $regPath -replace "^HKLM\\", "HKLM:\"
                            $regPath = $regPath -replace "^HKCU\\", "HKCU:\"

                            if ($regPath -notmatch "^(HKLM|HKCU):") {
                                Log "  -> No se pudo interpretar la ruta de registro de: $($item.Name) (ubicacion: $($item.Location))"
                            } else {
                                Remove-ItemProperty -Path $regPath -Name $item.Name -ErrorAction Stop
                                Log "  -> Desactivado (registro): $($item.Name)"
                                $startupDisabledCount++
                            }
                        } elseif ($item.Location -match "Startup") {
                            $shortcutPath = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup","$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\StartUp" -Filter "*$($item.Name)*" -ErrorAction SilentlyContinue | Select-Object -First 1
                            if ($shortcutPath) {
                                Remove-Item $shortcutPath.FullName -Force -ErrorAction Stop
                                Log "  -> Desactivado (acceso directo eliminado): $($item.Name)"
                                $startupDisabledCount++
                            } else {
                                Log "  -> No se encontro el acceso directo de: $($item.Name)"
                            }
                        } else {
                            Log "  -> No se pudo desactivar automaticamente: $($item.Name) (ubicacion no reconocida: $($item.Location))"
                        }
                    } catch {
                        Log "  -> Error al intentar desactivar: $($item.Name) - $($_.Exception.Message)"
                    }
                } else {
                    Log "  -> Se conservo: $($item.Name)"
                    $startupKeptCount++
                }
            }
            Add-Summary "Programas de inicio: $startupDisabledCount desactivados, $startupKeptCount conservados (de $($startupItems.Count) detectados)."
            }
        } else {
            Log "  -> No se encontraron programas de inicio automatico."
            Add-Summary "Programas de inicio: no se encontraron."
        }
    } catch {
        Log "  -> No se pudo obtener la lista de programas de inicio."
        Add-Summary "Programas de inicio: no se pudo obtener la lista."
    }
}

# --- 16. Verificacion de errores del disco (solo lectura, seguro para SSD) ---
Step-Progress -Number 16 -Message "Verificando errores del disco (chkdsk /scan)..."
if ($DryRun) {
    Log "  [SIMULACION] Se omite en modo simulacion (es de solo lectura y no es necesario simularlo)."
    Add-Summary "Verificacion de disco (chkdsk): omitida en modo simulacion."
} elseif ($Silent -and -not $Monthly) {
    Log "  -> Paso omitido en ejecucion silenciosa semanal (solo se ejecuta en la mensual)."
    Add-Summary "Verificacion de disco (chkdsk): omitida (ejecucion silenciosa semanal)."
} elseif ($Silent -and $Monthly -and $script:SkipHeavyScansOnBattery) {
    Log "  -> Paso omitido: equipo portatil con bateria baja ($($script:BatteryPercent)%) y sin cargador conectado."
    Add-Summary "Verificacion de disco (chkdsk): omitida (bateria baja, sin cargador)."
} else {
    $ejecutarChkdsk = $true
    if (-not $Silent) {
        $r = Read-Host "Deseas ejecutar la verificacion de disco (chkdsk /scan, solo lectura)? (S/N)"
        $ejecutarChkdsk = $r -match "^[SsYy]"
    }
    if ($ejecutarChkdsk) {
        try {
            $chkdskResult = chkdsk $env:SystemDrive /scan 2>&1
            $chkdskResult | Out-File "$optimizerDir\ChkDsk_Resultado_$timestamp.txt" -Force
            Log "  -> Verificacion completada. Resultado guardado en ChkDsk_Resultado_$timestamp.txt ($optimizerDir)."
            $chkdskText = ($chkdskResult | Out-String)
            if ($chkdskText -match "(?i)no problems|no encontro ningun problema|no ha encontrado ningun problema|encontro 0 problema") {
                Add-Summary "Verificacion de disco (chkdsk): completada, sin problemas detectados."
            } else {
                Add-Summary "Verificacion de disco (chkdsk): completada, revisa ChkDsk_Resultado_$timestamp.txt por posibles hallazgos."
            }
        } catch {
            Log "  -> No se pudo ejecutar chkdsk /scan en este equipo."
            Add-Summary "Verificacion de disco (chkdsk): no se pudo ejecutar."
        }
    } else {
        Log "  -> Verificacion de disco omitida por el usuario."
        Add-Summary "Verificacion de disco (chkdsk): omitida por el usuario."
    }
}

# --- 17. Escaneo rapido de Windows Defender (solo lectura, seguro para SSD) ---
Step-Progress -Number 17 -Message "Ejecutando escaneo rapido de Windows Defender..."
if ($DryRun) {
    Log "  [SIMULACION] Se omite en modo simulacion (es de solo lectura y no es necesario simularlo)."
    Add-Summary "Escaneo de Windows Defender: omitido en modo simulacion."
} elseif ($Silent -and -not $Monthly) {
    Log "  -> Paso omitido en ejecucion silenciosa semanal (solo se ejecuta en la mensual)."
    Add-Summary "Escaneo de Windows Defender: omitido (ejecucion silenciosa semanal)."
} elseif ($Silent -and $Monthly -and $script:SkipHeavyScansOnBattery) {
    Log "  -> Paso omitido: equipo portatil con bateria baja ($($script:BatteryPercent)%) y sin cargador conectado."
    Add-Summary "Escaneo de Windows Defender: omitido (bateria baja, sin cargador)."
} else {
    $ejecutarDefender = $true
    if (-not $Silent) {
        $r = Read-Host "Deseas ejecutar un escaneo rapido de Windows Defender (solo lectura)? (S/N)"
        $ejecutarDefender = $r -match "^[SsYy]"
    }
    if ($ejecutarDefender) {
        try {
            if (Get-Command Start-MpScan -ErrorAction SilentlyContinue) {
                Start-MpScan -ScanType QuickScan -ErrorAction Stop
                Log "  -> Escaneo rapido de Defender completado (revisa el Centro de seguridad para detalles)."
                try {
                    $threats = Get-MpThreatDetection -ErrorAction SilentlyContinue
                    if ($threats -and $threats.Count -gt 0) {
                        Add-Summary "Escaneo de Windows Defender: completado, $($threats.Count) deteccion(es) reciente(s) - revisa el Centro de seguridad."
                    } else {
                        Add-Summary "Escaneo de Windows Defender: completado, sin amenazas detectadas."
                    }
                } catch {
                    Add-Summary "Escaneo de Windows Defender: completado (no se pudo confirmar el detalle de detecciones)."
                }
            } else {
                Log "  -> Windows Defender no esta disponible o esta desactivado (puede haber otro antivirus activo)."
                Add-Summary "Escaneo de Windows Defender: no disponible (puede haber otro antivirus activo)."
            }
        } catch {
            Log "  -> No se pudo completar el escaneo de Defender (puede estar deshabilitado por otro antivirus)."
            Add-Summary "Escaneo de Windows Defender: no se pudo completar."
        }
    } else {
        Log "  -> Escaneo de Windows Defender omitido por el usuario."
        Add-Summary "Escaneo de Windows Defender: omitido por el usuario."
    }
}

# --- 18. Limpieza avanzada del sistema (cleanmgr con perfil configurado) ---
Step-Progress -Number 18 -Message "Ejecutando liberador de espacio en disco de Windows..."
if ($DryRun) {
    Log "  [SIMULACION] Se configuraria el perfil de cleanmgr y se ejecutaria el Liberador de espacio en disco."
    Add-Summary "Liberador de espacio en disco (cleanmgr): omitido en modo simulacion."
} else {
    # NOTA (v2.0): "cleanmgr /sagerun:1" solo limpia las categorias marcadas
    # previamente con "/sageset:1" en el registro. Sin ese perfil, /sagerun:1
    # no hace nada (bug detectado en la auditoria: el paso se reportaba como
    # "ejecutado" aunque no liberara espacio real). Aqui se configura el perfil
    # 1 con un conjunto conservador de categorias seguras antes de ejecutarlo.
    $cleanmgrCategorias = @(
        "Active Setup Temp Folders", "Temporary Files", "Recycle Bin",
        "Temporary Setup Files", "Setup Log Files", "Thumbnail Cache",
        "Windows Error Reporting Files", "Delivery Optimization Files",
        "Windows Upgrade Log Files", "System error memory dump files",
        "System error minidump files"
    )
    $cleanmgrBaseKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    $cleanmgrConfigurado = $false
    try {
        foreach ($cat in $cleanmgrCategorias) {
            $catKey = "$cleanmgrBaseKey\$cat"
            if (Test-Path $catKey -ErrorAction SilentlyContinue) {
                New-ItemProperty -Path $catKey -Name "StateFlags0001" -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
                $cleanmgrConfigurado = $true
            }
        }
    } catch {
        Log "  -> No se pudo configurar el perfil de cleanmgr (se ejecutara con el perfil que ya existiera, si existe)."
    }

    if (-not $cleanmgrConfigurado) {
        Log "  -> No se encontraron categorias de VolumeCaches para configurar; se omite cleanmgr (no habria nada que limpiar de forma fiable)."
        Add-Summary "Liberador de espacio en disco (cleanmgr): omitido (no se pudo configurar el perfil de limpieza)."
    } else {
        try {
            Start-Process -FilePath cleanmgr.exe -ArgumentList "/sagerun:1" -WindowStyle Hidden -Wait -ErrorAction Stop
            Log "  -> Liberador de espacio en disco ejecutado con el perfil configurado."
            Add-Summary "Liberador de espacio en disco (cleanmgr): ejecutado con perfil de limpieza configurado."
        } catch {
            Log "  -> cleanmgr no disponible en este equipo, se omite."
            Add-Summary "Liberador de espacio en disco (cleanmgr): no disponible en este equipo."
        }
    }
}

# --- 19. Optimizacion adicional ---
Step-Progress -Number 19 -Message "Optimizacion final del sistema..."

if ($DryRun) {
    Log "  [SIMULACION] Se vaciaria la cache DNS y se ejecutaria Optimize-Volume (TRIM en SSD)."
    Add-Summary "Cache DNS: omitida en modo simulacion."
    Add-Summary "Optimizacion de unidad (TRIM/desfragmentacion): omitida en modo simulacion."
} else {
    ipconfig /flushdns | Out-Null
    Log "  -> Cache DNS vaciada."
    Add-Summary "Cache DNS: vaciada correctamente."

    # Ejecutar SFC en segundo plano (verifica archivos del sistema) - opcional, comentar si no se desea
    # sfc /scannow

    Log "  -> Optimizando unidad C: (puede tardar unos minutos)..."
    Optimize-Volume -DriveLetter C -ErrorAction SilentlyContinue
    Add-Summary "Optimizacion de unidad C: (TRIM en SSD / desfragmentacion en HDD) ejecutada."
}

# --- 20. Apps UWP con permiso de ejecucion en segundo plano (listado + confirmacion individual) ---
Step-Progress -Number 20 -Message "Revisando apps con ejecucion en segundo plano..."
if ($Silent) {
    Log "  -> Paso omitido en modo automatico/silencioso (requiere confirmacion manual)."
} else {
    try {
        $bgBaseKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
        $bgApps = @()
        if (Test-Path $bgBaseKey) {
            $bgApps = Get-ChildItem $bgBaseKey -ErrorAction SilentlyContinue | ForEach-Object {
                $disabled = (Get-ItemProperty -Path $_.PSPath -Name "Disabled" -ErrorAction SilentlyContinue).Disabled
                [PSCustomObject]@{ Pfn = $_.PSChildName; Key = $_.PSPath; CurrentlyDisabled = ($disabled -eq 1) }
            } | Where-Object { -not $_.CurrentlyDisabled }
        }

        if ($bgApps.Count -gt 0) {
            Write-Host "`nApps con permiso de ejecucion en segundo plano (actualmente activo):"
            $i = 1
            foreach ($app in $bgApps) {
                Write-Host "   [$i] $($app.Pfn)"
                $i++
            }
            Write-Host "Desactivar esto NO desinstala la app, solo evita que siga activa" -ForegroundColor Yellow
            Write-Host "en segundo plano cuando no la estas usando (ahorra CPU/RAM/bateria)." -ForegroundColor Yellow

            $bgDisabledCount = 0
            $bgKeptCount = 0
            $bgRevisar = $true
            if (-not $DryRun) {
                Write-Host "Si no sabes que app elegir, o son demasiadas, puedes omitir este paso" -ForegroundColor DarkGray
                Write-Host "por completo: no se tocara ninguna." -ForegroundColor DarkGray
                $rTodas = Read-Host "Revisar la lista una por una (S), u omitir todas sin tocar nada (N)? (S/N)"
                $bgRevisar = $rTodas -match "^[SsYy]"
            }
            if (-not $bgRevisar) {
                Log "  -> Paso omitido por el usuario: no se reviso ninguna app en segundo plano."
                Add-Summary "Apps en segundo plano: paso omitido por el usuario ($($bgApps.Count) detectadas, ninguna revisada)."
            } else {
            foreach ($app in $bgApps) {
                $r = Read-Host "Desactivar ejecucion en segundo plano de '$($app.Pfn)'? (S/N)"
                if ($r -match "^[SsYy]") {
                    if ($DryRun) {
                        Log "  [SIMULACION] Se desactivaria segundo plano de: $($app.Pfn)"
                        $bgDisabledCount++
                        continue
                    }
                    try {
                        New-ItemProperty -Path $app.Key -Name "Disabled" -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
                        New-ItemProperty -Path $app.Key -Name "DisabledByUser" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
                        Log "  -> Desactivado: $($app.Pfn)"
                        $bgDisabledCount++
                    } catch {
                        Log "  -> No se pudo desactivar: $($app.Pfn) - $($_.Exception.Message)"
                    }
                } else {
                    Log "  -> Se conservo: $($app.Pfn)"
                    $bgKeptCount++
                }
            }
            Add-Summary "Apps en segundo plano: $bgDisabledCount desactivadas, $bgKeptCount conservadas (de $($bgApps.Count) activas detectadas)."
            }
        } else {
            Log "  -> No se encontraron apps con ejecucion en segundo plano activa (o la funcion esta gestionada de otra forma en este equipo)."
            Add-Summary "Apps en segundo plano: no se encontraron activas para revisar."
        }
    } catch {
        Log "  -> No se pudo revisar las apps en segundo plano."
        Add-Summary "Apps en segundo plano: no se pudo obtener la lista."
    }
}

# --- 21. Diagnostico (solo lectura, SIN cambios) de servicios de terceros en inicio automatico ---
Step-Progress -Number 21 -Message "Diagnostico de servicios de terceros en inicio automatico..."
if ($Silent) {
    Log "  -> Paso omitido en modo automatico/silencioso (es informativo y alargaria la tarea programada)."
} else {
    try {
        # Solo se listan servicios de terceros (sin firma de Microsoft) configurados en
        # inicio Automatico. NO se modifica ni desactiva nada: es puramente informativo,
        # ya que decidir que servicio de terceros es seguro desactivar requiere conocer
        # sus dependencias caso por caso.
        $thirdPartyAuto = Get-CimInstance -ClassName Win32_Service -ErrorAction Stop |
            Where-Object { $_.StartMode -eq "Auto" -and $_.PathName -and $_.PathName -notmatch "\\Windows\\(System32|SysWOW64)\\" }

        if ($thirdPartyAuto.Count -gt 0) {
            Log "  -> Servicios de terceros en inicio Automatico (solo informativo, sin cambios):"
            foreach ($svc in $thirdPartyAuto) {
                Log "     - $($svc.DisplayName) [$($svc.Name)] - $($svc.PathName)"
            }
            Add-Summary "Diagnostico de servicios de terceros: $($thirdPartyAuto.Count) en inicio automatico (ver log para detalle; no se modifico ninguno)."
        } else {
            Log "  -> No se detectaron servicios de terceros evidentes en inicio automatico."
            Add-Summary "Diagnostico de servicios de terceros: ninguno detectado."
        }
    } catch {
        Log "  -> No se pudo obtener el listado de servicios."
        Add-Summary "Diagnostico de servicios de terceros: no se pudo obtener la lista."
    }
}

# --- (OPCIONAL) Eliminar contrasenas guardadas en navegadores y redes WiFi ---
if ($Silent) {
    Log "`nEliminacion de contrasenas: paso omitido en modo automatico/silencioso."
} else {
    Write-Host "`n=========================================" -ForegroundColor Yellow
    Write-Host "  ELIMINAR CONTRASENAS GUARDADAS (OPCIONAL)" -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Yellow
    Write-Host "A continuacion se preguntara de forma agrupada por los"
    Write-Host "navegadores y de forma individual por las redes WiFi."
    Write-Host "Cada accion es PERMANENTE y no se puede deshacer." -ForegroundColor Red

    Log "`nEliminacion de contrasenas (confirmacion agrupada por navegador, individual por red WiFi)..."

    if (-not $DryRun) {
        foreach ($b in $browsers) { Stop-Process -Name $b -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 2
    }

    # --- Contrasenas de navegadores (Chrome, Edge, Brave, Firefox) - una sola confirmacion ---
    $navegadoresDetectados = @()
    if (Test-Path $chromePath) { $navegadoresDetectados += "Chrome" }
    if (Test-Path $edgePath) { $navegadoresDetectados += "Edge" }
    if (Test-Path $bravePath) { $navegadoresDetectados += "Brave" }
    if (Test-Path $firefoxProfiles) { $navegadoresDetectados += "Firefox" }

    if ($navegadoresDetectados.Count -gt 0) {
        Write-Host "`nNavegadores detectados: $($navegadoresDetectados -join ', ')"
        $r = Read-Host "Eliminar contrasenas guardadas de TODOS estos navegadores? (S/N)"
        if ($r -match "^[SsYy]") {

            if (Test-Path $chromePath) {
                if ($DryRun) { Log "  [SIMULACION] Se eliminarian las contrasenas de Chrome." }
                else {
                    Remove-Item "$chromePath\Login Data" -Force -ErrorAction SilentlyContinue
                    Remove-Item "$chromePath\Login Data-journal" -Force -ErrorAction SilentlyContinue
                    Log "  -> Contrasenas de Chrome eliminadas."
                }
            }

            if (Test-Path $edgePath) {
                if ($DryRun) { Log "  [SIMULACION] Se eliminarian las contrasenas de Edge." }
                else {
                    Remove-Item "$edgePath\Login Data" -Force -ErrorAction SilentlyContinue
                    Remove-Item "$edgePath\Login Data-journal" -Force -ErrorAction SilentlyContinue
                    Log "  -> Contrasenas de Edge eliminadas."
                }
            }

            if (Test-Path $bravePath) {
                if ($DryRun) { Log "  [SIMULACION] Se eliminarian las contrasenas de Brave." }
                else {
                    Remove-Item "$bravePath\Login Data" -Force -ErrorAction SilentlyContinue
                    Remove-Item "$bravePath\Login Data-journal" -Force -ErrorAction SilentlyContinue
                    Log "  -> Contrasenas de Brave eliminadas."
                }
            }

            if (Test-Path $firefoxProfiles) {
                if ($DryRun) { Log "  [SIMULACION] Se eliminarian las contrasenas de Firefox." }
                else {
                    Get-ChildItem $firefoxProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                        Remove-Item "$($_.FullName)\logins.json" -Force -ErrorAction SilentlyContinue
                        Remove-Item "$($_.FullName)\key4.db" -Force -ErrorAction SilentlyContinue
                    }
                    Log "  -> Contrasenas de Firefox eliminadas."
                }
            }

            $verbo = if ($DryRun) { "se eliminarian" } else { "eliminadas" }
            Add-Summary "Contrasenas de navegadores: $verbo en $($navegadoresDetectados -join ', ')."

        } else {
            Log "  -> Se omitio la eliminacion de contrasenas de navegadores."
            Add-Summary "Contrasenas de navegadores: no se elimino nada (usuario eligio no hacerlo)."
        }
    } else {
        Log "  -> No se detectaron navegadores compatibles instalados."
        Add-Summary "Contrasenas de navegadores: no se detectaron navegadores compatibles."
    }

    # --- Perfiles de redes WiFi guardadas (una sola confirmacion para todas) ---
    $wifiProfiles = (netsh wlan show profiles) | Select-String "\:(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
    if ($wifiProfiles.Count -gt 0) {
        Write-Host "`nSe encontraron $($wifiProfiles.Count) redes WiFi guardadas:"
        $wifiProfiles | ForEach-Object { Write-Host "   - $_" }
        $r = Read-Host "Eliminar TODOS estos perfiles de redes WiFi? (S/N)"
        if ($r -match "^[SsYy]") {
            foreach ($profile in $wifiProfiles) {
                if ($DryRun) {
                    Log "  [SIMULACION] Se eliminaria el perfil WiFi: $profile"
                } else {
                    netsh wlan delete profile name="$profile" | Out-Null
                    Log "  -> Eliminado perfil WiFi: $profile"
                }
            }
            $verbo = if ($DryRun) { "se eliminarian" } else { "eliminados" }
            Add-Summary "Redes WiFi guardadas: $($wifiProfiles.Count) $verbo."
        } else {
            Log "  -> Se conservaron todos los perfiles de redes WiFi."
            Add-Summary "Redes WiFi guardadas: $($wifiProfiles.Count) encontradas, conservadas (usuario eligio no eliminar)."
        }
    } else {
        Log "  -> No se encontraron perfiles de redes WiFi guardadas."
        Add-Summary "Redes WiFi guardadas: no se encontraron."
    }
}

# --- Cerrar la barra de progreso ---
Write-Progress -Activity "Mantenimiento y Limpieza de Windows" -Completed

# --- Calcular espacio recuperado ---
$driveCAfter = Get-PSDrive C -ErrorAction SilentlyContinue
$freeAfter = if ($driveCAfter) { $driveCAfter.Free } else { $freeBefore }
$recoveredBytes = $freeAfter - $freeBefore
$recoveredGB = [math]::Round($recoveredBytes / 1GB, 2)

# --- Resumen final de escaneos, optimizaciones y acciones ---
Write-Host "`n=========================================" -ForegroundColor Green
Write-Host "  RESUMEN DE ESCANEOS Y OPTIMIZACIONES" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Log "`nResumen de escaneos, optimizaciones y acciones realizadas:"
if ($script:Summary.Count -gt 0) {
    foreach ($line in $script:Summary) {
        Write-Host "  - $line"
        Log "  - $line"
    }
} else {
    Log "  (no se registraron acciones para resumir)"
}

# --- Reporte detallado por categoria ---
Write-Host "`n=========================================" -ForegroundColor Green
if ($DryRun) {
    Write-Host "  RESULTADO DE LA SIMULACION (nada fue eliminado)" -ForegroundColor Magenta
} else {
    Write-Host "  DETALLE DE ESPACIO POR CATEGORIA" -ForegroundColor Green
}
Write-Host "=========================================" -ForegroundColor Green
Log "`nDetalle de espacio $(if ($DryRun) {'que se liberaria'} else {'liberado'}) por categoria:"
if ($script:SpaceReport.Count -gt 0) {
    foreach ($key in $script:SpaceReport.Keys) {
        $mb = [math]::Round($script:SpaceReport[$key], 2)
        $line = "  - {0}: {1} MB" -f $key, $mb
        Write-Host $line
        Log $line
    }
} else {
    Log "  (no se detecto espacio significativo en las categorias medidas)"
}

Write-Host "`n=========================================" -ForegroundColor Green
if ($DryRun) {
    Write-Host "  SIMULACION COMPLETADA - no se elimino nada" -ForegroundColor Magenta
} else {
    Write-Host "  LIMPIEZA COMPLETADA" -ForegroundColor Green
    if ($recoveredGB -gt 0) {
        Write-Host "  Espacio total recuperado en disco: $recoveredGB GB" -ForegroundColor Green
    } else {
        Write-Host "  Espacio recuperado: menos de lo esperado o no medible" -ForegroundColor Yellow
        Write-Host "  (puede deberse a actividad del sistema durante la limpieza)" -ForegroundColor Yellow
    }
}
Write-Host "  Log guardado en: $logFile" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green

Log "`nEspacio libre antes: $([math]::Round($freeBefore/1GB,2)) GB"
Log "Espacio libre despues: $([math]::Round($freeAfter/1GB,2)) GB"
Log "Espacio total recuperado: $recoveredGB GB"
"Fin de limpieza: $(Get-Date)" | Out-File $logFile -Append

# --- Programar ejecucion automatica (solo en modo interactivo) ---
if (-not $Silent -and -not $DryRun) {
    Write-Host "`n=========================================" -ForegroundColor Cyan
    Write-Host "  PROGRAMAR EJECUCION AUTOMATICA (OPCIONAL)" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "La tarea programada usara la copia guardada en:"
    Write-Host "  $stableScriptPath"
    Write-Host "(se creo automaticamente en la primera ejecucion de este script)."
    $schedResp = Read-Host "Programar este script para ejecutarse solo? (S = Semanal, M = Mensual, N = No)"

    # NOTA (v2.0): nombre actual de la tarea, y nombres usados por versiones
    # anteriores del script. Al reprogramar, se eliminan las tareas legacy para
    # no dejar tareas duplicadas/huerfanas apuntando a un script ya renombrado.
    $currentTaskName = "MantenimientoWindows"
    $legacyTaskNames = @("LimpiezaOptimizacionWindows11")

    function Remove-LegacyScheduledTasks {
        param([string[]]$Names, [string]$KeepName)
        foreach ($n in $Names) {
            if ($n -eq $KeepName) { continue }
            schtasks /Query /TN $n 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                schtasks /Delete /TN $n /F 2>$null | Out-Null
                Log "  -> Tarea programada de una version anterior eliminada: $n"
            }
        }
    }

    if (-not (Test-Path $stableScriptPath)) {
        Write-Host "  -> No se encontro la copia en $optimizerDir, no se puede programar la tarea." -ForegroundColor Red
        Log "  -> Programacion cancelada: no existe $stableScriptPath."
    } elseif ($schedResp -match "^[Ss]") {
        Remove-LegacyScheduledTasks -Names $legacyTaskNames -KeepName $currentTaskName
        $taskName = $currentTaskName
        $trArg = "-NoProfile -ExecutionPolicy Bypass -File `"$stableScriptPath`" -Silent"
        # NOTA (v2.0): se crea con /RU SYSTEM para que la tarea se ejecute aunque
        # el usuario no tenga sesion iniciada a esa hora (antes dependia de la
        # sesion del usuario que la programo, y podia no dispararse nunca).
        schtasks /Create /SC WEEKLY /D SUN /TN $taskName /TR "powershell.exe $trArg" /ST 20:00 /RL HIGHEST /RU SYSTEM /F | Out-Null
        Log "  -> Tarea programada creada (como SYSTEM): se ejecutara todos los domingos a las 8:00 PM (sin chkdsk ni Defender, solo en la mensual)."
        Write-Host "  -> Listo. Se ejecutara todos los domingos a las 8:00 PM en modo silencioso." -ForegroundColor Green
        Write-Host "     Nota: chkdsk y el escaneo de Defender solo corren en la tarea mensual." -ForegroundColor DarkGray
    } elseif ($schedResp -match "^[Mm]") {
        Remove-LegacyScheduledTasks -Names $legacyTaskNames -KeepName $currentTaskName
        $taskName = $currentTaskName
        $trArg = "-NoProfile -ExecutionPolicy Bypass -File `"$stableScriptPath`" -Silent -Monthly"
        schtasks /Create /SC MONTHLY /D 1 /TN $taskName /TR "powershell.exe $trArg" /ST 20:00 /RL HIGHEST /RU SYSTEM /F | Out-Null
        Log "  -> Tarea programada creada (como SYSTEM): se ejecutara el dia 1 de cada mes a las 8:00 PM (incluye chkdsk y escaneo de Defender)."
        Write-Host "  -> Listo. Se ejecutara el dia 1 de cada mes a las 8:00 PM en modo silencioso." -ForegroundColor Green
        Write-Host "     Esta ejecucion mensual tambien incluye chkdsk /scan y el escaneo de Defender." -ForegroundColor Green
    } else {
        Log "  -> No se programo ejecucion automatica."
    }
}

if (-not $Silent) {
    Read-Host "`nPresiona ENTER para salir"
}
