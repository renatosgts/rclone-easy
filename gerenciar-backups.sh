#!/bin/bash
#set -x ; exec 2> "$HOME/$(date +"%Y%m%d_%H%M%S").debug.log"
# =================================================================
# FERRAMENTA DE GERENCIAMENTO DE BACKUPS (V. COM MENU FZF)
# =================================================================

# --- Variáveis Globais e Carregamento de Bibliotecas ---
BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export WORKER_SCRIPT_PATH="/usr/local/bin/backup-drive.sh"
export CONFIG_FILE="$HOME/backup_tasks.json"
export SERVICE_NAME="backup-manager.service"
export SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
export NEEDS_RESTART=false

show_message() { local type="$1"; local title="$2"; local message="$3"; echo; echo "--- [${type^^}] $title ---"; echo -e "$message"; echo "---------------------------------"; if [[ "$type" == "error" || "$type" == "warning" ]]; then read -p "Pressione Enter para continuar..."; fi; }; export -f show_message
for lib_file in "$BASE_DIR"/lib/*.sh; do source "$lib_file"; done

# --- LÓGICA PRINCIPAL ---
run_setup

while true; do
    clear
    if [ "$NEEDS_RESTART" = true ]; then
        echo "========================================================"
        echo "AVISO: Você fez alterações que exigem reiniciar o serviço!"
        echo "========================================================"
    fi

    # Define as opções do menu
    options=(
        "1. Gerenciar Tarefas de Backup (Add/Remove/Edit/Includes)"
        "2. Gerenciar Redes Permitidas"
        "3. Simular um Backup (Dry Run)"
        "4. Gerenciar Serviço (Start/Stop/Status...)"
        "5. Ver Logs de uma Tarefa"
        "9. Desinstalar (Limpeza Completa)"
        "S. Sair"
    )

    # Se uma reinicialização for necessária, adiciona a opção ao menu
    if [ "$NEEDS_RESTART" = true ]; then
        options+=("R. Reiniciar Serviço para Aplicar Mudanças")
    fi
    
    # Usa fzf para criar o menu interativo
    main_choice=$(printf "%s\n" "${options[@]}" | fzf --height="~50%" --layout=reverse --prompt="Escolha uma opção > " --header="Use as setas ou digite para filtrar, [ENTER] para selecionar")

    # Pega apenas o número ou letra inicial da escolha
    action_char=$(echo "$main_choice" | cut -d'.' -f1)

    case "$action_char" in
        "1") show_task_menu ;;
        "2") show_network_menu ;;
        "3") run_dry_run ;;
        "4") show_service_menu ;;
        "5") view_logs ;;
        "9") run_uninstall ;;
        "R") 
            if [ "$NEEDS_RESTART" = true ]; then
                show_message "info" "Ação" "Reiniciando o serviço..."
                sudo systemctl restart "$SERVICE_NAME"
                NEEDS_RESTART=false
                sleep 1
                show_message "info" "Sucesso" "Serviço reiniciado."
            fi
            ;;
        "S") break ;;
        *) # O usuário pressionou ESC ou a seleção foi vazia
           if [ -z "$main_choice" ]; then
                # Se for ESC, sai do programa
                break
           fi
           ;;
    esac
done

echo "Até logo!"