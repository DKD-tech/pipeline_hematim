#!/bin/bash -l
#SBATCH --job-name=clair3
#SBATCH --time=04:00:00

# Arguments
SAMPLE_NAME=$1
BAM=$2
REFERENCE=$3
THREADS=$4
BED_FILE=$5
DO_PHASING=$6

# Fichiers d'entrée
#BAM="results/${SAMPLE_NAME}/mapping/${SAMPLE_NAME}.bam"
OUTDIR="results/${SAMPLE_NAME}/snps_clair3"
MODEL_PATH="$HOME/local/bin/miniconda/envs/sv_env/bin/models/r1041_e82_400bps_sup_v500"

# Activer conda
echo " Activation de conda et de l'environnement Clair3..."
#source $HOME/local/bin/miniconda/etc/profile.d/conda.sh

# Assure que conda est disponible
if ! command -v conda &> /dev/null; then
    echo "Chargement de conda..."
    source "$HOME/local/bin/miniconda/etc/profile.d/conda.sh"
fi

# Active l'environnement clair3 (sv_env)
conda activate sv_env

echo "Conda activé : $(which python)"
#source $HOME/tools/bio/config.sh
#conda activate "$CONDA_SV_ENV"



# === Vérification des index BAM ===
# Index requis
echo " Vérification des index"
if [[ ! -f "$BAM.bai" ]]; then
    echo " Index BAM manquant, création..."
    samtools index -@ "$THREADS" "$BAM"
else
    echo "Index BAM déjà présent."
fi

# === Vérification index .fai de la référence ===
echo " Vérification de l'index de la référence..."
if [[ ! -f "${REFERENCE}.fai" ]]; then
    echo " Index FAI manquant pour $REFERENCE, création..."
    samtools faidx "$REFERENCE"
    if [[ $? -ne 0 ]]; then
        echo "Erreur : impossible de créer l'index .fai. Fichier FASTA corrompu ?"
        exit 1
    fi
else
    echo "Index FAI déjà présent."
fi


# Lancement de Clair3
echo " Lancement de Clair3 pour $SAMPLE_NAME"
CMD="run_clair3.sh \
    --bam_fn=$BAM \
    --ref_fn=$REFERENCE \
    --threads=$THREADS \
    --platform=ont \
    --model_path=$MODEL_PATH \
    --output=$OUTDIR"

if [[ -n "$BED_FILE" ]]; then
    CMD+=" --bed_fn=$BED_FILE"
fi

echo "Commande exécutée : $CMD"
eval $CMD

# === WhatsHap (optionnel) ===
if [[ "$DO_PHASING" == "yes" ]]; then
  echo " Phasage activé. Lancement de WhatsHap..."
  
  PHASED_VCF="$OUTDIR/phased.vcf"
  VCF_INPUT="$OUTDIR/merge_output.vcf.gz"
  VCF_DECOMP="$OUTDIR/merge_output.vcf"
  
  if [[ ! -f "$VCF_INPUT" ]]; then
  	echo " Fichier $VCF_INPUT introuvable, le phasage est annulé."
  	exit 1
  fi
  
  
if [[ ! -f "$VCF_DECOMP" ]]; then
	echo "Décompression du VCF clair3..."
	gunzip -c "$VCF_INPUT" > "$VCF_DECOMP"
fi

whatshap phase --output "$PHASED_VCF" --reference "$REFERENCE" "$VCF_DECOMP" "$BAM" --ignore-read-groups
  [[ $? -eq 0 ]] && echo "Phasage terminé : $PHASED_VCF" || (echo "Erreur phasage" && exit 1)


echo " Compression et indexaction du vcf"
bgzip -f "$PHASED_VCF"
tabix -p vcf  "${PHASED_VCF}.gz"


echo "Haplotagging du BAM..."
  HAPLO_BAM="$OUTDIR/haplotagged.bam"
  whatshap haplotag \
    --reference "$REFERENCE" \
    --output "$HAPLO_BAM" \
    --ignore-read-groups \
    "${PHASED_VCF}.gz" \
    "$BAM"


  if [[ $? -eq 0 ]]; then
    echo "Haplotagging terminé : $HAPLO_BAM"
    samtools index "$HAPLO_BAM"
  else
    echo "Erreur lors du haplotagging"
    exit 1
  fi
else
  echo "  Phasage désactivé."
fi


echo "Clair3 terminé. Résultats dans $OUTDIR"
