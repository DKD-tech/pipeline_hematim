#!/bin/bash
#SBATCH --job-name=cnvkit
#SBATCH --time=04:00:00

# === Arguments ===
SAMPLE_NAME=$1
REFERENCE=$2
THREADS=$3
BED_FILE=$4         # Optionnel : fichier BED
CNV_BAM=$5          # Fichier BAM mappé

# === Répertoire de sortie ===
OUTDIR="results/${SAMPLE_NAME}/cnvkit"
mkdir -p "$OUTDIR"

# === Chargement de l’environnement conda ===
source $HOME/local/bin/miniconda/etc/profile.d/conda.sh
conda activate cnvkit_env


# === Vérifications ===
if [[ ! -f "$CNV_BAM" ]]; then
    echo "BAM introuvable : $CNV_BAM"
    exit 1
fi

if [[ ! -f "$REFERENCE" ]]; then
    echo "Référence FASTA introuvable : $REFERENCE"
    exit 1
fi

# === Étape CNVkit ===
if [[ -f "$BED_FILE" ]]; then
    echo " Lancement CNVkit avec fichier BED : $BED_FILE"

    cnvkit.py batch "$CNV_BAM" \
        -f "$REFERENCE" \
        -t "$BED_FILE" \
        -n   \
        --output-reference "$OUTDIR/reference.cnn" \
        --output-dir "$OUTDIR" \
        --method wgs \
        --processes "$THREADS"
else
    echo " Lancement CNVkit sans BED"

    cnvkit.py batch "$CNV_BAM" \
        -f "$REFERENCE" \
        -n   \
        --output-reference "$OUTDIR/reference.cnn" \
        --output-dir "$OUTDIR" \
        --method wgs \
        --processes "$THREADS"
fi

# === Fichiers générés ===
CNR_FILE="$OUTDIR/$(basename "$CNV_BAM" .bam).cnr"
CNS_FILE="$OUTDIR/$(basename "$CNV_BAM" .bam).cns"

if [[ -f "$CNR_FILE" && -f "$CNS_FILE" ]]; then
    echo " Génération des graphiques"
    cnvkit.py scatter "$CNR_FILE" -s "$CNS_FILE" -o "$OUTDIR/${SAMPLE_NAME}_scatter.pdf"
    cnvkit.py diagram "$CNR_FILE" -s "$CNS_FILE" -o "$OUTDIR/${SAMPLE_NAME}_diagram.pdf"

    echo " Export en VCF"
    cnvkit.py export vcf "$CNS_FILE" -o "$OUTDIR/${SAMPLE_NAME}.cnv.vcf"
else
    echo "Les fichiers CNR ou CNS sont manquants."
    exit 1
fi

echo "CNVkit terminé. Résultats disponibles dans : $OUTDIR"
