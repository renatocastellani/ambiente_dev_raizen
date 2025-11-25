#!/bin/bash

# Script para recriar o .vscode/launch.json para debug de DAGs do Airflow
# Autor: GitHub Copilot

# Configurações Iniciais
DEFAULT_VENV_PATH="$HOME/venv-datahub-dev"
AIRFLOW_BIN="$DEFAULT_VENV_PATH/bin/airflow"
PYTHON_BIN="$DEFAULT_VENV_PATH/bin/python"

# Função para verificar se o comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 1. Perguntar sobre o workspace
CURRENT_DIR=$(pwd)
read -p "Gravar launch.json no workspace atual ($CURRENT_DIR)? [S/n] " -r
if [[ $REPLY =~ ^[Nn]$ ]]; then
    read -p "Informe o caminho do workspace: " WORKSPACE_DIR
else
    WORKSPACE_DIR="$CURRENT_DIR"
fi

if [ ! -d "$WORKSPACE_DIR" ]; then
    echo "Erro: Diretório '$WORKSPACE_DIR' não existe."
    exit 1
fi

# 2. Procurar pastas 'dags' (max 4 níveis)
echo "Procurando pastas 'dags' em $WORKSPACE_DIR..."
DAGS_DIRS=$(find "$WORKSPACE_DIR" -maxdepth 4 -type d -name "dags")

if [ -z "$DAGS_DIRS" ]; then
    echo "Erro: Nenhuma pasta 'dags' encontrada."
    exit 1
fi

# Converter para array para seleção
mapfile -t DAGS_DIR_ARRAY <<< "$DAGS_DIRS"

