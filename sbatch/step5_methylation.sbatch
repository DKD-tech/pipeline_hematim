#!/bin/bash -l
#SBATCH --job-name=methylartist_seg
#SBATCH --time=04:00:00

# === Arguments ===
SAMPLE_NAME=$1
REFERENCE=$2
THREADS=$3
REGION_FILE=$4    # BED obligatoire
METHYLBAM=$5      # BAM annoté

# === Répertoire de sortie ===
OUTDIR="results/${SAMPLE_NAME}/methylation"
mkdir -p "$OUTDIR"

# === Activer l’environnement conda ===
source $HOME/local/bin/miniconda/etc/profile.d/conda.sh
conda activate sv_env
#source $HOME/tools/bio/config.sh
#conda activate "$CONDA_SV_ENV"

# === Vérifications ===
if [[ ! -f "$METHYLBAM" ]]; then
    echo "BAM annoté manquant : $METHYLBAM"
    exit 1
fi

if [[ ! -f "$REFERENCE" ]]; then
    echo "Référence FASTA manquante : $REFERENCE"
    exit 1
fi

if [[ ! -f "$REGION_FILE" ]]; then
    echo "Fichier de régions BED obligatoire manquant : $REGION_FILE"
    exit 1
fi

echo " Traitement MethylArtist (segmeth + segplot) avec régions de $REGION_FILE"

# === Vérification du format BED (3 colonnes ou 4 ?) ===
LINE_COLS=$(awk '{print NF; exit}' "$REGION_FILE")
NAMED_BED="$REGION_FILE"

if [[ "$LINE_COLS" -eq 3 ]]; then
    echo "BED sans nom détecté. Ajout automatique d'une 4ᵉ colonne..."
    NAMED_BED="${REGION_FILE%.bed}_named.bed"
    awk '{print $0 "\tregion_"$1}' "$REGION_FILE" > "$NAMED_BED"
else
    echo "BED avec noms détecté."
fi

echo " Traitement MethylArtist (segmeth + segplot) avec régions de $NAMED_BED"

# Préparation nom de sortie
BASENAME=$(basename "$REGION_FILE" | sed 's/\.[^.]*$//')
METHYL_NAME=$(basename "$METHYLBAM" .bam)
SEGFILE="${OUTDIR}/${BASENAME}.${METHYL_NAME}.segmeth.tsv"

# === Étape 1 : segmeth ===
echo " SegMeth : $SEGFILE"
methylartist segmeth \
    -b "$METHYLBAM" \
    -i "$NAMED_BED" \
    -p "$THREADS" \
    --ref "$REFERENCE" \
    --motif CG \
    -o "$SEGFILE"

# === Étape 2 : segplot ===
echo "️ SegPlot standard"
methylartist segplot \
    -s "$SEGFILE" -a \
    --palette viridis \
    -o "$OUTDIR/${BASENAME}_plot.png"

echo "️ SegPlot verbose"
methylartist segplot \
    -s "$SEGFILE" -v -a \
    --palette viridis \
    -o "$OUTDIR/${BASENAME}_plot_violon.png"

echo "Visualisation terminée. Résultats dans $OUTDIR"

# === Étape 3 : methylartist locus pour chaque ligne du BED ===
echo " Locus plot pour chaque région..."

while read -r chrom start end; do
    REGION_ID="region_${chrom}_${start}"
    REGION_STRING="${chrom}:${start}-${end}"
    OUT_PNG="$OUTDIR/${REGION_ID}_locus.png"

    echo " $REGION_STRING --> $OUT_PNG"
    methylartist locus \
        -b "$METHYLBAM" \
        -i "$REGION_STRING" \
        -r "$REFERENCE" \
        --motif CG \
        -o "$OUT_PNG"
done < "$REGION_FILE"

