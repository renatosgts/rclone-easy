#!/bin/bash

add_task() {
    clear; echo "--- Adicionar Nova Tarefa ---"
    read -p "Digite um identificador único para a nova tarefa: " id
    if [ -z "$id" ]; then show_message "error" "Erro" "O identificador não pode ser vazio."; return; fi
    if jq -e --arg id "$id" 'has($id)' "$CONFIG_FILE" > /dev/null; then show_message "error" "Erro" "O identificador '$id' já existe."; return; fi

    show_message "info" "Passo 1: Pasta de Origem" "Selecione a pasta PRINCIPAL que contém os dados para o backup."
    local source_path
    source_path=$(fzf_file_browser "$HOME" "/tmp/fzf_single_selection.tmp" "single")
    if [ $? -ne 0 ]; then show_message "warning" "Ação Cancelada" "Criação de tarefa cancelada."; return; fi
    
    read -p "Passo 2: Digite o destino no rclone (ex: gdrive:backup/$id): " dest

    local sync_mode
    while true; do
        clear
        echo "--- Passo 3: Modo de Sincronização ---"
        echo "Como esta tarefa de backup ('$id') deve funcionar?"
        echo
        echo "1. Modo Completo (Padrão)"
        echo "   ↳ Sincroniza todos os arquivos e pastas dentro de '$source_path',"
        echo "     respeitando automaticamente as regras do arquivo .gitignore, se existir."
        echo
        echo "2. Modo de Inclusão Específica"
        echo "   ↳ Sincroniza SOMENTE os arquivos e subpastas que você selecionar manualmente."
        echo
        read -p "Escolha o modo (1 ou 2): " mode_choice
        case "$mode_choice" in
            1) sync_mode="Completo"; break ;;
            2) sync_mode="Inclusão"; break ;;
            *) show_message "error" "Erro" "Opção inválida. Escolha 1 ou 2.";;
        esac
    done

    jq --arg id "$id" --arg src "$source_path" --arg dst "$dest" --arg mode "$sync_mode" \
    '. + {($id): {"source": $src, "destination": $dst, "sync_mode": $mode, "includes": []}}' \
    "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

    show_message "info" "Sucesso" "Tarefa '$id' adicionada com o modo '$sync_mode'."
    NEEDS_RESTART=true

    if [[ "$sync_mode" == "Inclusão" ]]; then
        show_message "info" "Próximo Passo" "Agora, selecione os arquivos/pastas para incluir no backup."
        configure_includes "$id"
    fi
}

edit_task() {
    local task_id="$1" 
    if [ -z "$task_id" ]; then
        show_message "error" "Erro Interno" "A função de edição foi chamada sem um ID de tarefa."
        return
    fi
    
    while true; do
        local sync_mode=$(jq -r --arg id "$task_id" '.[$id].sync_mode // "Completo"' "$CONFIG_FILE")
        local task_info=$(jq -r --arg id "$task_id" '.[$id] | "Origem: \(.source | sub($ENV.HOME; "~"))\nDestino: \(.destination)"' "$CONFIG_FILE")
        
        local options=()
        options+=("1. Mudar Origem ou Destino")
        options+=("2. Alterar Modo de Sincronização (Atual: ${sync_mode})")
        if [[ "$sync_mode" == "Inclusão" ]]; then
            options+=("3. Configurar Arquivos Incluídos")
        fi
        options+=("V. Voltar")

        clear
        echo "--- Editando Tarefa: $task_id ---"
        echo -e "$task_info"
        echo "--------------------------------"
        
        local choice=$(printf "%s\n" "${options[@]}" | fzf --height="~25%" --layout=reverse --prompt="O que deseja alterar? > ")
        local action_char=$(echo "$choice" | cut -d'.' -f1)

        case "$action_char" in
            1)
                local current_source=$(jq -r --arg id "$task_id" '.[$id].source' "$CONFIG_FILE" | envsubst)
                local current_dest=$(jq -r --arg id "$task_id" '.[$id].destination' "$CONFIG_FILE" | envsubst)
                show_message "info" "Nova Origem" "Selecione o novo diretório de origem."
                local new_source=$(fzf_file_browser "$current_source" "/tmp/fzf_single_selection.tmp" "single")
                [ $? -ne 0 ] && new_source="$current_source"

                read -e -p "Novo caminho de Destino (atual: $current_dest): " -i "$current_dest" new_dest

                jq --arg id "$task_id" --arg src "$new_source" --arg dst "$new_dest" \
                '.[$id].source = $src | .[$id].destination = $dst' \
                "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                show_message "info" "Sucesso" "Tarefa '$task_id' atualizada!";
                NEEDS_RESTART=true
                ;;
            2)
                local current_mode=$(jq -r --arg id "$task_id" '.[$id].sync_mode // "Completo"' "$CONFIG_FILE")
                local new_mode=$([[ "$current_mode" == "Completo" ]] && echo "Inclusão" || echo "Completo")
                
                read -p "Mudar modo de '$current_mode' para '$new_mode'? (s/N) " confirm
                if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                    jq --arg id "$task_id" --arg mode "$new_mode" '.[$id].sync_mode = $mode' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                    show_message "info" "Sucesso" "Modo da tarefa '$task_id' alterado para '$new_mode'."
                    NEEDS_RESTART=true

                    if [[ "$new_mode" == "Inclusão" ]]; then
                       read -p "Deseja configurar os arquivos a serem incluídos agora? (s/N) " config_now
                       if [[ "$config_now" == "s" || "$config_now" == "S" ]]; then
                           configure_includes "$task_id"
                       fi
                    fi
                else
                    show_message "info" "Cancelado" "A alteração do modo foi cancelada."
                fi
                ;;
            3)
                configure_includes "$task_id"
                ;;
            V|v) break;;
            *) 
                if [ -z "$choice" ]; then
                    break
                fi
                ;;
        esac
    done
}

