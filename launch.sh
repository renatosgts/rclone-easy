#!/bin/bash

# =================================================================
# FERRAMENTA DE GERENCIAMENTO DE BACKUPS
# Autor: Renato De Souza
# Descrição: Um script interativo e portátil para instalar, configurar e gerenciar
#            o sistema de backup com rclone em qualquer sistema Linux.
# =================================================================

# --- Variáveis Globais Dinâmicas ---
WORKER_SCRIPT_PATH="/usr/local/bin/backup-drive.sh"
CONFIG_FILE="$HOME/backup_tasks.json"
SERVICE_NAME="backup-manager.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
NEEDS_RESTART=false

# --- Funções do Menu ---

list_tasks() {
    clear
    echo "--- Tarefas de Backup Configuradas ---"
    if [ ! -f "$CONFIG_FILE" ] || [ "$(jq 'del(.allowed_networks) | length' "$CONFIG_FILE")" -eq 0 ]; then
        echo "Nenhuma tarefa de backup configurada."
    else
        jq -r 'to_entries[] | select(.key != "allowed_networks") | "▶️ ID: \(.key)\n  ├─ Origem: \(.value.source)\n  └─ Destino: \(.value.destination)\n"' "$CONFIG_FILE"
    fi
    echo "----------------------------------------"
}

add_task() {
    while true; do
        list_tasks
        echo "--- Adicionar Nova Tarefa de Backup ---"
        read -p "Digite um identificador único (ex: musicas): " id
        if [ -z "$id" ]; then echo "Erro: O identificador não pode ser vazio."; continue; fi
        if jq -e --arg id "$id" 'has($id)' "$CONFIG_FILE" > /dev/null; then echo "Erro: O identificador '$id' já existe."; continue; fi
        echo "Dica: você pode usar a variável \$HOME no caminho (ex: \$HOME/Documentos)"
        read -p "Digite o caminho completo da ORIGEM: " source
        read -p "Digite o destino no rclone (ex: gdrive:backup/musica): " dest
        jq --arg id "$id" --arg src "$source" --arg dst "$dest" '. + {($id): {"source": $src, "destination": $dst}}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "Tarefa '$id' adicionada com sucesso!"; NEEDS_RESTART=true
        read -p "Adicionar outra tarefa? (s/N) " choice
        case "$choice" in s|S) continue ;; *) break ;; esac
    done
}

remove_task() {
    list_tasks
    if [ "$(jq 'del(.allowed_networks) | length' "$CONFIG_FILE")" -eq 0 ]; then read -p "Pressione Enter para voltar..."; return; fi
    echo "--- Remover Tarefa de Backup ---"
    read -p "Digite o ID exato da tarefa a ser removida: " id
    if ! jq -e --arg id "$id" 'has($id)' "$CONFIG_FILE" > /dev/null; then echo "Erro: O identificador '$id' não existe.";
    else
        jq --arg id "$id" 'del(.[$id])' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "Tarefa '$id' removida com sucesso!"; NEEDS_RESTART=true
    fi
    read -p "Pressione Enter para voltar..."
}

manage_networks() {
    while true; do
        clear
        echo "--- Gerenciamento de Redes Permitidas (Whitelist) ---"
        echo "Os backups só rodarão quando conectado a uma destas redes."
        echo "Se a lista estiver vazia, os backups rodarão em QUALQUER rede."
        echo
        echo "Redes Atuais:"
        jq -r '.allowed_networks[]? // "Nenhuma rede configurada."' "$CONFIG_FILE"
        echo "-----------------------------------------------------"
        echo "1. Adicionar Rede Wi-Fi ATUAL à lista"
        echo "2. Adicionar Rede (Manualmente)"
        echo "3. Remover Rede da lista"
        echo "V. Voltar ao Menu Principal"
        echo "-----------------------------------------------------"
        read -p "Escolha uma opção: " net_choice
        case "$net_choice" in
            1)
                local current_ssid=$(nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d: -f2)
                if [ -z "$current_ssid" ]; then
                    echo "Erro: Não conectado a uma rede Wi-Fi."
                elif jq -e --arg ssid "$current_ssid" '.allowed_networks[]? | select(. == $ssid)' "$CONFIG_FILE" > /dev/null; then
                    echo "A rede '$current_ssid' já está na lista."
                else
                    jq '.allowed_networks += ["'"$current_ssid"'"]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                    echo "Rede '$current_ssid' adicionada com sucesso!"
                    NEEDS_RESTART=true
                fi
                sleep 2
                ;;
            2)
                read -p "Digite o nome (SSID) da rede a adicionar: " manual_ssid
                if [ -n "$manual_ssid" ]; then
                    jq '.allowed_networks += ["'"$manual_ssid"'"]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                    echo "Rede '$manual_ssid' adicionada com sucesso!"
                    NEEDS_RESTART=true
                fi
                sleep 2
                ;;
            3)
                read -p "Digite o nome EXATO da rede a remover: " ssid_to_remove
                if jq -e --arg ssid "$ssid_to_remove" '.allowed_networks[]? | select(. == $ssid)' "$CONFIG_FILE" > /dev/null; then
                    jq '.allowed_networks |= map(select(. != "'"$ssid_to_remove"'"))' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                    echo "Rede '$ssid_to_remove' removida com sucesso!"
                    NEEDS_RESTART=true
                else
                    echo "Erro: Rede não encontrada."
                fi
                sleep 2
                ;;
            V|v) break ;;
            *) echo "Opção inválida."; sleep 1 ;;
        esac
    done
}

