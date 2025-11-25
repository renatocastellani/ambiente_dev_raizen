#!/usr/bin/env bash
set -euo pipefail

# ===== CONFIGURAÇÕES BÁSICAS =====
# Caminho onde o venv vai ficar (igual à máquina origem)
# VENV_PATH="${VENV_PATH:-/home/coder/venv-datahub-dev}"
# ao invés de usar o usuário coder, usar o usuário corrente do script
VENV_PATH="${VENV_PATH:-$HOME/venv-datahub-dev}"

# Versão de Python desejada (minor). O uv vai pegar a última 3.10.x
PY_MINOR="${PY_MINOR:-3.10}"

echo "=== Clone de venv com uv ==="
echo "VENV_PATH  = $VENV_PATH"
echo "PY_MINOR   = $PY_MINOR"
echo

# ===== 1. Instalar uv se não existir =====
# Garante que o PATH inclua ~/.local/bin antes de verificar
export PATH="$HOME/.local/bin:$PATH"

if ! command -v uv >/dev/null 2>&1; then 
  echo "[1/4] uv não encontrado. Instalando..."
  # Instalação sem modificar arquivos de shell (bashrc/zshrc) e assumindo defaults
  curl -LsSf https://astral.sh/uv/install.sh | sh -s -- --no-modify-path
else
  echo "[1/4] uv já está instalado."
fi

echo

# ===== 2. Instalar Python 3.10.x gerenciado pelo uv =====
echo "[2/4] Instalando Python $PY_MINOR (último patch disponível) com uv..."
uv python install "$PY_MINOR"
echo

# ===== 3. Criar o venv no caminho desejado com essa versão de Python =====
echo "[3/4] Criando virtualenv em: $VENV_PATH"
uv venv "$VENV_PATH" --python "$PY_MINOR"

# Ativar o venv
# (mesmo esquema que um venv normal)
# shellcheck disable=SC1090
source "$VENV_PATH/bin/activate"

echo
python --version
echo "Venv ativo em: $VENV_PATH"
echo

# ===== 4. Instalar dependências do requirements.txt =====
if [ ! -f "requirements_venv_datahub_dev.txt" ]; then
  echo "ERRO: requirements_venv_datahub_dev.txt não encontrado no diretório atual."
  echo "Rode o script na pasta onde está o requirements_venv_datahub_dev.txt."
  exit 1
fi

echo "[4/4] Instalando dependências com uv (interface pip)..."
uv pip install -r requirements_venv_datahub_dev.txt

echo
echo "✔ Clone do venv concluído!"

# mude a cor do prompt para destacar o que precisa fazer para usar o venv
echo -e "\e[1;32mIMPORTANTE:\e[0m"
echo -e "\e[1;32m*****************************************************\e[0m"
echo -e "\e[1;32m Para usar depois, rode:\e[0m"
echo -e "\e[1;32m   source $VENV_PATH/bin/activate\e[0m"
echo -e "\e[1;32m*****************************************************\e[0m"
