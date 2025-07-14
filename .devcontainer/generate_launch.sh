#!/usr/bin/env bash
#!/bin/bash

echo $(which airflow)

echo $AIRFLOW__CORE__DAGS_FOLDER

echo $(airflow config get-value core dags_folder)

# Função para procurar a pasta "dags" até 3 níveis abaixo da pasta atual
find_dags_folder() {
  local start_dir="$1"
  find "$start_dir" -maxdepth 3 -type d -name "dags" | head -n 1
}

# Captura o diretório atual
current_dir=$(pwd)

# Procura a pasta "dags"
suggested_dags_folder=$(find_dags_folder "$current_dir")

# Pergunta ao usuário com sugestão
echo "Qual é a pasta de dags? [Padrão: ${suggested_dags_folder}]"
read -r user_input

# Define a pasta final
if [ -z "$user_input" ]; then
  dags_folder="$suggested_dags_folder"
else
  dags_folder="$user_input"
fi

# Verifica se o caminho existe
if [ ! -d "$dags_folder" ]; then
  echo "❌ Erro: O diretório '$dags_folder' não existe!"
  exit 1
fi

# Exporta a variável de ambiente
export AIRFLOW__CORE__DAGS_FOLDER="$dags_folder"

echo ""
echo "✅ AIRFLOW__CORE__DAGS_FOLDER definido como: $AIRFLOW__CORE__DAGS_FOLDER"
echo ""

# airflow db init

# Função para listar os DAGs e tratar problemas de banco de dados
list_dags_with_db_init_if_needed() {
  local output
  local status

  # Tenta listar os DAGs e captura stdout + stderr
  echo $AIRFLOW__CORE__DAGS_FOLDER
  output=$(airflow dags list 2>&1)
  status=$?

  # Verifica se o erro é por banco de dados não inicializado
  if echo "$output" | grep -q -E "no such table: dag|You need to initialize the database"; then
    echo "⚠️ Banco de dados não inicializado. Executando 'airflow db init'..."
    airflow db init
    echo ""
    echo "✅ Banco de dados inicializado. Tentando listar os DAGs novamente..."
    airflow dags list
  elif [ $status -ne 0 ]; then
    echo "❌ Erro inesperado ao listar os DAGs:"
    echo "$output"
    exit 1
  else
    echo "$output"
  fi
}

# Função para listar os DAGs e tratar problemas de banco de dados
list_dags_with_db_init_if_needed() {
  local output
  local status

  # Tenta listar os DAGs e captura stdout + stderr
  output=$(airflow dags list 2>&1)
  status=$?

  # Verifica se o erro é por banco de dados não inicializado
  if echo "$output" | grep -q -E "no such table: dag|You need to initialize the database"; then
    echo "⚠️ Banco de dados não inicializado. Executando 'airflow db init'..."
    airflow db init
    echo ""
    echo "✅ Banco de dados inicializado. Tentando listar os DAGs novamente..."
    airflow dags list
  elif [ $status -ne 0 ]; then
    echo "❌ Erro inesperado ao listar os DAGs:"
    echo "$output"
    exit 1
  else
    echo "$output"
  fi
}

# Executa a função de listagem com tratamento
list_dags_with_db_init_if_needed

# generate_launch.sh - Gera dinamicamente um .vscode/launch.json para Airflow
set -euo pipefail

# 1) checar dependências
for cmd in airflow python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Erro: '$cmd' não encontrado. Instale antes de continuar." >&2
    exit 1
  fi
done

# 2) buscar DAGs via JSON
echo $AIRFLOW__CORE__DAGS_FOLDER

echo $(airflow config get-value core dags_folder)