run_dry_run() {
    list_tasks; if [ "$(jq 'del(.allowed_networks) | length' "$CONFIG_FILE")" -eq 0 ]; then read -p "Pressione Enter para voltar..."; return; fi
    read -p "Digite o ID da tarefa que deseja simular: " id
    if ! jq -e --arg id "$id" 'has($id)' "$CONFIG_FILE" > /dev/null; then echo "Erro: O identificador '$id' não existe."; sleep 2; return; fi
    local SOURCE=$(jq -r --arg id "$id" '.[$id].source' "$CONFIG_FILE" | envsubst)
    local DEST=$(jq -r --arg id "$id" '.[$id].destination' "$CONFIG_FILE" | envsubst)
    local RCLONE_PARAMS_AC="--checkers 24 --transfers 12"; local RCLONE_PARAMS_BATTERY="--checkers 8 --transfers 4 --bwlimit 2M"
    local rclone_params_to_use; local POWER_SUPPLY_PATH="/sys/class/power_supply/AC/online"
    echo "Detectando fonte de energia para uma simulação mais precisa..."
    if [ -f "$POWER_SUPPLY_PATH" ] && [ "$(cat "$POWER_SUPPLY_PATH")" -eq 1 ]; then rclone_params_to_use=$RCLONE_PARAMS_AC; echo "Simulando com perfil de ALTA PERFORMANCE (conectado à tomada)."; else rclone_params_to_use=$RCLONE_PARAMS_BATTERY; echo "Simulando com perfil de ECONOMIA DE ENERGIA (na bateria)."; fi
    sleep 2; clear
    echo "--- SIMULAÇÃO (DRY RUN) PARA '$id' ---"; echo "O rclone irá listar todas as ações que faria, mas NENHUM ARQUIVO SERÁ ALTERADO."; echo "------------------------------------------------------------------"
    rclone sync --dry-run --progress --track-renames $rclone_params_to_use --fast-list "$SOURCE" "$DEST"
    echo "------------------------------------------------------------------"; read -p "Simulação concluída. Pressione Enter para voltar ao menu..."
}

view_logs() {
    list_tasks
    if [ "$(jq 'del(.allowed_networks) | length' "$CONFIG_FILE")" -eq 0 ]; then read -p "Pressione Enter para voltar..."; return; fi
    read -p "Digite o ID da tarefa para ver os logs: " id
    local LOG_FILE="$HOME/.backup_gdrive_${id}.log"
    if [ -f "$LOG_FILE" ]; then clear; echo "Mostrando logs de '$id'. Pressione Ctrl+C para sair."; tail -f "$LOG_FILE";
    else echo "Nenhum arquivo de log encontrado para a tarefa '$id'."; read -p "Pressione Enter para voltar..."; fi
}