configure_includes() {
    local task_id="$1"
    if [ -z "$task_id" ]; then
        show_message "error" "Erro" "ID da tarefa não fornecido para configurar inclusões." 
        return 
    fi

    if ! jq -e --arg id "$task_id" '.[$id]' "$CONFIG_FILE" > /dev/null; then 
        show_message "error" "Erro" "Tarefa '$task_id' não encontrada." 
        return 
    fi
    
    local sync_mode=$(jq -r --arg id "$task_id" '.[$id].sync_mode // "Completo"' "$CONFIG_FILE") 
    if [[ "$sync_mode" != "Inclusão" ]]; then 
        show_message "warning" "Modo Incorreto" "Esta função é para tarefas em 'Modo de Inclusão'." 
        return 
    fi
    
    local source_dir=$(jq -r --arg id "$task_id" '.[$id].source' "$CONFIG_FILE" | envsubst) 
    if [ ! -d "$source_dir" ]; then 
        show_message "error" "Erro de Caminho" "O 'source' ('$source_dir') não é um diretório válido." 
        return 
    fi

    # Arquivo temporário para gerenciar a lista de inclusões durante a edição
    local selection_file="/tmp/backup_selection_${task_id}.txt"
    # Popula o arquivo de estado com as seleções atuais
    jq -r --arg id "$task_id" '.[$id].includes[]?' "$CONFIG_FILE" | sed 's|/\*\*||' > "$selection_file" 

    while true; do
        clear
        echo "--- Configurando Inclusões para: $task_id ---"
        echo "Origem do Backup: $source_dir"
        echo "-----------------------------------------------------"
        echo "Arquivos e Pastas Atualmente na Lista de Backup:"
        if [ -s "$selection_file" ]; then
            cat "$selection_file" | sed 's/^/  ✔ /'
        else
            echo "  (Nenhum item selecionado)"
        fi
        echo "-----------------------------------------------------"
        echo "A. Adicionar arquivos/pastas (usando o navegador)"
        echo "R. Remover um item da lista"
        echo "S. Salvar e Voltar ao menu anterior"
        echo "C. Cancelar (descartar alterações)"
        echo "-----------------------------------------------------"
        read -p "Escolha uma opção: " choice

        case "$choice" in
            A|a)
                # Chama o navegador de arquivos para selecionar novos itens
                local new_items
                new_items=$(fzf_file_browser "$source_dir" "/dev/null" "multi") # Passamos /dev/null para evitar confusão

                if [ $? -eq 0 ] && [ -n "$new_items" ]; then
                    # Adiciona os novos itens ao arquivo de seleção, sem duplicatas
                    (echo "$new_items"; cat "$selection_file") | sort -u > "$selection_file.tmp"
                    mv "$selection_file.tmp" "$selection_file"
                    show_message "info" "Itens Adicionados" "A lista foi atualizada."
                else
                    show_message "info" "Nenhuma Seleção" "Nenhum item novo foi adicionado."
                fi
                ;;
            R|r)
                if [ ! -s "$selection_file" ]; then
                    show_message "warning" "Lista Vazia" "Não há itens para remover."
                    continue
                fi
                # Usa fzf para selecionar um item da lista atual para remoção
                local item_to_remove
                item_to_remove=$(cat "$selection_file" | fzf --prompt="Selecione o item para REMOVER > " --height="~30%")
                
                if [ -n "$item_to_remove" ]; then
                    # Remove o item selecionado do arquivo de estado
                    grep -vFx "$item_to_remove" "$selection_file" > "$selection_file.tmp"
                    mv "$selection_file.tmp" "$selection_file"
                    show_message "info" "Item Removido" "'$item_to_remove' foi removido da lista."
                fi
                ;;
            S|s)
                # Constrói o novo array JSON a partir do arquivo de seleção final
                local new_includes_json="[]"
                while IFS= read -r item; do 
                    if [ -n "$item" ]; then 
                        local final_item="$item"
                        if [ -d "$source_dir/$item" ]; then 
                            final_item="${item}/**" 
                        fi
                        new_includes_json=$(jq --arg i "$final_item" '. + [$i]' <<< "$new_includes_json")
                    fi
                done < "$selection_file"
                
                # Salva a nova lista no arquivo de configuração principal
                jq --argjson newlist "$new_includes_json" --arg id "$task_id" '.[$id].includes = $newlist' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE" 
                show_message "info" "Sucesso" "Configuração de inclusões para '$task_id' salva!" 
                NEEDS_RESTART=true 
                rm -f "$selection_file" 
                return 0
                ;;
            C|c)
                show_message "warning" "Ação Cancelada" "Nenhuma alteração foi salva." 
                rm -f "$selection_file" 
                return 1
                ;;
            *)
                show_message "error" "Opção Inválida" "Por favor, escolha uma das opções do menu."
                ;;
        esac
    done
}

