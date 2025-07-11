#!/bin/bash

show_service_menu() {
    if [ ! -f "$SERVICE_PATH" ]; then
        echo "O serviço systemd não parece estar instalado. Execute a instalação primeiro."
        sleep 3
        return
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
            3) sudo systemctl restart "$SERVICE_NAME"; echo "Serviço reiniciado."; NEEDS_RESTART=false; sleep 1 ;;
            4) sudo systemctl enable "$SERVICE_NAME"; echo "Serviço habilitado para a próxima inicialização."; sleep 2 ;;
            5) sudo systemctl disable "$SERVICE_NAME"; echo "Serviço desabilitado da próxima inicialização."; sleep 2 ;;
            6) clear; sudo systemctl status "$SERVICE_NAME"; read -p "Pressione Enter para voltar..." ;;
            V|v) break ;;
            *) echo "Opção inválida."; sleep 1 ;;
        esac
    done
}