echo "Buscando lista de DAGs..."
DAGS_JSON=$(mktemp)
airflow dags list -o json >"$DAGS_JSON" 2>/dev/null &
SPINNER_PID=$!
spinner() {
  local pid=$1; local delay=0.1; local spinstr='|/-\\'
  printf "  "
  while kill -0 "$pid" 2>/dev/null; do
    for ((i=0;i<${#spinstr};i++)); do
      printf "\b%s" "${spinstr:i:1}"
      sleep $delay
    done
  done
  printf "\b"
}
spinner $SPINNER_PID
wait $SPINNER_PID
echo " OK."

mapfile -t DAGS < <(python3 - <<PYTHON
import json,sys
try:
    data=json.load(open("$DAGS_JSON"))
    for d in data:
        print(d.get("dag_id",""))
except:
    sys.exit(0)
PYTHON
)
rm -f "$DAGS_JSON"
if [ "${#DAGS[@]}" -eq 0 ]; then
  echo "Nenhuma DAG encontrada." >&2
  exit 1
fi

# 3) selecionar DAG (interativo com fzf)
echo; echo "Selecione a DAG:"
if ! command -v fzf &>/dev/null; then
  echo "Erro: 'fzf' não encontrado. Instale antes de continuar." >&2
  exit 1
fi

DAG_ID=$(printf "%s\n" "${DAGS[@]}" | fzf --prompt="Selecione a DAG: " --height=10 --border)
if [ -z "$DAG_ID" ]; then
  echo "Nenhuma DAG selecionada." >&2
  exit 1
fi
echo "DAG selecionada: $DAG_ID"


# 4) listar tasks (texto puro)
echo "Buscando tasks de '$DAG_ID'..."
TASKS_RAW=$(mktemp)
airflow tasks list "$DAG_ID" >"$TASKS_RAW" 2>/dev/null & spinner $!
echo " OK."
mapfile -t TASKS < <(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "$TASKS_RAW" | sed '/^$/d')
rm -f "$TASKS_RAW"
if [ "${#TASKS[@]}" -eq 0 ]; then
  echo "Nenhuma task encontrada para $DAG_ID." >&2
  exit 1
fi

export HOME='/app'
# 5) perguntas finais
DEFAULT_PATH="$HOME/.vscode/launch.json"
read -rp "Caminho para salvar launch.json [${DEFAULT_PATH}]: " OUTPUT_PATH
OUTPUT_PATH=${OUTPUT_PATH:-$DEFAULT_PATH}

DEFAULT_DATE=$(date +%F)
read -rp "Data de execução (YYYY-MM-DD ou YYYY-MM-DDThh:mm:ss) [${DEFAULT_DATE}]: " EXEC_DATE
EXEC_DATE=${EXEC_DATE:-$DEFAULT_DATE}

# 6) gerar launch.json sem compounds
export PYTHON_PATH=$(command -v python3)
export AIRFLOW_PATH=$(command -v airflow)

mkdir -p "$(dirname "$OUTPUT_PATH")"
{
  echo '{'
  echo '  "version": "0.2.0",'
  echo '  "configurations": ['

  # 6.0) Config de Iniciar DB Airflow
  echo '    {'
  echo '      "name": "Airflow: Iniciar DB do Airflow",'
  echo '      "type": "python",'
  echo '      "request": "launch",'
  echo "      \"python\": \"$PYTHON_PATH\","
  echo "      \"program\": \"$AIRFLOW_PATH\","
  echo '      "console": "integratedTerminal",'
  echo '      "args": ["db", "init"],'
  echo '      "env": {'
  echo '        "AIRFLOW__CORE__DAGS_FOLDER": "'"$AIRFLOW__CORE__DAGS_FOLDER"'",'
  echo '        "AIRFLOW_HOME": "'"/opt"'/airflow",'
  echo '      }'
  echo '    },'

  
  # 6.1) Config de Listar DAGs
  echo '    {'
  echo '      "name": "Airflow: Listar DAGs",'
  echo '      "type": "python",'
  echo '      "request": "launch",'
  echo "      \"python\": \"$PYTHON_PATH\","
  echo "      \"program\": \"$AIRFLOW_PATH\","
  echo '      "console": "integratedTerminal",'
  echo '      "args": ["dags", "list"],'
  echo '      "env": {'
  echo '        "AIRFLOW__CORE__DAGS_FOLDER": "'"$AIRFLOW__CORE__DAGS_FOLDER"'",'
  echo '        "AIRFLOW_HOME": "'"/opt"'/airflow",'
  echo '      }'
  echo '    },'

  # 6.2) Uma configuração de Debug por task
  for idx in "${!TASKS[@]}"; do
    task="${TASKS[idx]}"
    echo '    {'
    echo '      "name": "Airflow: Debug Task '"$task"'",'
    echo '      "type": "python",'
    echo '      "request": "launch",'
    echo "      \"python\": \"$PYTHON_PATH\","
    echo "      \"program\": \"$AIRFLOW_PATH\","
    echo '      "console": "integratedTerminal",'
    echo "      \"args\": [\"tasks\",\"test\",\"$DAG_ID\",\"$task\",\"\${input:executionDate}\"],"
    echo '      "env": {'
  echo '          "AIRFLOW__CORE__DAGS_FOLDER": "'"$AIRFLOW__CORE__DAGS_FOLDER"'",'
  echo '          "AIRFLOW_HOME": "'"/opt"'/airflow",'
    echo '          "MEMCACHE_HOST": "memcache",'
    echo '        "AIRFLOW__CORE__EXECUTOR": "DebugExecutor"'
    echo '      }'
    if [ "$idx" -lt $((${#TASKS[@]}-1)) ]; then
      echo '    },'
    else
      echo '    }'
    fi
  done

  echo '  ],'
  echo '  "inputs": ['
  echo '    {'
  echo '      "id": "executionDate",'
  echo '      "type": "promptString",'
  echo '      "description": "Data de execução (YYYY-MM-DD ou YYYY-MM-DDThh:mm:ss)",'
  echo '      "default": "${date:yyyy-MM-dd}"'
  echo '    }'
  echo '  ]'
  echo '}'
} > "$OUTPUT_PATH"

echo -e "\nArquivo launch.json gerado em: $OUTPUT_PATH"