manage_service() {
    if [ ! -f "$SERVICE_PATH" ]; then
        echo "O serviço systemd não parece estar instalado. Execute a instalação primeiro (Opção 9)."
        sleep 3; return
    fi
    while true; do
        clear
        echo "--- Gerenciamento do Serviço ($SERVICE_NAME) ---"
        systemctl is-active --quiet "$SERVICE_NAME" && echo "Status: ATIVO (rodando)" || echo "Status: INATIVO (parado)"
        systemctl is-enabled --quiet "$SERVICE_NAME" && echo "Inicialização com o sistema: HABILITADA" || echo "Inicialização com o sistema: DESABILITADA"
        echo "----------------------------------------------------"
        echo "1. Iniciar (Start) o serviço agora"
        echo "2. Parar (Stop) o serviço agora"
        echo "3. Reiniciar (Restart) o serviço"
        echo "4. Habilitar para iniciar com o sistema (Enable)"
        echo "5. Desabilitar da inicialização (Disable)"
        echo "6. Ver status detalhado"
        echo "V. Voltar ao Menu Principal"
        echo "----------------------------------------------------"
        read -p "Escolha uma opção: " service_choice
        case "$service_choice" in
            1) sudo systemctl start "$SERVICE_NAME"; echo "Serviço iniciado."; sleep 1 ;;
            2) sudo systemctl stop "$SERVICE_NAME"; echo "Serviço parado."; sleep 1 ;;
            3) sudo systemctl restart "$SERVICE_NAME"; echo "Serviço reiniciado."; sleep 1; NEEDS_RESTART=false ;;
            4) sudo systemctl enable "$SERVICE_NAME"; echo "Serviço habilitado para a próxima inicialização."; sleep 2 ;;
            5) sudo systemctl disable "$SERVICE_NAME"; echo "Serviço desabilitado da próxima inicialização."; sleep 2 ;;
            6) clear; sudo systemctl status "$SERVICE_NAME"; read -p "Pressione Enter para voltar..." ;;
            V|v) break ;;
            *) echo "Opção inválida."; sleep 1 ;;
        esac
    done
}

uninstall_system() {
    clear
    echo "!! ATENÇÃO: AÇÃO DESTRUTIVA E IRREVERSÍVEL !!"; echo "Esta opção removerá TODOS os componentes deste sistema de backup:"; echo " - O serviço systemd ($SERVICE_NAME)"; echo " - O script de trabalho ($WORKER_SCRIPT_PATH)"; echo " - O arquivo de configuração de tarefas ($CONFIG_FILE)"; echo " - TODOS os arquivos de log de backup ($HOME/.backup_gdrive_*.log)"; echo
    read -p "Você tem certeza ABSOLUTA que deseja continuar? (s/N) " confirm
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then echo "Desinstalação cancelada."; sleep 2; return; fi
    echo; read -p "Para confirmar, por favor, digite a palavra 'confirmar': " final_confirm
    if [ "$final_confirm" != "confirmar" ]; then echo "Confirmação incorreta. Desinstalação cancelada."; sleep 2; return; fi
    echo "Iniciando a limpeza completa...";
    if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then echo "Parando e desabilitando o serviço..."; sudo systemctl disable --now "$SERVICE_NAME" &>/dev/null; fi
    echo "Removendo arquivos do sistema..."; [ -f "$SERVICE_PATH" ] && sudo rm -f "$SERVICE_PATH"; [ -f "$WORKER_SCRIPT_PATH" ] && sudo rm -f "$WORKER_SCRIPT_PATH"
    sudo systemctl daemon-reload
    echo "Removendo arquivos de configuração e logs do usuário..."; [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE"
    rm -f "$HOME"/.backup_gdrive_*.log; rm -f /tmp/backup_gdrive_*.lock
    echo; echo "Limpeza completa realizada com sucesso."; echo "O script de gerenciamento não foi removido. Você pode removê-lo manualmente se desejar."
    read -p "Pressione Enter para sair do script."; exit 0
}

setup() {
    echo "--- Verificando Instalação do Sistema de Backup ---"
    # 1. Verifica jq (essencial)
    if ! command -v jq &> /dev/null; then
        echo "O utilitário 'jq' é essencial."; read -p "Deseja instalá-lo agora? (S/n) " c
        case "$c" in n|N) exit 1 ;; *) sudo apt update && sudo apt install -y jq ;; esac
    fi
    
    # 2. Cria arquivo de configuração se não existir
    [ ! -f "$CONFIG_FILE" ] && echo "{}" > "$CONFIG_FILE"
    if ! jq -e '.allowed_networks' "$CONFIG_FILE" > /dev/null; then
        jq '. + {"allowed_networks": []}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi

    # 3. Opção para instalar/reinstalar os componentes principais
    if [ -f "$WORKER_SCRIPT_PATH" ] || [ -f "$SERVICE_PATH" ]; then
        return # Se já existe, não faz nada automaticamente. O usuário usará o menu.
    fi

    echo "Os componentes principais (script worker e serviço systemd) não estão instalados."
    read -p "Deseja realizar a instalação inicial agora? (S/n) " install_choice
    case "$install_choice" in
        n|N) return ;;
    esac

    echo "Instalando script de trabalho em $WORKER_SCRIPT_PATH..."
    sudo tee "$WORKER_SCRIPT_PATH" > /dev/null << 'EOF'
#!/bin/bash

CONFIG_FILE="$HOME/backup_tasks.json"
if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

