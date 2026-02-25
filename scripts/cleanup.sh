#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Cloud Projects Portfolio - Cleanup Helper Script
# Author: Liliane Konissi (portfolio cleanup)
# Purpose:
#   Remove only placeholder/generated scaffold files safely.
#   Does NOT delete real project work unless explicitly forced.
# ============================================================

ROOT_DIR="${1:-.}"
MODE="${2:-safe}"   # safe | force

cd "${ROOT_DIR}"

echo "==> Cleanup mode: ${MODE}"
echo "==> Working directory: $(pwd)"
echo

# Project folders expected from setup script
PROJECTS=(
  "production-vpc-vnet-public-private-subnets-nat"
  "ha-web-app-load-balancer-auto-scaling-multi-az"
  "iam-secrets-management"
  "cloud-monitoring-flow-logs-investigation"
  "backup-restore-dr-mini-project"
)

# Helper: remove file only if it matches exact placeholder pattern
remove_if_placeholder_readme() {
  local file="$1"

  [[ -f "$file" ]] || return 0

  # Detect placeholder text created by setup.sh
  if grep -q "TODO: Describe the purpose of this project." "$file" \
     && grep -q "## Lessons Learned" "$file"; then
    rm -f "$file"
    echo "   - Removed placeholder README: $file"
  else
    echo "   - Kept (customized) README: $file"
  fi
}

remove_if_placeholder_note() {
  local file="$1"

  [[ -f "$file" ]] || return 0

  if grep -q "Project notes for:" "$file" \
     && grep -q "screenshot checklist" "$file"; then
    rm -f "$file"
    echo "   - Removed placeholder note: $file"
  else
    echo "   - Kept (customized) note: $file"
  fi
}

# ----------------------------------------
# SAFE cleanup: only scaffold placeholders
# ----------------------------------------
if [[ "${MODE}" == "safe" ]]; then
  echo "Running SAFE cleanup (placeholder files only)..."

  for p in "${PROJECTS[@]}"; do
    remove_if_placeholder_readme "${p}/README.md"
    remove_if_placeholder_note "${p}/notes/note.txt"

    # remove .gitkeep only if screenshots folder has no real files
    if [[ -d "${p}/screenshots" ]]; then
      # Count non-hidden image/files except .gitkeep
      real_count=$(find "${p}/screenshots" -maxdepth 1 -type f ! -name ".gitkeep" | wc -l | tr -d ' ')
      if [[ "${real_count}" == "0" && -f "${p}/screenshots/.gitkeep" ]]; then
        rm -f "${p}/screenshots/.gitkeep"
        echo "   - Removed ${p}/screenshots/.gitkeep (no screenshots yet)"
      else
        echo "   - Kept screenshots contents in ${p}/screenshots"
      fi
    fi
  done

  # docs placeholders (only if untouched)
  for f in docs/architecture.md docs/runbooks.md docs/incident-response.md; do
    if [[ -f "$f" ]]; then
      if grep -q "## Purpose" "$f" && grep -q "Suggested runbooks\|Lifecycle" "$f"; then
        # Only remove if very short (still placeholder-ish)
        line_count=$(wc -l < "$f" | tr -d ' ')
        if [[ "$line_count" -lt 30 ]]; then
          rm -f "$f"
          echo "   - Removed placeholder doc: $f"
        else
          echo "   - Kept (customized) doc: $f"
        fi
      else
        echo "   - Kept (customized) doc: $f"
      fi
    fi
  done

  # diagrams placeholder png (empty file only)
  if [[ -f "diagrams/platform-architecture.png" ]]; then
    size_bytes=$(wc -c < "diagrams/platform-architecture.png" | tr -d ' ')
    if [[ "$size_bytes" == "0" ]]; then
      rm -f "diagrams/platform-architecture.png"
      echo "   - Removed empty placeholder diagrams/platform-architecture.png"
    else
      echo "   - Kept real diagrams/platform-architecture.png"
    fi
  fi

  echo
  echo "✅ SAFE cleanup complete."
  echo "No customized files were removed."

# ----------------------------------------
# FORCE cleanup: remove scaffold folders/files
# ----------------------------------------
elif [[ "${MODE}" == "force" ]]; then
  echo "⚠️  FORCE cleanup will remove scaffold docs/diagrams placeholders and empty helper folders."
  echo "This may remove files if they still match the scaffold structure."
  echo

  # Remove placeholders using same logic first
  "${BASH_SOURCE[0]}" "$(pwd)" safe

  echo
  echo "==> Continuing FORCE cleanup..."

  # Remove empty notes/ and screenshots/ folders if empty
  for p in "${PROJECTS[@]}"; do
    [[ -d "$p" ]] || continue

    if [[ -d "${p}/notes" ]] && [[ -z "$(find "${p}/notes" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
      rmdir "${p}/notes" || true
      echo "   - Removed empty ${p}/notes"
    fi

    if [[ -d "${p}/screenshots" ]] && [[ -z "$(find "${p}/screenshots" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
      rmdir "${p}/screenshots" || true
      echo "   - Removed empty ${p}/screenshots"
    fi
  done

  # Remove docs/ or diagrams/ if empty
  for d in docs diagrams; do
    if [[ -d "$d" ]] && [[ -z "$(find "$d" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
      rmdir "$d" || true
      echo "   - Removed empty ${d}/"
    fi
  done

  echo
  echo "✅ FORCE cleanup complete."

else
  echo "❌ Invalid mode: ${MODE}"
  echo "Usage:"
  echo "  ./scripts/cleanup.sh [root_dir] [safe|force]"
  echo
  echo "Examples:"
  echo "  ./scripts/cleanup.sh . safe"
  echo "  ./scripts/cleanup.sh . force"
  exit 1
fi