show_task_menu() {
    while true; do
        local tasks_list
        if [ -f "$CONFIG_FILE" ] && [ "$(jq 'del(.allowed_networks) | length' "$CONFIG_FILE")" -gt 0 ]; then
             tasks_list=$(jq -r 'to_entries[] | select(.key != "allowed_networks") | "▶️ \(.key) | Modo: \(.value.sync_mode // "Completo")"' "$CONFIG_FILE")
        else
            tasks_list="(Nenhuma tarefa configurada)"
        fi
        
        local actions=(
            "---------------------------------------"
            "➕ Adicionar Nova Tarefa"
            "🗑️ Remover Tarefa"
            "🚪 Voltar ao Menu Principal"
        )
        
        local full_list="$tasks_list\n$(printf "%s\n" "${actions[@]}")"
        
        local choice=$(echo -e "$full_list" | fzf \
            --height="~60%" \
            --layout=reverse \
            --prompt="Selecione uma Tarefa para Editar ou uma Ação > " \
            --header="[ENTER] para selecionar" \
            --no-multi)
            
        if [ -z "$choice" ]; then return; fi

        case "$choice" in
            "➕ Adicionar Nova Tarefa") add_task ;;
            "🗑️ Remover Tarefa")
                local tasks_to_remove=$(jq -r 'keys_unsorted | map(select(. != "allowed_networks")) | .[]' "$CONFIG_FILE")
                if [ -z "$tasks_to_remove" ]; then
                    show_message "info" "Vazio" "Nenhuma tarefa para remover."
                    continue
                fi
                
                local task_to_remove=$(echo "$tasks_to_remove" | fzf --prompt="Selecione a tarefa para REMOVER > " --height="~30%")
                
                if [ -n "$task_to_remove" ]; then
                    read -p "Tem certeza que deseja remover a tarefa '$task_to_remove'? (s/N) " confirm
                    if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                        jq --arg id "$task_to_remove" 'del(.[$id])' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                        show_message "info" "Sucesso" "Tarefa '$task_to_remove' removida."
                        NEEDS_RESTART=true
                    else
                        show_message "info" "Cancelado" "A remoção foi cancelada."
                    fi
                fi
                ;;
            "🚪 Voltar ao Menu Principal") return ;;
            "---------------------------------------" | "(Nenhuma tarefa configurada)") ;; 
            *)
                local task_id=$(echo "$choice" | cut -d'|' -f1 | sed 's/▶️ //g' | xargs)
                if [ -n "$task_id" ]; then
                    edit_task "$task_id"
                fi
                ;;
        esac
    done
}