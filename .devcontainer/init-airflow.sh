#!/usr/bin/env bash

# Função para listar os DAGs e tratar problemas de banco de dados
list_dags_with_db_init_if_needed() {
  local output
  local status

  output=$(airflow dags list 2>&1)
  status=$?

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

# Chama a função na inicialização
list_dags_with_db_init_if_needed
