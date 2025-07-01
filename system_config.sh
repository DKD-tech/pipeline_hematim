#!/bin/bash

### === CONFIGURATION ===
INSTALL_DIR="$HOME/tools/bio"
MINICONDA_DIR="$INSTALL_DIR/miniconda3"
CONFIG_FILE="$INSTALL_DIR/config.sh"

mkdir -p "$INSTALL_DIR"

echo "🔍 Vérification de conda..."

if ! command -v conda &> /dev/null; then
    echo "⚠️ Conda non trouvé. Installation de Miniconda dans $MINICONDA_DIR..."

    # Télécharger et installer Miniconda localement
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O "$INSTALL_DIR/miniconda.sh"
    bash "$INSTALL_DIR/miniconda.sh" -b -p "$MINICONDA_DIR"
    rm "$INSTALL_DIR/miniconda.sh"

    # Initialiser conda depuis l'installation locale
    eval "$($MINICONDA_DIR/bin/conda shell.bash hook)"
    export PATH="$MINICONDA_DIR/bin:$PATH"
else
    echo "✅ Conda déjà installé."
    eval "$(conda shell.bash hook)"
fi

### === [1] Création des environnements ===

## sv_env
if ! conda info --envs | grep -q "sv_env"; then
    echo "🧪 Création de l'environnement sv_env..."
    conda create -y -n sv_env \
        minimap2 samtools bcftools whatshap mosdepth \
        clair3 cutesv survivor pysam python=3.9
else
    echo "✅ Environnement sv_env déjà présent"
fi

## sv_sniff
if ! conda info --envs | grep -q "sv_sniff"; then
    echo "🧬 Création de l'environnement sv_sniff..."
    conda create -y -n sv_sniff python=3.10 python-edlib pysam
    conda activate sv_sniff
    conda install -y -c bioconda sniffles=2.6.1
    conda deactivate
else
    echo "✅ Environnement sv_sniff déjà présent"
fi

## cnvkit_env
if ! conda info --envs | grep -q "cnvkit_env"; then
    echo "📈 Création de l'environnement cnvkit_env..."
    conda create -y -n cnvkit_env cnvkit pyfaidx pyvcf3 pysam bioconductor-dnacopy r-base
else
    echo "✅ Environnement cnvkit_env déjà présent"
fi

### === [2] Génération de config.sh ===
echo "📄 Génération de $CONFIG_FILE"

cat <<EOF > "$CONFIG_FILE"
# ==========================================
# config.sh - Pipeline Nanopore - UPJV
# ==========================================

# === Ajouter les outils locaux au PATH ===
export PATH="$INSTALL_DIR/spliceai:\$PATH"
export PATH="$MINICONDA_DIR/bin:\$PATH"

# === Chargement automatique de conda ===
if command -v conda >/dev/null 2>&1; then
    __conda_setup="\$(conda shell.bash hook 2> /dev/null)"
    if [ \$? -eq 0 ]; then
        eval "\$__conda_setup"
    else
        export PATH="$MINICONDA_DIR/bin:\$PATH"
    fi
elif [ -f "$MINICONDA_DIR/etc/profile.d/conda.sh" ]; then
    source "$MINICONDA_DIR/etc/profile.d/conda.sh"
    export PATH="$MINICONDA_DIR/bin:\$PATH"
else
    echo "⚠️ Conda n'est pas trouvé dans ton PATH. Installe-le ou ajoute-le manuellement."
fi

# === Environnements Conda par défaut ===
export CONDA_SV_ENV="sv_env"
export CONDA_SNIFF_ENV="sv_sniff"
export CONDA_CNVKIT_ENV="cnvkit_env"
EOF

### === [3] Ajout dans ~/.bashrc si souhaité ===
if ! grep -q "tools/bio/config.sh" "$HOME/.bashrc"; then
    echo ""
    read -p "❓ Souhaites-tu l’ajouter automatiquement à ton ~/.bashrc ? (o/N) : " confirm_bashrc
    if [[ "$confirm_bashrc" == "o" || "$confirm_bashrc" == "O" ]]; then
        echo -e "\n🔧 Ajout dans ~/.bashrc..."
        echo "# Chargement automatique du pipeline Nanopore" >> "$HOME/.bashrc"
        echo "source \"$CONFIG_FILE\"" >> "$HOME/.bashrc"
        echo "✅ Ajout effectué. Il sera actif à chaque session."
    else
        echo "⚠️ Tu devras exécuter manuellement : source \"$CONFIG_FILE\" à chaque session."
    fi
else
    echo "ℹ️ Le chargement est déjà présent dans ~/.bashrc"
fi

echo -e "\n✅ Installation terminée ! Recharge ton terminal avec :"
echo "   👉 source ~/.bashrc"