run_backup_task() {
    local BACKUP_ID="$1"
    local SOURCE=$(jq -r --arg id "$BACKUP_ID" '.[$id].source' "$CONFIG_FILE" | envsubst)
    local DEST=$(jq -r --arg id "$BACKUP_ID" '.[$id].destination' "$CONFIG_FILE" | envsubst)

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
            local CURRENT_SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d: -f2)
            if [ -n "$CURRENT_SSID" ]; then
                local ALLOWED_NETWORKS_JSON=$(jq -c '.allowed_networks' "$CONFIG_FILE")
                if [ "$ALLOWED_NETWORKS_JSON" != "null" ] && [ "$(jq 'length' <<< "$ALLOWED_NETWORKS_JSON")" -gt 0 ]; then
                    if ! jq -e --arg ssid "$CURRENT_SSID" '.[] | select(. == $ssid)' <<< "$ALLOWED_NETWORKS_JSON" > /dev/null; then
                        echo "$(date) - Rede Wi-Fi '$CURRENT_SSID' não permitida. Pausando." >> "$LOG_FILE"
                        sleep 1800
                        continue
                    fi
                fi
            fi

            local rclone_params_to_use
            local POWER_SUPPLY_PATH="/sys/class/power_supply/AC/online"
            if [ -f "$POWER_SUPPLY_PATH" ] && [ "$(cat "$POWER_SUPPLY_PATH")" -eq 1 ]; then
                rclone_params_to_use=$RCLONE_PARAMS_AC
            else
                rclone_params_to_use=$RCLONE_PARAMS_BATTERY
            fi

            echo "$(date) - Iniciando backup para: '$BACKUP_ID'" >> "$LOG_FILE"
            rclone sync --track-renames $rclone_params_to_use --fast-list "$SOURCE" "$DEST" >> "$LOG_FILE" 2>&1
            echo "$(date) - Sincronização de '$BACKUP_ID' finalizada. Pausa." >> "$LOG_FILE"
            echo "==================================================" >> "$LOG_FILE"
            sleep 1800
        done
    ) 9>"$LOCK_FILE"
}

TASKS_TO_RUN=($(jq -r 'keys_unsorted[] | select(. != "allowed_networks")' "$CONFIG_FILE"))
for task in "${TASKS_TO_RUN[@]}"; do
    run_backup_task "$task" &
done
wait
EOF
    sudo chmod +x "$WORKER_SCRIPT_PATH"
    
    echo "Instalando serviço systemd em $SERVICE_PATH..."
    sudo tee "$SERVICE_PATH" > /dev/null << EOF
[Unit]
Description=Gerenciador de Backups Paralelos
After=network-online.target
[Service]
User=$USER
Type=simple
ExecStart=$WORKER_SCRIPT_PATH
[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    
    read -p "Deseja habilitar e iniciar o serviço de automação agora? (S/n) " enable_choice
    case "$enable_choice" in n|N) ;; *) sudo systemctl enable --now "$SERVICE_NAME" ;; esac
    
    echo "Instalação finalizada!"; read -p "Pressione Enter para ir ao menu..."
}

# --- MENU PRINCIPAL ---
setup
while true; do
    clear
    if [ "$NEEDS_RESTART" = true ]; then echo "========================================================"; echo "AVISO: Você fez alterações que exigem reiniciar o serviço!"; echo "========================================================"; fi
    echo "--- Ferramenta de Gerenciamento de Backups ---"
    echo "1. Gerenciar Tarefas de Backup (Add/Remove)"
    echo "2. Gerenciar Redes Permitidas"
    echo "3. Simular um Backup (Dry Run)"
    echo "4. Gerenciar Serviço (Start/Stop/Enable...)"
    echo "5. Ver Logs de uma Tarefa"
    echo
    echo "9. Desinstalar (Limpeza Completa)"
    echo "S. Sair"
    echo "--------------------------------------------"
    read -p "Escolha uma opção: " main_choice
    case "$main_choice" in
        1)
            while true; do list_tasks; echo; echo "1. Adicionar Tarefa | 2. Remover Tarefa | V. Voltar"; read -p "> " task_choice
            case "$task_choice" in 1) add_task;; 2) remove_task;; V|v) break;; *) echo "Inválido"; sleep 1;; esac; done
            ;;
        2) manage_networks ;;
        3) run_dry_run ;;
        4) manage_service ;;
        5) view_logs ;;
        9) uninstall_system ;;
        S|s) break ;;
        *) echo "Opção inválida."; sleep 1 ;;
    esac
done
echo "Até logo!"