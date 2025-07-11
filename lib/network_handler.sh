#!/bin/bash

show_network_menu() {
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
            V|v)
                break
                ;;
            *)
                echo "Opção inválida."
                sleep 1
                ;;
        esac
    done
}