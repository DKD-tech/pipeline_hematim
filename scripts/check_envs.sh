#!/bin/bash

PIPELINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONDA_ENV_DIR="${PIPELINE_DIR}/.conda_envs"

echo "=== Vérification des environnements ==="

for env_dir in "$CONDA_ENV_DIR"/*; do
    if [ -d "$env_dir" ]; then
        env_name=$(basename "$env_dir")
        echo -n "Test $env_name: "
        
        # Tester l'activation
        if source activate "$env_dir" 2>/dev/null; then
            echo "OK"
            conda deactivate 2>/dev/null
        else
            echo "ERREUR"
        fi
    fi
done