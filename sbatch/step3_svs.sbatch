#!/bin/bash
#SBATCH --job-name=svs
#SBATCH --time=04:00:00

# === Arguments ===
SAMPLE_NAME=$1
BAM=$2
REFERENCE=$3
THREADS=$4
BED_FILE=$5

# === Fichiers d'entrée ===
#BAM="results/${SAMPLE_NAME}/mapping/${SAMPLE_NAME}.bam"
OUTDIR="results/${SAMPLE_NAME}/svs"
mkdir -p "$OUTDIR"

# # === Activer conda ===
# echo " Activation de conda et de l'environnement sv_env..."
# source $HOME/local/bin/miniconda/etc/profile.d/conda.sh
# conda activate sv_env
# conda activate sv_sniff

# Récupérer le répertoire du pipeline
# === Vérification que PIPELINE_DIR est bien défini ===
if [[ -z "$PIPELINE_DIR" ]]; then
	echo "❌ ERREUR: La variable PIPELINE_DIR n'est pas définie."
	echo "Vérifiez que run_pipeline.sh a bien exporté PIPELINE_DIR."
	exit 1
fi

# === Activer conda ===
echo "Activation de conda et des environnements..."
source $HOME/local/bin/miniconda/etc/profile.d/conda.sh
echo "PIPELINE est : $PIPELINE_DIR"
conda activate "$PIPELINE_DIR/.conda_envs/sv_env"
conda activate "$PIPELINE_DIR/.conda_envs/sv_sniff"

echo "Environnements activés :"
conda info --envs


#source $HOME/tools/bio/config.sh
#conda activate "$CONDA_SV_ENV"
#conda activate "$CONDA_SNIFF_ENV"

# === Vérifications des index ===
echo " Vérification des fichiers nécessaires"

if [[ ! -f "$BAM" ]]; then
    echo "Fichier BAM introuvable : $BAM"
    exit 1
fi

if [[ ! -f "$BAM.bai" ]]; then
    echo " Index BAM manquant, création..."
    samtools index -@ "$THREADS" "$BAM"
else
    echo "Index BAM trouvé."
fi

if [[ ! -f "$REFERENCE" ]]; then
    echo "Fichier de référence introuvable : $REFERENCE"
    exit 1
fi

if [[ ! -f "$REFERENCE.fai" ]]; then
    echo " Index FAI manquant, création..."
    samtools faidx "$REFERENCE"
    if [[ $? -ne 0 ]]; then
        echo "Erreur lors de l'indexation de la référence."
        exit 1
    fi
else
    echo "Index de la référence trouvé."
fi

# === Étape 1 : Sniffles2 ===
echo " Sniffles2 pour $SAMPLE_NAME..."
SNIFFLES_CMD="sniffles -i $BAM \
              -v $OUTDIR/sniffles.vcf \
              -t $THREADS \
              --output-rnames"

if [[ -n "$BED_FILE" ]]; then
    SNIFFLES_CMD+=" --regions $BED_FILE"
fi

echo "Commande exécutée : $SNIFFLES_CMD"
eval $SNIFFLES_CMD

echo "Sniffles2 terminé."

# === Étape 2 : CuteSV ===
echo " CuteSV..."
TEMP_DIR="$OUTDIR/cuteSV/tmp_${SAMPLE_NAME}"
mkdir -p "$TEMP_DIR"

cuteSV "$BAM" "$REFERENCE" "$OUTDIR/cutesv.vcf" "$TEMP_DIR" \
       --threads "$THREADS" \
       -s 3 \
       -L 500000
echo "CuteSV terminé."

# === Étape 3 : Fusion avec SURVIVOR ===
echo " Fusion des SVs avec SURVIVOR..."
VCF_LIST="$OUTDIR/sv_callsets.txt"
echo "$OUTDIR/sniffles.vcf" > "$VCF_LIST"
echo "$OUTDIR/cutesv.vcf"    >> "$VCF_LIST"

SURVIVOR merge "$VCF_LIST" 1000 1 1 0 0 30 "$OUTDIR/final_SVs.vcf"
echo "Fusion complète. Résultat : $OUTDIR/final_SVs.vcf"