if [ ${#DAGS_DIR_ARRAY[@]} -gt 1 ]; then
    echo "Múltiplas pastas 'dags' encontradas. Escolha uma:"
    select d in "${DAGS_DIR_ARRAY[@]}"; do
        if [ -n "$d" ]; then
            CHOSEN_DAGS_DIR="$d"
            break
        else
            echo "Opção inválida."
        fi
    done
else
    CHOSEN_DAGS_DIR="${DAGS_DIR_ARRAY[0]}"
fi

echo "Pasta de DAGs selecionada: $CHOSEN_DAGS_DIR"

# Listar arquivos Python na pasta de DAGs
echo "Procurando arquivos de DAG..."
DAG_FILES=$(find "$CHOSEN_DAGS_DIR" -maxdepth 2 -name "*.py")

if [ -z "$DAG_FILES" ]; then
    echo "Erro: Nenhum arquivo Python encontrado em $CHOSEN_DAGS_DIR."
    exit 1
fi

mapfile -t DAG_FILES_ARRAY <<< "$DAG_FILES"

echo "Escolha o arquivo da DAG:"
select dag_file in "${DAG_FILES_ARRAY[@]}"; do
    if [ -n "$dag_file" ]; then
        CHOSEN_DAG_FILE="$dag_file"
        break
    else
        echo "Opção inválida."
    fi
done

echo "Arquivo selecionado: $CHOSEN_DAG_FILE"

# Configurar variáveis de ambiente para o Airflow
# Nota: Não definimos AIRFLOW_HOME ou PYTHONPATH explicitamente para respeitar o ambiente do usuário,
# similar ao script generate_launch.sh de referência.
export AIRFLOW__CORE__DAGS_FOLDER="$CHOSEN_DAGS_DIR"
export AIRFLOW__CORE__LOAD_EXAMPLES="False"

# Tentar extrair o DAG_ID usando o Airflow (importando a DAG)
echo "Identificando DAG ID via Airflow..."

# Verificar se precisa inicializar o DB
if $AIRFLOW_BIN dags list --subdir "$CHOSEN_DAG_FILE" 2>&1 | grep -q -E "no such table|OperationalError"; then
    echo "Banco de dados não inicializado. Executando 'airflow db init'..."
    $AIRFLOW_BIN db init > /dev/null 2>&1
fi

# Obter lista de DAGs em JSON
DAGS_JSON_OUTPUT=$($AIRFLOW_BIN dags list --subdir "$CHOSEN_DAG_FILE" -o json 2>/dev/null)

# Parsear JSON com Python
DETECTED_DAG_IDS=$(python3 -c "
import sys, json
try:
    output = '''$DAGS_JSON_OUTPUT'''
    # Tentar encontrar o início do JSON se houver lixo antes
    start = output.find('[')
    if start != -1:
        output = output[start:]
    
    data = json.loads(output)
    if isinstance(data, list):
        for dag in data:
            print(dag.get('dag_id', ''))
except Exception:
    pass
")

# Converter para array
mapfile -t DAG_IDS_ARRAY <<< "$DETECTED_DAG_IDS"
# Remover linhas vazias
DAG_IDS_ARRAY=($(printf "%s\n" "${DAG_IDS_ARRAY[@]}" | grep -v '^$'))

if [ ${#DAG_IDS_ARRAY[@]} -eq 0 ]; then
    echo "Aviso: Não foi possível detectar DAG ID via Airflow. Tentando método fallback (grep)."
    # Fallback: grep no arquivo
    DETECTED_DAG_ID=$(grep -oP "dag_id=['\"]?\K[^'\",]+" "$CHOSEN_DAG_FILE" | head -1)
    
    if [ -z "$DETECTED_DAG_ID" ]; then
        # Fallback: nome do arquivo sem extensão
        FILENAME=$(basename "$CHOSEN_DAG_FILE")
        DETECTED_DAG_ID="${FILENAME%.*}"
    fi
    DAG_IDS_ARRAY=("$DETECTED_DAG_ID")
fi

if [ ${#DAG_IDS_ARRAY[@]} -gt 1 ]; then
    echo "Múltiplas DAGs encontradas no arquivo. Escolha uma:"
    select d in "${DAG_IDS_ARRAY[@]}"; do
        if [ -n "$d" ]; then
            DAG_ID="$d"
            break
        else
            echo "Opção inválida."
        fi
    done
else
    DAG_ID="${DAG_IDS_ARRAY[0]}"
fi

echo "Usando DAG ID: $DAG_ID"

# 3. Listar tasks da DAG
echo "Listando tasks..."

TASKS=""
if [ -f "$AIRFLOW_BIN" ]; then
    echo "Executando: $AIRFLOW_BIN tasks list $DAG_ID"
    
    # Usar arquivos temporários para separar stdout e stderr
    STDOUT_FILE=$(mktemp)
    STDERR_FILE=$(mktemp)
    
    $AIRFLOW_BIN tasks list "$DAG_ID" > "$STDOUT_FILE" 2> "$STDERR_FILE"
    EXIT_CODE=$?
    
    TASKS_OUTPUT=$(cat "$STDOUT_FILE")
    STDERR_OUTPUT=$(cat "$STDERR_FILE")
    
    rm "$STDOUT_FILE" "$STDERR_FILE"
    
    if [ $EXIT_CODE -ne 0 ]; then
        if echo "$STDERR_OUTPUT" | grep -q -E "no such table|OperationalError"; then
            echo "Banco de dados do Airflow parece não estar inicializado. Executando 'airflow db init'..."
            $AIRFLOW_BIN db init > /dev/null 2>&1
            
            # Tentar novamente
            echo "Tentando listar tasks novamente..."
            TASKS_OUTPUT=$($AIRFLOW_BIN tasks list "$DAG_ID" 2>/dev/null)
            EXIT_CODE=$?
        else
            echo "Aviso: Falha ao listar tasks com o comando airflow."
            echo "Erro: $STDERR_OUTPUT"
        fi
    fi

    if [ $EXIT_CODE -eq 0 ]; then
        TASKS="$TASKS_OUTPUT"
    fi
else
    echo "Aviso: Binário do Airflow não encontrado em $AIRFLOW_BIN."
fi

# Fallback se não conseguiu listar via comando
if [ -z "$TASKS" ]; then
    echo "Tentando extrair tasks via regex do arquivo..."
    TASKS=$(grep -oP "task_id=['\"]?\K[^'\"]+" "$CHOSEN_DAG_FILE")
fi

if [ -z "$TASKS" ]; then
    echo "Aviso: Nenhuma task encontrada. O launch.json será criado sem opções de tasks."
fi

# Exportar variáveis para o script Python
export TASKS
export DAG_ID
export WORKSPACE_DIR
export CHOSEN_DAGS_DIR
export AIRFLOW_BIN
export PYTHON_BIN

# Gerar o JSON usando Python
python3 -c '
import os
import json

tasks_raw = os.environ.get("TASKS", "")
dag_id = os.environ.get("DAG_ID")
workspace_dir = os.environ.get("WORKSPACE_DIR")
dags_folder = os.environ.get("CHOSEN_DAGS_DIR")
airflow_bin = os.environ.get("AIRFLOW_BIN")
python_bin = os.environ.get("PYTHON_BIN")

# Limpar e filtrar a lista de tasks
task_list = []
if tasks_raw:
    for line in tasks_raw.splitlines():
        line = line.strip()
        # Ignorar linhas vazias
        if not line:
            continue
        # Ignorar linhas que parecem logs
        if line.startswith("[") or "INFO" in line or "WARNING" in line or "DeprecationWarning" in line:
            continue
        
        task_list.append(line)

# Se a lista estiver vazia, adicionar um placeholder
if not task_list:
    task_list = ["start-pipeline", "end-pipeline"]

# Estrutura do launch.json baseada no modelo
launch_config = {
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Airflow: Iniciar DB do Airflow",
            "type": "python",
            "request": "launch",
            "program": airflow_bin,
            "python": python_bin,
            "console": "integratedTerminal",
            "args": ["db", "init"],
            "env": {
                "AIRFLOW__CORE__DAGS_FOLDER": dags_folder,
                "AIRFLOW__CORE__LOAD_EXAMPLES": "False",
                "AIRFLOW_HOME": os.path.join(os.path.expanduser("~"), "airflow"),
                "SPARK_HOME": "/opt/spark",
                "JAVA_HOME": "/usr/lib/jvm/java-1.17.0-openjdk-amd64"
            }
        },
        {
            "name": "Airflow: Listar DAGs",
            "type": "python",
            "request": "launch",
            "program": airflow_bin,
            "python": python_bin,
            "console": "integratedTerminal",
            "args": ["dags", "list"],
            "env": {
                "AIRFLOW__CORE__DAGS_FOLDER": dags_folder,
                "AIRFLOW__CORE__LOAD_EXAMPLES": "False",
                "AIRFLOW_HOME": os.path.join(os.path.expanduser("~"), "airflow"),
                "SPARK_HOME": "/opt/spark",
                "JAVA_HOME": "/usr/lib/jvm/java-1.17.0-openjdk-amd64"
            }
        },
        {
            "name": "Airflow: Debug ANY Task",
            "type": "python",
            "request": "launch",
            "program": airflow_bin,
            "python": python_bin,
            "console": "integratedTerminal",
            "args": [
                "tasks",
                "test",
                dag_id,
                "${input:taskId}",
                "${input:executionDate}"
            ],
            "env": {
                "AIRFLOW__CORE__DAGS_FOLDER": dags_folder,
                "AIRFLOW__CORE__LOAD_EXAMPLES": "False",
                "AIRFLOW_HOME": os.path.join(os.path.expanduser("~"), "airflow"),
                "AIRFLOW__CORE__EXECUTOR": "DebugExecutor",
                "SPARK_HOME": "/opt/spark",
                "JAVA_HOME": "/usr/lib/jvm/java-1.17.0-openjdk-amd64",
                "MEMCACHED_HOST": "memcache",
                "MEMCACHE_HOST": "memcache",
                "MEMCACHED_PORT": "11211",
                "ENVIRONMENT": "dev",
                "MEMCACHE_KEY_PREFIX": "renatocastellani"
            }
        }
    ],
    "inputs": [
        {
            "id": "executionDate",
            "type": "promptString",
            "description": "Data de execução (YYYY-MM-DD ou YYYY-MM-DDThh:mm:ss)",
            "default": "${date:yyyy-MM-dd}"
        },
        {
            "id": "taskId",
            "type": "pickString",
            "description": "Qual tarefa você quer depurar?",
            "options": task_list
        }
    ]
}

vscode_dir = os.path.join(workspace_dir, ".vscode")
if not os.path.exists(vscode_dir):
    os.makedirs(vscode_dir)

launch_path = os.path.join(vscode_dir, "launch.json")
with open(launch_path, "w") as f:
    json.dump(launch_config, f, indent=2)

print(f"Sucesso! Arquivo criado em: {launch_path}")
'
