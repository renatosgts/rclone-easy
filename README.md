# Suíte de Backup Inteligente para Linux com Rclone

## 1. Visão Geral

Este projeto é uma suíte de automação de backup completa, "inteligente" e de fácil gerenciamento para sistemas Linux. Utilizando `rclone` como motor de sincronização, o sistema automatiza o envio de arquivos de múltiplos diretórios locais para um provedor de armazenamento em nuvem (como Google Drive, Dropbox, S3, etc.).

O grande diferencial deste projeto é sua camada de gerenciamento e sua **consciência de contexto**. Através de um único script interativo, qualquer usuário pode instalar, configurar, monitorar e até desinstalar o sistema por completo. A ferramenta é inteligente o suficiente para se adaptar ao ambiente do usuário, ajustando sua performance com base na fonte de energia (bateria ou tomada) e restringindo suas operações a redes Wi-Fi pré-aprovadas, tornando-a ideal para notebooks e desktops.

A solução foi desenhada para ser executada como um serviço `systemd`, garantindo que os backups rodem continuamente em segundo plano, iniciem com o sistema e se recuperem de falhas de forma autônoma.

## 2. Funcionalidades Principais

Esta suíte de backup foi construída com foco em robustez, automação e facilidade de uso.

#### Gerenciamento Total via Menu Interativo
A complexidade do sistema é abstraída por um único script de gerenciamento (`gerenciar-backups.sh`), que oferece:
-   **Instalação Guiada:** Detecta e instala dependências (`jq`, `wireless-tools`) e cria todos os componentes do sistema na primeira execução.
-   **Gerenciamento de Tarefas:** Um sub-menu para adicionar e remover tarefas de backup de forma interativa, atualizando o arquivo de configuração central.
-   **Controle de Serviço `systemd`:** Um sub-menu completo para iniciar, parar, reiniciar, habilitar e desabilitar o serviço de backup, além de verificar seu status detalhado.
-   **Desinstalação Segura:** Uma opção de "limpeza completa" que remove todos os arquivos, logs e serviços criados, com uma dupla confirmação de segurança para evitar acidentes.

#### Backups Inteligentes e Conscientes de Contexto
O sistema se adapta ao ambiente para otimizar recursos e respeitar as preferências do usuário:
-   **Otimização de Energia:** Detecta se o dispositivo está na bateria ou na tomada e ajusta os parâmetros de performance do `rclone` (transferências, limite de banda) para economizar energia.
-   **Whitelist de Redes Wi-Fi:** O backup só é executado em redes Wi-Fi previamente autorizadas no menu. Conexões cabeadas são sempre permitidas. O gerenciamento da lista é totalmente interativo, incluindo uma opção para adicionar a rede atual com um clique.

#### Filtragem de Arquivos Automática e Precisa
-   **Suporte a `.gitignore`:** Respeita automaticamente as regras de exclusão de qualquer arquivo `.gitignore` encontrado na raiz de uma pasta de backup, ideal para projetos de desenvolvimento.
-   **Suporte a `.hidden`:** Também obedece ao arquivo `.hidden` (usado por gerenciadores de arquivos do Linux para ocultar itens), excluindo os arquivos listados do backup.

#### Execução Robusta e Segura
-   **Backups Paralelos e Independentes:** Cada tarefa de backup roda em seu próprio processo, de forma paralela. Um backup grande ou lento não impede que outros backups menores sejam executados.
-   **Prevenção de Concorrência (`flock`):** Utiliza `flock` para criar um arquivo de trava exclusivo para cada tarefa, impedindo execuções simultâneas da mesma tarefa e prevenindo corrupção de dados.
-   **Simulação Segura (`--dry-run`):** O menu oferece uma opção para simular qualquer tarefa de backup, mostrando o que o `rclone` faria sem alterar nenhum arquivo real.
-   **Otimização de Renomeação:** Utiliza a flag `--track-renames` do `rclone` para economizar banda e tempo, detectando arquivos/pastas renomeados em vez de deletá-los e reenviá-los.

#### Configuração Centralizada e Portátil
-   **Uso de JSON:** Todas as tarefas e configurações são definidas em um único arquivo `backup_tasks.json`, separando a configuração da lógica.
-   **Portabilidade Total:** O script não contém nenhum nome de usuário ou caminho fixo. Ele se adapta automaticamente ao usuário que o instala, usando variáveis de ambiente como `$HOME` e `$USER`.

