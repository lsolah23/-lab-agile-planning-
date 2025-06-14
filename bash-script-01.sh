#!/bin/bash

# --- Configuración del Script ---
# Nombre del script para mensajes
SCRIPT_NAME="util-backup.sh"

# Directorio donde se guardarán las copias de seguridad (debe existir)
# Cambia esto a tu ruta deseada, por ejemplo: /mnt/backups
BACKUP_DIR="/ruta/a/tus/backups/proyecto_x"

# Directorio de origen a respaldar
# Cambia esto a la ruta de tu proyecto o datos a respaldar, por ejemplo: /home/usuario/mi_proyecto
SOURCE_DIR="/ruta/a/tu/proyecto/fuente"

# Nombre base para los directorios de copia de seguridad
# Por ejemplo, si es "mi_app", las copias serán "mi_app_20230101-103000"
BACKUP_PREFIX="mi_proyecto"

# Usuario que ejecuta el script (para verificaciones de permisos, si es necesario)
CURRENT_USER=$(whoami)

# --- Funciones de Utilidad ---

# Función para mostrar mensajes de error y salir
function error_exit {
    echo -e "\n\e[31m[ERROR]\e[0m $1" >&2
    exit 1
}

# Función para mostrar mensajes de información
function info_msg {
    echo -e "\e[34m[INFO]\e[0m $1"
}

# Función para mostrar mensajes de éxito
function success_msg {
    echo -e "\e[32m[ÉXITO]\e[0m $1"
}

# Función para verificar si un directorio existe
function check_dir_exists {
    if [[ ! -d "$1" ]]; then
        error_exit "El directorio '$1' no existe o no es accesible."
    fi
}

# Función para verificar si rsync está instalado
function check_rsync_installed {
    if ! command -v rsync &> /dev/null; then
        error_exit "rsync no está instalado. Por favor, instálalo (ej: sudo apt install rsync)."
    fi
}

# --- Funciones Principales ---

# Función para crear una nueva copia de seguridad incremental
function create_backup {
    info_msg "Iniciando creación de copia de seguridad..."
    check_dir_exists "$SOURCE_DIR"
    check_dir_exists "$BACKUP_DIR"
    check_rsync_installed

    # Genera el nombre del directorio de copia de seguridad con fecha y hora
    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    NEW_BACKUP_PATH="${BACKUP_DIR}/${BACKUP_PREFIX}_${TIMESTAMP}"

    info_msg "Directorio de origen: '$SOURCE_DIR'"
    info_msg "Directorio de destino: '$NEW_BACKUP_PATH'"

    # Encuentra la última copia de seguridad completa para el enlace duro (incremental)
    # Lista las copias de seguridad existentes, ordena por fecha, y toma la última
    LAST_BACKUP=$(ls -td "${BACKUP_DIR}/${BACKUP_PREFIX}_"* 2>/dev/null | head -n 1)

    RSYNC_OPTIONS="-avh --delete --stats" # -a (archive), -v (verbose), -h (human-readable), --delete (elimina archivos en destino si no están en origen), --stats (estadísticas)

    if [[ -n "$LAST_BACKUP" ]]; then
        info_msg "Última copia de seguridad encontrada para enlace duro: '$LAST_BACKUP'"
        # Utiliza --link-dest para enlaces duros incrementales.
        # Esto crea enlaces duros a archivos sin cambios desde la última copia, ahorrando espacio.
        rsync $RSYNC_OPTIONS --link-dest="${LAST_BACKUP}" "$SOURCE_DIR/" "$NEW_BACKUP_PATH"
    else
        info_msg "No se encontraron copias de seguridad anteriores. Realizando copia de seguridad completa inicial."
        rsync $RSYNC_OPTIONS "$SOURCE_DIR/" "$NEW_BACKUP_PATH"
    fi

    if [[ $? -eq 0 ]]; then
        success_msg "Copia de seguridad creada exitosamente en: '$NEW_BACKUP_PATH'"
    else
        error_exit "Fallo al crear la copia de seguridad. Verifique los errores anteriores."
    fi
}

