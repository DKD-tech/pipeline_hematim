#!/bin/bash -l
#SBATCH --job-name=Annotation
#SBATCH --time=04:00:00

# Arguments
SAMPLE_NAME=$1
VCF_FILE=$2
THREADS=$3
REFERENCE=$4

# Fichiers d'entrée et de sortie
OUTDIR="results/${SAMPLE_NAME}/annotation"
mkdir -p "$OUTDIR"

VEPANNO="/scratch/dkdiakite/private/ondemand/data/sys/myjobs/projects/default/pipeline_hematim/fusion_vep_annovar.py"

# Activer conda et les variables d'environnement
#echo " Activation de conda et de l'environnement Annotation..."
#source $HOME/local/bin/miniconda/etc/profile.d/conda.sh
#conda activate sv_env


echo " Activation de conda et de l'environnement Annotation (compatible non-interactif)..."
eval "$($HOME/local/bin/miniconda/bin/conda shell.bash hook)"
conda activate sv_env

# Export des chemins pour VEP en non-interactif
export PERL5LIB=$HOME/local/bin/ensembl-vep:$HOME/local/bin/ensembl-vep/modules:$PERL5LIB


# Variables
VEP_DIR=$HOME/local/bin/ensembl-vep
ANNOVAR_DIR=$HOME/local/bin/annovar
VEP_DATA_DIR=$HOME/.vep
VEP_DATA="/scratch/dkdiakite/data/vep-data"

# === Vérifications des fichiers ===
echo " Vérification des fichiers nécessaires"

if [[ ! -f "$VCF_FILE" ]]; then
    echo "Fichier VCF introuvable : $VCF_FILE"
    exit 1
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

# === Étape 1 : Annotation avec VEP ===
echo " Lancement de VEP pour $SAMPLE_NAME..."

$VEP_DIR/vep \
    --offline \
    --cache \
    --transcript_version \
    --mane \
    --dir_plugins ${VEP_DATA_DIR}/Plugins \
    --dir ${VEP_DATA_DIR} \
    --assembly GRCh38 \
    --fasta ${REFERENCE} \
    --input_file ${VCF_FILE} \
    --output_file ${OUTDIR}/${SAMPLE_NAME}_annotation_vep.tsv \
    --tab \
    --force_overwrite \
    --no_stats \
    --plugin CADD,snv=${VEP_DIR}/VEP_data/whole_genome_SNVs.tsv.gz \
    --plugin LOVD \
    --plugin NMD \
    --plugin AlphaMissense,file=${VEP_DIR}/VEP_data/AlphaMissense_hg38.tsv.gz \
    --plugin GeneBe \
    --plugin FlagLRG,${VEP_DATA}/list_LRGs_transcripts_xrefs.txt \
    --plugin PolyPhen_SIFT,db=${VEP_DIR}/VEP_data/homo_sapiens_pangenome_PolyPhen_SIFT_20240502.db \
    --plugin UTRAnnotator,${VEP_DATA}/uORF_5UTR_GRCh38_PUBLIC.txt \
    --plugin SpliceAI,snv=${VEP_DATA}/spliceai_scores.masked.snv.hg38.vcf.gz,indel=${VEP_DATA}/spliceai_scores.masked.indel.hg38.vcf.gz


#--plugin gnomADc,${VEP_DATA}/gnomad.ch.genomesv3.tabbed.tsv.gz \

# Vérification de la sortie VEP
if [[ ! -f "${OUTDIR}/${SAMPLE_NAME}_annotation_vep.tsv" ]]; then
    echo "Erreur : VEP n’a pas généré le fichier attendu."
    exit 1
fi

echo "VEP terminé."

# === Étape 2 : Annotation avec Annovar ===
echo " Lancement de Annovar pour $SAMPLE_NAME..."

perl ${ANNOVAR_DIR}/table_annovar.pl \
    ${VCF_FILE} \
    ${ANNOVAR_DIR}/humandb/ \
    --outfile ${OUTDIR}/${SAMPLE_NAME}_annovar_pileup \
    --buildver hg38 \
    --protocol refGeneWithVer,clinvar_20240611,dbnsfp47a,gnomad41_exome,gnomad41_genome \
    --operation g,f,f,f,f \
    --vcfinput \
    --otherinfo \
    --thread ${THREADS} \
    --maxgenethread ${THREADS}

# Vérification de la sortie Annovar
if [[ ! -f "${OUTDIR}/${SAMPLE_NAME}_annovar_pileup.hg38_multianno.txt" ]]; then
    echo "Erreur : Annovar n’a pas généré le fichier attendu."
    exit 1
fi

echo "Annovar terminé."

# === Étape 3 : Fusion des résultats VEP et ANNOVAR ===
echo " Fusion des résultats..."

FUSION="${OUTDIR}/fusion"
mkdir -p "$FUSION"

FUSION="${OUTDIR}/fusion"
mkdir -p "$FUSION"

python3 $VEPANNO \
    -v "${OUTDIR}/${SAMPLE_NAME}_annotation_vep.tsv" \
    -a "${OUTDIR}/${SAMPLE_NAME}_annovar_pileup.hg38_multianno.txt" \
    -o "${FUSION}/${SAMPLE_NAME}_annotation_final.tsv"

echo "Fusion complète : ${FUSION}/${SAMPLE_NAME}_annotation_final.tsv"