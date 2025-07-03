#!/bin/bash
#SBATCH --job-name=qc
#SBATCH --time=01:00:00


# Arguments
SAMPLE_NAME=$1
BAM_FILE=$2
THREADS=$3
REFERENCE=$4
BED_FILE=$5  # Facultatif

QC_DIR="results/${SAMPLE_NAME}/qc"
mkdir -p "$QC_DIR"


# # Activer conda
# source $HOME/local/bin/miniconda/etc/profile.d/conda.sh
# conda activate sv_env

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

echo "Environnements activés :"
conda info --envs


echo " Statistiques samtools..."
samtools stats "$BAM_FILE" > "$QC_DIR/samtools_stats.tsv"
samtools flagstat "$BAM_FILE" | awk '{print $0}' > "$QC_DIR/flagstat.tsv"
samtools idxstats "$BAM_FILE" > "$QC_DIR/idxstats.tsv"
samtools depth -aa "$BAM_FILE" > "$QC_DIR/depth.tsv"


# Facultatif : fichier BED pour bedcov & coverage
if [[ -n "$BED_FILE" && -f "$BED_FILE" ]]; then
    echo " Calcul de la couverture par région (bedcov)..."
    samtools bedcov "$BED_FILE" "$BAM_FILE" > "$QC_DIR/bedcov.tsv"


    echo " Calcul global de couverture (coverage)..."
    samtools coverage -b "$BAM_FILE" -r "$BED_FILE" > "$QC_DIR/coverage.tsv"
    
    echo " Calcul de la couverture avec mosdepth..."
    mosdepth -b "$BED_FILE" -t "$THREADS" "$QC_DIR/${SAMPLE_NAME}_mosdepth" "$BAM_FILE"
    
else
    echo " Aucun fichier BED fourni, skip bedcov/coverage."
fi


echo " Statistiques NanoStat..."
NanoStat --bam "$BAM_FILE" --outdir "$QC_DIR" --name "nanostat_summary.tsv" --tsv


echo " Génération du rapport MultiQC..."
multiqc "$QC_DIR" --outdir "$QC_DIR"


echo "Rapport MultiQC : $QC_DIR/multiqc_report.html"


