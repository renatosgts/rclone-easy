#!/bin/bash

# VERSÃO REFATORADA - Compatível com fzf moderno.
# Remove o gerenciamento de estado em tempo real para focar na estabilidade.

# FUNÇÃO PRINCIPAL: O CONTROLADOR DO NAVEGADOR
fzf_file_browser() {
    local START_DIR="$1"
    # O arquivo de estado não é mais usado para a lógica principal, apenas para pré-seleção.
    local SELECTION_STATE_FILE="$2"
    local MODE="$3"

    if [ ! -d "$START_DIR" ]; then
        show_message "error" "Erro Interno" "Diretório inicial inválido: '$START_DIR'"
        return 1
    fi

    local CURRENT_DIR="$START_DIR"
    local task_id
    task_id=$(basename "$SELECTION_STATE_FILE" | sed -e 's/backup_selection_//' -e 's/\.txt//')
    local history_file="/tmp/fzf_history_${task_id}"

    # Gera a lista de arquivos do diretório atual
    # Para o modo 'multi', pré-seleciona os itens que já estão no arquivo de configuração
    local input_generator="ls -A1 '$CURRENT_DIR'"
    
    while true; do
        local fzf_header
        local fzf_bindings=()
        local fzf_optional_args=()

        if [[ "$MODE" == "multi" ]]; then
            fzf_header="[TAB] Marca/Desmarca | [CTRL+S] Salva | [CTRL+P/N] Histórico | [ESC] Cancela"
            fzf_bindings+=(
                --bind "ctrl-s:accept+bell"
                --bind "ctrl-p:previous-history"
                --bind "ctrl-n:next-history"
            )
            # Habilita o modo de seleção múltipla do fzf
            fzf_optional_args+=(--multi)

        else # single mode
            fzf_header="[ENTER] Seleciona | [ESC] Cancela"
            # O modo single não precisa de bindings especiais aqui
        fi
        
        # Adiciona a opção de subir de nível no topo da lista
        local full_input
        full_input=$( (echo ".. (Subir de nível)"; ls -A1 "$CURRENT_DIR") )


        local selection
        selection=$(
            echo -e "$full_input" |
            fzf --prompt="[$CURRENT_DIR] > " \
                --height="80%" --reverse \
                --header="$fzf_header" \
                --ansi \
                --bind "enter:accept" \
                --bind "esc:abort" \
                "${fzf_bindings[@]}" \
                "${fzf_optional_args[@]}" \
                \
                --border="bold" \
                --border-label=" Selecionando Itens " \
                --info="inline" \
                --pointer="➜" \
                --marker="✔" \
                --cycle \
                --scrollbar="┃" \
                --history="$history_file" \
                --ghost="Digite para filtrar..." \
                --preview="ls -ld --color=always '$CURRENT_DIR'/$(echo {} | sed 's/.. (Subir de nível)//') 2>/dev/null"
        )

        # Se o usuário pressionou ESC, a saída é vazia.
        if [ -z "$selection" ]; then
            # No modo multi, se o usuário cancela, retornamos o estado original do arquivo.
            if [[ "$MODE" == "multi" ]]; then
                cat "$SELECTION_STATE_FILE"
                return 0
            else
                return 1
            fi
        fi

        # Se o usuário selecionou para subir de nível
        if [[ "$selection" == ".. (Subir de nível)" ]]; then
            CURRENT_DIR=$(dirname "$CURRENT_DIR")
            continue
        fi

        # Se chegamos aqui, o usuário fez uma seleção válida.

        if [[ "$MODE" == "multi" ]]; then
            # Para o modo multi, a saída do fzf (a variável $selection) já é a lista
            # final de arquivos selecionados, separados por nova linha.
            # Convertemos os caminhos para serem relativos ao diretório inicial.
            local final_selection=""
            while IFS= read -r item; do
                local relative_path
                relative_path=$(realpath --relative-to="$START_DIR" "$CURRENT_DIR/$item" 2>/dev/null || echo "$item")
                final_selection+="$relative_path\n"
            done <<< "$selection"

            echo -e "$final_selection"
            return 0
        else # single mode
            local selected_path="$CURRENT_DIR/$selection"
            realpath "$selected_path" 2>/dev/null || echo "$selected_path"
            return 0
        fi
    done
}