#!/bin/bash

# MUDANÇA: Nova função para instalar o fzf a partir do repositório oficial
install_fzf_from_git() {
    read -p "Deseja clonar e instalar a versão mais recente do fzf agora (Recomendado)? (S/n) " choice
    case "$choice" in
        n|N)
            show_message "warning" "Ação Requerida" "A funcionalidade completa do script requer a versão mais recente do fzf."
            return 1
            ;;
        *)
            echo "Instalando fzf do repositório oficial..."
            if [ -d "$HOME/.fzf" ]; then
                echo "Diretório $HOME/.fzf já existe. Tentando atualizar..."
                (cd "$HOME/.fzf" && git pull)
                "$HOME/.fzf/install" --all
            else
                if ! git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"; then
                    show_message "error" "Falha no Clone" "Não foi possível clonar o repositório do fzf. Verifique sua conexão e se o git está instalado."
                    return 1
                fi
                # A opção --all instala para os shells disponíveis sem fazer perguntas
                "$HOME/.fzf/install" --all
            fi
            
            show_message "info" "Ação Necessária" "FZF foi instalado/atualizado com sucesso.\n\nPara que as mudanças tenham efeito, por favor:\n1. Feche e reabra seu terminal.\n2. Execute o script './gerenciar-backups.sh' novamente."
            exit 0
            ;;
    esac
}

run_setup() {
    echo "--- Verificando Instalação do Sistema de Backup ---"
    
    # MUDANÇA: Adicionado 'git' à lista de dependências essenciais
    for cmd in jq nmcli git; do
        if ! command -v $cmd &> /dev/null; then
            echo "Dependência essencial '$cmd' não encontrada."
            read -p "Deseja tentar instalar o pacote '$cmd' agora? (S/n) " c
            case "$c" in
                n|N) exit 1 ;;
                *) sudo apt-get update && sudo apt-get install -y "$cmd" ;;
            esac
        fi
    done
    
    # MUDANÇA: Lógica de verificação específica e melhorada para o FZF
    echo "Verificando a instalação do fzf..."
    if ! command -v fzf &> /dev/null; then
        echo "O comando 'fzf' não foi encontrado no sistema."
        install_fzf_from_git
    else
        # Verifica se a versão instalada é a do apt ou a do git. A do git cria o diretório ~/.fzf
        if [ ! -d "$HOME/.fzf" ]; then
            echo "Você possui uma versão do fzf instalada via 'apt' que pode ser incompatível."
            install_fzf_from_git
        else
            echo "Versão recomendada do fzf encontrada."
        fi
    fi
    
    [ ! -f "$CONFIG_FILE" ] && echo "{}" > "$CONFIG_FILE"
    if ! jq -e '.allowed_networks' "$CONFIG_FILE" > /dev/null; then
        jq '. + {"allowed_networks": []}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi

    if [ ! -f "$WORKER_SCRIPT_PATH" ]; then
        echo "Componentes principais não instalados."
        read -p "Realizar a instalação inicial agora? (S/n) " install_choice
        case "$install_choice" in n|N) return ;; esac
        
        echo "Instalando script de trabalho em $WORKER_SCRIPT_PATH..."
        sudo cp "$BASE_DIR/worker/backup_worker.sh" "$WORKER_SCRIPT_PATH"
        sudo chmod +x "$WORKER_SCRIPT_PATH"
        
        echo "Instalando serviço systemd..."
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
        
        echo "Instalação finalizada!";
        read -p "Pressione Enter para ir ao menu..."
    fi
}