## 3. Detalhes da Implementação Técnica

O sistema é composto por uma ferramenta de gerenciamento, um script de trabalho, um arquivo de configuração JSON e um serviço `systemd`.

-   **`gerenciar-backups.sh` (O Orquestrador):** A interface de usuário do projeto. É responsável pelo setup, edição do JSON e controle do serviço `systemd`.
-   **`backup-drive.sh` (O "Worker"):** O motor do sistema, iniciado pelo `systemd`. Ele lê o `backup_tasks.json`, verifica o contexto (rede, energia) e lança os processos de backup em segundo plano com os parâmetros apropriados, além de aplicar os filtros de exclusão (`.gitignore`, `.hidden`).
-   **`backup_tasks.json` (A Configuração):** O "banco de dados" do sistema. Armazena as tarefas de backup (com origem e destino) e a lista de redes Wi-Fi permitidas (`allowed_networks`).
-   **`backup-manager.service` (O Serviço `systemd`):** Garante que o script "worker" esteja sempre em execução. É criado dinamicamente para o usuário que executa o setup.
-   **Ferramentas Utilizadas:**
    -   `rclone`: Backend para a sincronização, usando flags como `sync`, `--exclude-from`, `--track-renames`, `--dry-run`.
    -   `jq`: Utilitário essencial para ler e escrever no arquivo de configuração JSON de forma segura.
    -   `nmcli`: Ferramenta moderna do NetworkManager usada para obter o SSID da rede Wi-Fi atual.
    -   `/sys/class/power_supply/`: Acessado para verificar o status da fonte de energia (bateria ou AC).
    -   `flock`: Usado para a trava de processos, garantindo que apenas uma instância de cada tarefa de backup execute por vez.

## 4. Como Executar

Siga os passos abaixo para que qualquer usuário instale e configure o sistema em uma máquina Linux moderna baseada em Debian/Ubuntu.

### Pré-requisitos

1.  **Rclone:** Deve estar instalado e configurado. O comando `rclone listremotes` deve funcionar e mostrar seu remote de nuvem.
2.  **Git:** Necessário para clonar o repositório (`sudo apt install git`).

### Instalação

1.  **Clonar o Repositório:**
    ```bash
    git clone [https://github.com/seu-usuario/seu-repositorio.git](https://github.com/seu-usuario/seu-repositorio.git)
    cd seu-repositorio
    ```

2.  **Executar o Script de Gerenciamento:**
    Este é o único passo manual. O script cuidará de todo o resto, configurando o sistema para o seu usuário atual.
    ```bash
    chmod +x gerenciar-backups.sh
    ./gerenciar-backups.sh
    ```

### Primeira Execução e Uso

-   Na primeira execução, o script verificará as dependências (`jq`, etc.) e oferecerá para instalá-las.
-   Em seguida, ele criará os componentes necessários (o script "worker" e o serviço `systemd`) e perguntará se você deseja habilitar e iniciar o serviço de automação.
-   Após o setup, você será apresentado ao menu principal.

### Gerenciamento (O Menu Principal)

Execute `./gerenciar-backups.sh` a qualquer momento para acessar o menu de gerenciamento.

-   **`1. Gerenciar Tarefas de Backup`**: Abre um sub-menu para Adicionar ou Remover pastas a serem backupeadas.
-   **`2. Gerenciar Redes Permitidas`**: Abre um sub-menu para controlar em quais redes Wi-Fi o backup pode rodar. Inclui uma opção para adicionar a rede atual automaticamente.
-   **`3. Simular um Backup (Dry Run)`**: Permite testar qualquer tarefa de backup, mostrando o que o `rclone` faria sem alterar nenhum arquivo.
-   **`4. Gerenciar Serviço (Start/Stop/Enable...)`**: Abre um sub-menu completo para controlar o serviço `systemd`: iniciar, parar, reiniciar, habilitar ou desabilitar na inicialização do sistema.
-   **`5. Ver Logs de uma Tarefa`**: Permite escolher uma tarefa e visualizar seu arquivo de log em tempo real.
-   **`9. Desinstalar (Limpeza Completa)`**: Remove de forma segura todos os arquivos, logs e serviços criados por esta ferramenta, após uma dupla confirmação.