#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Cloud Projects Portfolio - Repository Bootstrap Script
# Author: Liliane Konissi (portfolio setup)
# Purpose:
#   Create a professional engineering-style repository structure
#   with docs/, diagrams/, scripts/, and cloud project folders.
# ============================================================

PROJECT_ROOT="${1:-cloud-projects}"

echo "==> Creating repository structure in: ${PROJECT_ROOT}"
mkdir -p "${PROJECT_ROOT}"
cd "${PROJECT_ROOT}"

# -----------------------------
# Core folders
# -----------------------------
mkdir -p docs
mkdir -p diagrams
mkdir -p scripts

# -----------------------------
# Project folders
# -----------------------------
PROJECTS=(
  "production-vpc-vnet-public-private-subnets-nat"
  "ha-web-app-load-balancer-auto-scaling-multi-az"
  "iam-secrets-management"
  "cloud-monitoring-flow-logs-investigation"
  "backup-restore-dr-mini-project"
)

for p in "${PROJECTS[@]}"; do
  mkdir -p "${p}/screenshots"
  mkdir -p "${p}/notes"
  # Create README only if it doesn't exist
  if [[ ! -f "${p}/README.md" ]]; then
    cat > "${p}/README.md" <<EOF
# ${p}

## Purpose

TODO: Describe the purpose of this project.

## Problem

TODO: Describe the real Ops/DevOps problem this project solves.

## Solution

TODO: Describe the solution and AWS services used.

## Architecture Diagram

> Add architecture diagram image here (recommended: \`diagrams/\` or project-level image)

## Step-by-step CLI (with variable assignments)

TODO: Add numbered implementation steps with CLI commands.

## Screenshots linked to steps

- \`screenshots/01-placeholder.png\` — TODO (what should this show)
- \`screenshots/02-placeholder.png\` — TODO (what should this show)

## Testing / Failure Simulation

TODO: Add validation tests and failure simulation steps.

## Troubleshooting

TODO: Add common issues and fixes.

## Cleanup

TODO: Add cleanup commands and order.

## Lessons Learned

TODO: Add key lessons from the project.

## Outcome

TODO: Summarize what this project proves.
EOF
    echo "   - Created ${p}/README.md"
  else
    echo "   - Skipped existing ${p}/README.md"
  fi

  # Placeholder note file
  if [[ ! -f "${p}/notes/note.txt" ]]; then
    cat > "${p}/notes/note.txt" <<EOF
Project notes for: ${p}

Use this file for:
- command outputs
- troubleshooting notes
- reminders
- screenshot checklist
EOF
    echo "   - Created ${p}/notes/note.txt"
  else
    echo "   - Skipped existing ${p}/notes/note.txt"
  fi

  # .gitkeep so empty screenshot folder is tracked
  if [[ ! -f "${p}/screenshots/.gitkeep" ]]; then
    touch "${p}/screenshots/.gitkeep"
    echo "   - Created ${p}/screenshots/.gitkeep"
  fi
done

# -----------------------------
# docs/ files (only if missing)
# -----------------------------
create_if_missing() {
  local filepath="$1"
  local content="$2"

  if [[ ! -f "$filepath" ]]; then
    printf "%s\n" "$content" > "$filepath"
    echo "   - Created $filepath"
  else
    echo "   - Skipped existing $filepath"
  fi
}

create_if_missing "docs/architecture.md" "# Cloud Projects Platform Architecture

## Purpose
High-level architecture and how all projects connect into one production cloud platform story.

## Sections to document
- Network foundation
- HA web tier
- IAM + secrets
- Monitoring + logs
- Backup / restore + DR
"

create_if_missing "docs/runbooks.md" "# Operations Runbooks

## Purpose
Operational runbooks for common incidents and recovery actions.

## Suggested runbooks
- EC2 instance failure
- High CPU alarm
- Flow Logs REJECT traffic investigation
- IAM AccessDenied for secret read
- EBS snapshot restore
- S3 version recovery
"

create_if_missing "docs/incident-response.md" "# Incident Response Guide

## Purpose
Simple incident response lifecycle for these cloud projects.

## Lifecycle
1. Detect
2. Triage
3. Contain
4. Investigate
5. Recover
6. Communicate
7. Post-incident review
"

# -----------------------------
# diagrams/ placeholders
# -----------------------------
if [[ ! -f "diagrams/platform-architecture.png" ]]; then
  touch "diagrams/platform-architecture.png"
  echo "   - Created diagrams/platform-architecture.png (placeholder)"
else
  echo "   - Skipped existing diagrams/platform-architecture.png"
fi

if [[ ! -f "diagrams/README.md" ]]; then
  cat > "diagrams/README.md" <<'EOF'
# Diagrams

Store architecture images here for GitHub README rendering.

Recommended file:
- platform-architecture.png

Tip:
Add this near the top of the root README:
![Cloud Platform Architecture](diagrams/platform-architecture.png)
EOF
  echo "   - Created diagrams/README.md"
fi

# -----------------------------
# Root README (if missing)
# -----------------------------
if [[ ! -f "README.md" ]]; then
  cat > "README.md" <<'EOF'
# Cloud Projects

Production-style cloud engineering projects built from scratch.

## Operational Documentation

- [Platform Architecture](docs/architecture.md)
- [Operations Runbooks](docs/runbooks.md)
- [Incident Response Guide](docs/incident-response.md)
EOF
  echo "   - Created README.md"
else
  echo "   - Skipped existing README.md"
fi

# -----------------------------
# Git ignore (safe defaults)
# -----------------------------
if [[ ! -f ".gitignore" ]]; then
  cat > ".gitignore" <<'EOF'
# OS / editor files
.DS_Store
Thumbs.db
*.swp
*.swo
.vscode/
.idea/

# Shell artifacts
*.log
*.tmp
EOF
  echo "   - Created .gitignore"
else
  echo "   - Skipped existing .gitignore"
fi

# -----------------------------
# Make scripts executable if present
# (works after you paste these scripts)
# -----------------------------
chmod +x scripts/*.sh 2>/dev/null || true

echo
echo "✅ Repository bootstrap complete."
echo "📁 Location: $(pwd)"
echo
echo "Next steps:"
echo "1) Paste your real README contents"
echo "2) Replace placeholder docs with your final versions"
echo "3) Add architecture image to diagrams/platform-architecture.png"
echo "4) Commit to GitHub"