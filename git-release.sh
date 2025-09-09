#!/usr/bin/env bash
set -e

git fetch origin --tags

CHANGED=$(git status --short | awk '{print $2}')
if [ -z "$CHANGED" ]; then
  echo "⚠️ No hay cambios detectados."
  exit 1
fi

read -rp "📝 Escribe el mensaje de commit: " COMMIT_MSG

BASE_TAG=$(git describe --tags --abbrev=0 origin/main 2>/dev/null || echo "v1.0.0")
BASE_NUM=${BASE_TAG#v}
IFS='.' read -r MAJOR MINOR PATCH <<<"$BASE_NUM"

NEW_PATCH=$((PATCH + 1))
NEW_TAG="v${MAJOR}.${MINOR}.${NEW_PATCH}"

echo ""
echo "🚀 Preparando release..."
echo "   Archivos a commitear:"
echo "$CHANGED" | sed 's/^/     • /'
echo "   Branch destino: qa-agents"
echo "   Commit:         $COMMIT_MSG"
echo "   Base (main):    $BASE_TAG"
echo "   Nuevo tag:      $NEW_TAG"
echo ""
read -rp "❓ ¿Proceder con estos cambios? (y/n): " CONFIRM
[ "$CONFIRM" = "y" ] || { echo "❌ Operación cancelada."; exit 1; }

git add .
git commit -m "$COMMIT_MSG" || echo "⚠️ No hay cambios que commitear"
git push origin qa-agents

git tag "$NEW_TAG"
git push origin "$NEW_TAG"

echo "✅ Commit y tag $NEW_TAG publicados correctamente (branch dev)."

