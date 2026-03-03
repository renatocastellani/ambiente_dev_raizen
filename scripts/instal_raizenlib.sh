set -euo pipefail

REPO_URL="https://github.com/raizen-analytics/raizenlib.git"
REF="v3.6.4"   # pode ser tag, branch, ou commit hash

TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

echo "[1/5] Clonando ..."
if ! git clone --quiet "$REPO_URL" "$TMPDIR/raizenlib" 2>"$TMPDIR/clone.err"; then
  echo "ERRO: não foi possível clonar via HTTPS sem token."
  echo "---- detalhe ----"
  cat "$TMPDIR/clone.err"
  echo "-----------------"
  if grep -qi "SAML SSO" "$TMPDIR/clone.err" || grep -qi "403" "$TMPDIR/clone.err"; then
    echo ""
    echo "Causa provável: repo privado em org com SAML SSO enforced."
    echo "Sem token/credencial autorizada, HTTPS não vai funcionar."
  fi
  exit 1
fi

cd "$TMPDIR/raizenlib"

echo "[2/5] Fetch + checkout determinístico ($REF) ..."
git fetch --all --tags --quiet
git checkout --detach "$REF" --quiet

echo "[3/5] Validando ref instalada (HEAD) ..."
git log -1 --oneline

echo "[4/5] Instalando (por cima, sem mexer em deps) ..."
pip install --upgrade --force-reinstall --no-deps .

echo "[5/5] Validando import ..."
python -c "import raizenlib, inspect; print('raizenlib import:', inspect.getfile(raizenlib))"

echo "OK: instalado a partir de $REF"