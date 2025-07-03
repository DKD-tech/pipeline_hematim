#!/bin/bash

set -euo pipefail

PIPELINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDA_ENV_DIR="${PIPELINE_DIR}/.conda_envs"
LOG_FILE="${PIPELINE_DIR}/setup.log"

echo "=== Installation du Pipeline Bioinformatique ===" | tee -a "$LOG_FILE"
echo "Répertoire: $PIPELINE_DIR" | tee -a "$LOG_FILE"
echo "Date: $(date)" | tee -a "$LOG_FILE"

# Fonction de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Vérification des prérequis système
check_system_requirements() {
    log "Vérification des prérequis système..."
    
    # Vérifier les commandes essentielles
    for cmd in curl wget git; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERREUR: $cmd n'est pas installé"
            exit 1
        fi
    done
    
    # Vérifier l'espace disque (minimum 5GB)
    available_space=$(df "$PIPELINE_DIR" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 5242880 ]; then  # 5GB en KB
        log "ATTENTION: Espace disque insuffisant (<5GB)"
    fi
}

# Installation de Miniconda si nécessaire
install_conda() {
    if ! command -v conda &> /dev/null; then
        log "Installation de Miniconda..."
        
        # Détecter l'architecture
        if [[ $(uname -m) == "x86_64" ]]; then
            ARCH="x86_64"
        elif [[ $(uname -m) == "aarch64" ]]; then
            ARCH="aarch64"
        else
            log "ERREUR: Architecture non supportée: $(uname -m)"
            exit 1
        fi
        
        # Télécharger et installer Miniconda
        MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${ARCH}.sh"
        wget -q "$MINICONDA_URL" -O miniconda.sh
        bash miniconda.sh -b -p "$HOME/miniconda3"
        rm miniconda.sh
        
        # CORRECTION: Initialiser conda pour le shell actuel
        eval "$($HOME/miniconda3/bin/conda shell.bash hook)"
        conda config --set auto_activate_base false
        
        # AJOUT: Ajouter conda au PATH pour la session en cours
        export PATH="$HOME/miniconda3/bin:$PATH"
        
        log "Miniconda installé avec succès"
    else
        log "Conda déjà disponible: $(which conda)"
    fi
}

# Création des environnements conda
setup_conda_environments() {
    log "Configuration des environnements conda..."
    
    # Créer le répertoire des environnements locaux
    mkdir -p "$CONDA_ENV_DIR"
    
    # CORRECTION: S'assurer que conda est disponible
    if ! command -v conda &> /dev/null; then
        # Si conda vient d'être installé, le réactiver
        export PATH="$HOME/miniconda3/bin:$PATH"
        eval "$($HOME/miniconda3/bin/conda shell.bash hook)"
    fi
    
    # Installer chaque environnement
    for env_file in "$PIPELINE_DIR"/envs/*.yml; do
        if [ -f "$env_file" ]; then
            env_name=$(basename "$env_file" .yml)
            log "Installation de l'environnement: $env_name"
            
            # AMÉLIORATION: Vérifier si l'environnement existe déjà
            if [ -d "$CONDA_ENV_DIR/$env_name" ]; then
                log "L'environnement $env_name existe déjà, mise à jour..."
                conda env update \
                    --file "$env_file" \
                    --prefix "$CONDA_ENV_DIR/$env_name" \
                    --prune
            else
                conda env create \
                    --file "$env_file" \
                    --prefix "$CONDA_ENV_DIR/$env_name"
            fi
            
            log "✓ Environnement $env_name installé/mis à jour"
        fi
    done
}

# Validation de l'installation
validate_installation() {
    log "Validation de l'installation..."
    
    # S'assurer que conda est disponible pour les tests
    if ! command -v conda &> /dev/null; then
        export PATH="$HOME/miniconda3/bin:$PATH"
        eval "$($HOME/miniconda3/bin/conda shell.bash hook)"
    fi
    
    # Tester les environnements
    for env_dir in "$CONDA_ENV_DIR"/*; do
        if [ -d "$env_dir" ]; then
            env_name=$(basename "$env_dir")
            log "Test de l'environnement: $env_name"
            
            # CORRECTION: Utiliser conda activate au lieu de source activate
            conda activate "$env_dir"
            python -c "import sys; print(f'Python {sys.version}')" || {
                log "ERREUR: Problème avec l'environnement $env_name"
                conda deactivate
                exit 1
            }
            conda deactivate
            log "✓ Environnement $env_name validé"
        fi
    done
    
    # Exécuter les tests si disponibles
    if [ -f "$PIPELINE_DIR/tests/run_tests.sh" ]; then
        log "Exécution des tests de validation..."
        bash "$PIPELINE_DIR/tests/run_tests.sh"
    fi
}

# AJOUT: Fonction pour créer un script d'initialisation
create_init_script() {
    log "Création du script d'initialisation..."
    
    cat > "$PIPELINE_DIR/init_conda.sh" << 'EOF'
#!/bin/bash
# Script d'initialisation conda pour le pipeline

# Fonction pour initialiser conda dans le contexte actuel
init_conda() {
    if command -v conda &> /dev/null; then
        # Conda déjà disponible
        return 0
    elif [ -f "$HOME/miniconda3/bin/conda" ]; then
        # Conda installé mais pas dans le PATH
        export PATH="$HOME/miniconda3/bin:$PATH"
        eval "$($HOME/miniconda3/bin/conda shell.bash hook)"
        return 0
    else
        echo "ERREUR: Conda non trouvé"
        return 1
    fi
}

# Initialiser conda
init_conda
EOF
    chmod +x "$PIPELINE_DIR/init_conda.sh"
}

# Fonction principale
main() {
    check_system_requirements
    install_conda
    setup_conda_environments
    validate_installation
    create_init_script
    
    log "=== Installation terminée avec succès ==="
    log "Pour utiliser le pipeline: bash run_pipeline.sh"
    
    # AMÉLIORATION: Script d'activation plus robuste
    cat > "$PIPELINE_DIR/activate_pipeline.sh" << 'EOF'
#!/bin/bash
PIPELINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialiser conda si nécessaire
source "$PIPELINE_DIR/init_conda.sh"

# Exporter les variables d'environnement
export PATH="$PIPELINE_DIR/scripts:$PATH"
export PIPELINE_ROOT="$PIPELINE_DIR"
export CONDA_ENV_DIR="$PIPELINE_DIR/.conda_envs"

echo "Pipeline activé. Répertoire: $PIPELINE_ROOT"
echo "Environnements disponibles dans: $CONDA_ENV_DIR"

# Lister les environnements disponibles
if [ -d "$CONDA_ENV_DIR" ]; then
    echo "Environnements installés:"
    for env_dir in "$CONDA_ENV_DIR"/*; do
        if [ -d "$env_dir" ]; then
            echo "  - $(basename "$env_dir")"
        fi
    done
fi
EOF
    chmod +x "$PIPELINE_DIR/activate_pipeline.sh"
    
    log "Scripts d'activation créés:"
    log "  - activate_pipeline.sh : activation complète"
    log "  - init_conda.sh : initialisation conda uniquement"
}

# Gestion des erreurs
trap 'log "ERREUR: Installation échouée à la ligne $LINENO"' ERR

# Exécution
main "$@"