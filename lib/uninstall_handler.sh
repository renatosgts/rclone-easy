#!/bin/bash

run_uninstall() {
    clear
    echo "!! ATENÇÃO: AÇÃO DESTRUTIVA E IRREVERSÍVEL !!"
    echo "Esta opção removerá TODOS os componentes deste sistema de backup:"
    echo " - O serviço systemd ($SERVICE_NAME)"
    echo " - O script de trabalho ($WORKER_SCRIPT_PATH)"
    echo " - O arquivo de configuração de tarefas ($CONFIG_FILE)"
    echo " - TODOS os arquivos de log de backup ($HOME/.backup_gdrive_*.log)"
    echo " - TODOS os arquivos de trava (/tmp/backup_gdrive_*.lock)"
    echo
    read -p "Você tem certeza ABSOLUTA que deseja continuar? (s/N) " confirm

    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        echo "Desinstalação cancelada."
        sleep 2
        return
    fi

    echo
    read -p "Para confirmar, por favor, digite a palavra 'confirmar': " final_confirm
    if [ "$final_confirm" != "confirmar" ]; then
        echo "Confirmação incorreta. Desinstalação cancelada."
        sleep 2
        return
    fi

    echo "Iniciando a limpeza completa..."
    # 1. Parar e desabilitar o serviço
    if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
        echo "Parando e desabilitando o serviço..."
        sudo systemctl disable --now "$SERVICE_NAME" &>/dev/null
    fi
    
    # 2. Remover arquivos do sistema
    echo "Removendo arquivos do sistema..."
    [ -f "$SERVICE_PATH" ] && sudo rm -f "$SERVICE_PATH"
    [ -f "$WORKER_SCRIPT_PATH" ] && sudo rm -f "$WORKER_SCRIPT_PATH"
    
    # 3. Recarregar o systemd
    sudo systemctl daemon-reload

    # 4. Remover arquivos do usuário
    echo "Removendo arquivos de configuração, logs e travas do usuário..."
    [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE"
    rm -f "$HOME"/.backup_gdrive_*.log
    rm -f /tmp/backup_gdrive_*.lock

    echo
    echo "Limpeza completa realizada com sucesso."
    echo "O script de gerenciamento e seus componentes na pasta 'lib' não foram removidos. Você pode removê-los manualmente."
    read -p "Pressione Enter para sair do script."
    exit 0
}