# Función para listar las copias de seguridad existentes
function list_backups {
    info_msg "Listando copias de seguridad en: '$BACKUP_DIR'"
    check_dir_exists "$BACKUP_DIR"

    # Buscar directorios que coincidan con el prefijo
    BACKUPS=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "${BACKUP_PREFIX}_*" | sort -r)

    if [[ -z "$BACKUPS" ]]; then
        info_msg "No se encontraron copias de seguridad para '${BACKUP_PREFIX}'."
    else
        echo -e "\n--- Copias de Seguridad Disponibles ---"
        echo "$BACKUPS" | sed "s|^${BACKUP_DIR}/||" | nl -w 3 -s ". "
        echo "---------------------------------------"
    fi
}

# Función para restaurar una copia de seguridad
function restore_backup {
    info_msg "Iniciando restauración de copia de seguridad..."
    list_backups

    read -p "Ingrese el NÚMERO de la copia de seguridad a restaurar: " BACKUP_NUMBER

    # Obtener la ruta completa de la copia de seguridad seleccionada
    SELECTED_BACKUP=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "${BACKUP_PREFIX}_*" | sort -r | sed -n "${BACKUP_NUMBER}p")

    if [[ -z "$SELECTED_BACKUP" ]]; then
        error_exit "Número de copia de seguridad inválido o no encontrado."
    fi

    info_msg "Copia de seguridad seleccionada para restaurar: '$SELECTED_BACKUP'"

    read -p "¿Es el directorio de destino de la restauración el original ('$SOURCE_DIR')? (s/N): " CONFIRM_RESTORE_DEST

    DESTINATION_DIR="$SOURCE_DIR"
    if [[ "$CONFIRM_RESTORE_DEST" =~ ^[Nn]$ ]]; then
        read -p "Ingrese la ruta ABSOLUTA del directorio de destino para la restauración: " CUSTOM_DEST_DIR
        if [[ -z "$CUSTOM_DEST_DIR" ]]; then
            error_exit "Ruta de destino no puede estar vacía."
        fi
        DESTINATION_DIR="$CUSTOM_DEST_DIR"
    fi

    check_dir_exists "$DESTINATION_DIR"
    check_rsync_installed

    echo -e "\n\e[33m[ADVERTENCIA]\e[0m ¡Esto sobrescribirá o eliminará archivos en '$DESTINATION_DIR'!"
    read -p "¿Está seguro de que desea continuar con la restauración? (s/N): " CONFIRM

    if [[ "$CONFIRM" =~ ^[Ss]$ ]]; then
        info_msg "Restaurando de '$SELECTED_BACKUP/' a '$DESTINATION_DIR/'..."
        # El comando rsync para restaurar es similar, pero la fuente es la copia de seguridad
        rsync -avh --delete --stats "$SELECTED_BACKUP/" "$DESTINATION_DIR/"

        if [[ $? -eq 0 ]]; then
            success_msg "Restauración completada exitosamente en: '$DESTINATION_DIR'"
        else
            error_exit "Fallo al restaurar la copia de seguridad. Verifique los errores anteriores."
        fi
    else
        info_msg "Restauración cancelada por el usuario."
    fi
}

# --- Menú y Procesamiento de Argumentos ---

function show_help {
    echo "Uso: $SCRIPT_NAME [comando]"
    echo ""
    echo "Comandos disponibles:"
    echo "  create    - Crea una nueva copia de seguridad incremental."
    echo "  list      - Lista las copias de seguridad existentes."
    echo "  restore   - Restaura una copia de seguridad seleccionada."
    echo "  help      - Muestra esta ayuda."
    echo ""
    echo "Configuración actual:"
    echo "  Directorio de Origen:   $SOURCE_DIR"
    echo "  Directorio de Backups:  $BACKUP_DIR"
    echo "  Prefijo de Backups:     $BACKUP_PREFIX"
    echo ""
    echo "Asegúrese de configurar los directorios de SOURCE_DIR y BACKUP_DIR dentro del script."
}

# Verificar que se proporcione un comando
if [[ $# -eq 0 ]]; then
    show_help
    error_exit "No se proporcionó ningún comando."
fi

# Procesar el comando
case "$1" in
    create)
        create_backup
        ;;
    list)
        list_backups
        ;;
    restore)
        restore_backup
        ;;
    help)
        show_help
        ;;
    *)
        error_exit "Comando inválido: '$1'. Use 'help' para ver los comandos disponibles."
        ;;
esac

exit 0