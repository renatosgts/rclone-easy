# Suíte de Backup Inteligente para Linux com Rclone

## 1. Visão Geral

Este projeto é uma suíte de automação de backup completa, "inteligente" e de fácil gerenciamento para sistemas Linux. Utilizando `rclone` como motor de sincronização, o sistema automatiza o envio de arquivos de múltiplos diretórios locais para um provedor de armazenamento em nuvem.

O grande diferencial deste projeto é sua **arquitetura modular** e sua **interface de usuário avançada**. Através de um único script interativo (`gerenciar-backups.sh`), qualquer usuário pode instalar, configurar e monitorar múltiplas tarefas de backup usando um navegador de arquivos interativo no terminal. A ferramenta se adapta ao ambiente do usuário, ajustando sua performance com base na fonte de energia e restringindo operações a redes Wi-Fi pré-aprovadas.

## 2. Funcionalidades Principais

-   **Arquitetura Modular:** O código é dividido em múltiplos arquivos com responsabilidades únicas (gerenciamento, setup, worker, etc.), facilitando a manutenção e a extensão do projeto.
-   **Navegador de Arquivos Interativo (`fzf`):** Em vez de digitar caminhos, o usuário utiliza uma interface fluida para navegar por diretórios com `Enter`, selecionar arquivos e pastas com `Espaço`, e salvar seleções complexas para o backup.
-   **Gerenciamento Total via Menu:** Um script central oferece um menu amigável para controlar todo o sistema: instalação, gerenciamento de tarefas (Adicionar/Remover/Editar), configuração da whitelist de redes, controle do serviço `systemd`, simulação de backups e desinstalação segura.
-   **Backups Inteligentes e Conscientes de Contexto:**
    -   **Otimização de Energia:** Ajusta os parâmetros de performance do `rclone` se o notebook está na bateria ou na tomada.
    -   **Whitelist de Redes Wi-Fi:** Executa backups apenas em redes Wi-Fi autorizadas.
-   **Filtragem de Arquivos Avançada:**
    -   **Seleção de Inclusão por Navegação:** Permite selecionar recursivamente arquivos e pastas específicos para tarefas de backup complexas (como dotfiles).
    -   **Suporte a `.gitignore` e `.hidden`:** Respeita automaticamente as regras de exclusão para tarefas de backup de diretórios completos.

## 3. Detalhes da Implementação Técnica

O projeto utiliza uma estrutura de múltiplos scripts para separar as responsabilidades:

-   **`gerenciar-backups.sh` (O Orquestrador):** Ponto de entrada que carrega as bibliotecas e exibe o menu principal.
-   **`lib/` (A Biblioteca de Funções):** Contém a lógica de negócios dividida em módulos:
    -   `setup_handler.sh`: Cuida da instalação e dependências.
    -   `task_handler.sh`: Funções para CRUD (Create, Read, Update, Delete) de tarefas de backup.
    -   `includes_selector.sh`: O poderoso navegador de arquivos `fzf` para seleção interativa.
    -   E outros para gerenciar redes, serviços e logs.
-   **`worker/backup_worker.sh` (O "Worker"):** O motor do sistema, iniciado pelo `systemd`. Ele lê o `backup_tasks.json`, verifica o contexto e lança os processos de backup em paralelo.
-   **Ferramentas Utilizadas:** `rclone`, `jq`, `fzf`, `nmcli`, `systemd`, `flock`.

## 4. Como Executar

1.  **Clonar o Repositório:**
    ```bash
    git clone https://github.com/renatosgts/rclone-easy.git
    cd rclone-easy
    ```

2.  **Dar Permissão de Execução:**
    Dê permissão aos dois scripts principais.
    ```bash
    chmod +x gerenciar-backups.sh
    chmod +x lib/includes_selector.sh
    ```

3.  **Executar o Script de Gerenciamento:**
    Este é o único passo manual. O script cuidará de todo o resto.
    ```bash
    ./gerenciar-backups.sh
    ```
    - Na primeira execução, o script guiará pela instalação das dependências (`jq`, `fzf`) e pela configuração do serviço `systemd`.
    - Use o menu interativo para configurar suas tarefas, usando o navegador de arquivos para selecionar as pastas de origem com `Enter` e `Espaço`.