#!/bin/bash

run_dry_run() {
    list_tasks
    if [ "$(jq 'del(.allowed_networks) | length' "$CONFIG_FILE")" -eq 0 ]; then
        read -p "Nenhuma tarefa para simular. Pressione Enter..."
        return
    fi

    read -p "Digite o ID da tarefa que deseja simular: " id
    if ! jq -e --arg id "$id" 'has($id)' "$CONFIG_FILE" > /dev/null; then
        echo "Erro: O identificador '$id' não existe."
        sleep 2
        return
    fi

    local SOURCE=$(jq -r --arg id "$id" '.[$id].source' "$CONFIG_FILE" | envsubst)
    local DEST=$(jq -r --arg id "$id" '.[$id].destination' "$CONFIG_FILE" | envsubst)
    local RCLONE_PARAMS_AC="--checkers 24 --transfers 12"
    local RCLONE_PARAMS_BATTERY="--checkers 8 --transfers 4 --bwlimit 2M"
    local rclone_params_to_use
    local POWER_SUPPLY_PATH="/sys/class/power_supply/AC/online"
    
    echo "Detectando fonte de energia para uma simulação mais precisa..."
    if [ -f "$POWER_SUPPLY_PATH" ] && [ "$(cat $POWER_SUPPLY_PATH)" -eq 1 ]; then
        rclone_params_to_use=$RCLONE_PARAMS_AC
        echo "Simulando com perfil de ALTA PERFORMANCE (conectado à tomada)."
    else
        rclone_params_to_use=$RCLONE_PARAMS_BATTERY
        echo "Simulando com perfil de ECONOMIA DE ENERGIA (na bateria)."
    fi
    sleep 2
    
    clear
    echo "--- SIMULAÇÃO (DRY RUN) PARA '$id' ---"
    echo "O rclone irá listar todas as ações que faria, mas NENHUM ARQUIVO SERÁ ALTERADO."
    echo "------------------------------------------------------------------"
    
    rclone sync \
        --dry-run \
        --progress \
        --track-renames \
        $rclone_params_to_use \
        --fast-list \
        "$SOURCE" "$DEST"
        
    echo "------------------------------------------------------------------"
    read -p "Simulação concluída. Pressione Enter para voltar ao menu..."
}

view_logs() {
    list_tasks
    if [ "$(jq 'del(.allowed_networks) | length' "$CONFIG_FILE")" -eq 0 ]; then
        read -p "Nenhuma tarefa para ver logs. Pressione Enter..."
        return
    fi

    read -p "Digite o ID da tarefa para ver os logs: " id
    local LOG_FILE="$HOME/.rclone-easy-logs/.backup_gdrive_${id}.log"

    if [ -f "$LOG_FILE" ]; then
        clear
        echo "Mostrando logs de '$id'. Pressione Ctrl+C para sair."
        tail -f "$LOG_FILE"
    else
        echo "Nenhum arquivo de log encontrado para a tarefa '$id'."
        read -p "Pressione Enter para voltar..."
    fi
}