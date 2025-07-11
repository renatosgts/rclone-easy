#!/bin/bash
# VERSÃO ATUALIZADA - Suporta modo Completo e modo de Inclusão.

CONFIG_FILE="$HOME/backup_tasks.json"
if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

run_backup_task() {
    local BACKUP_ID="$1"
    local SOURCE=$(jq -r --arg id "$BACKUP_ID" '.[$id].source' "$CONFIG_FILE" | envsubst)
    local DEST=$(jq -r --arg id "$BACKUP_ID" '.[$id].destination' "$CONFIG_FILE" | envsubst)
    # MUDANÇA: Lê o modo de sincronização, com "Completo" como padrão para tarefas antigas.
    local SYNC_MODE=$(jq -r --arg id "$BACKUP_ID" '.[$id].sync_mode // "Completo"' "$CONFIG_FILE")
    
    if [ "$SOURCE" == "null" ] || [ "$DEST" == "null" ]; then
        return 1
    fi

    local LOG_FILE="$HOME/.backup_gdrive_${BACKUP_ID}.log"
    local LOCK_FILE="/tmp/backup_gdrive_${BACKUP_ID}.lock"
    local RCLONE_PARAMS_AC="--checkers 24 --transfers 12"
    local RCLONE_PARAMS_BATTERY="--checkers 8 --transfers 4 --bwlimit 2M"

    (
        flock -n 9 || { exit 1; }
        while true; do
            # ... (a lógica de verificação de rede permanece a mesma) ...
            local CURRENT_SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d: -f2)
            if [ -n "$CURRENT_SSID" ]; then
                local ALLOWED_NETWORKS_JSON=$(jq -c '.allowed_networks' "$CONFIG_FILE")
                if [ "$ALLOWED_NETWORKS_JSON" != "null" ] && [ "$(jq 'length' <<< "$ALLOWED_NETWORKS_JSON")" -gt 0 ]; then
                    if ! jq -e --arg ssid "$CURRENT_SSID" '.[] | select(. == $ssid)' <<< "$ALLOWED_NETWORKS_JSON" > /dev/null; then
                        echo "$(date) - Rede Wi-Fi '$CURRENT_SSID' não permitida. Pausando." >> "$LOG_FILE"; sleep 1800; continue
                    fi
                fi
            fi
           
            local rclone_params_to_use
            # ... (a lógica de verificação de energia permanece a mesma) ...
            local POWER_SUPPLY_PATH="/sys/class/power_supply/AC/online"
            if [ -f "$POWER_SUPPLY_PATH" ] && [ "$(cat "$POWER_SUPPLY_PATH")" -eq 1 ]; then
                rclone_params_to_use=$RCLONE_PARAMS_AC
            else
                rclone_params_to_use=$RCLONE_PARAMS_BATTERY
            fi
            
            echo "$(date) - Iniciando backup para: '$BACKUP_ID' (Modo: $SYNC_MODE)" >> "$LOG_FILE"
            
            local rclone_cmd_array=("rclone" "sync" "--track-renames" "--fast-list")
            read -ra rclone_params_array <<< "$rclone_params_to_use"
            rclone_cmd_array+=("${rclone_params_array[@]}")

            # MUDANÇA: Lógica para escolher os parâmetros do rclone baseada no SYNC_MODE
            if [[ "$SYNC_MODE" == "Inclusão" ]]; then
                local INCLUDES_LIST=$(jq -r --arg id "$BACKUP_ID" '.[$id].includes[]?' "$CONFIG_FILE")
                if [ -n "$INCLUDES_LIST" ]; then
                    local temp_files_from=$(mktemp)
                    # Adiciona um trap para garantir que o arquivo temporário seja limpo
                    trap 'rm -f "$temp_files_from"' RETURN
                    echo "$INCLUDES_LIST" > "$temp_files_from"
                    rclone_cmd_array+=("--files-from" "$temp_files_from")
                else
                    echo "$(date) - Tarefa '$BACKUP_ID' em modo Inclusão, mas sem arquivos para incluir. Pausando." >> "$LOG_FILE"
                    sleep 1800
                    continue # Pula para a próxima iteração do while
                fi
            else # Modo Completo
                rclone_cmd_array+=("--git-ignore")
                local hidden_path="$SOURCE/.hidden"
                if [ -f "$hidden_path" ]; then
                    rclone_cmd_array+=("--exclude-from" "$hidden_path")
                fi
            fi

            "${rclone_cmd_array[@]}" "$SOURCE" "$DEST" >> "$LOG_FILE" 2>&1
            
            echo "$(date) - Sincronização de '$BACKUP_ID' finalizada. Pausa." >> "$LOG_FILE"
            echo "==================================================" >> "$LOG_FILE"
            sleep 1800
        done
    ) 9>"$LOCK_FILE"
}

# ... (o resto do arquivo para iniciar as tarefas permanece o mesmo) ...
TASKS_TO_RUN=($(jq -r 'keys_unsorted[] | select(. != "allowed_networks")' "$CONFIG_FILE"))
for task in "${TASKS_TO_RUN[@]}"; do
    run_backup_task "$task" &
done
wait