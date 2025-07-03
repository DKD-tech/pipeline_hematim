#!/bin/bash
#SBATCH --job-name=align_test
#SBATCH --time=2-06:00:00
#SBATCH --cpus-per-task=20
#SBATCH --array=1-1%5

# === Initialisation environnement ===
# export PATH=$HOME/bin/minimap2-2.24_x64-linux:$PATH
# export PATH=$HOME/bin/samtools/bin:$PATH

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

# === Paramètres d'entrée ===
SAMPLE_NAME=$1
THREADS=$2
INPUT_PATH=$3
REFERENCE=$4
CONFIG_FILE="results/$SAMPLE_NAME/config_${SAMPLE_NAME}.txt"
BAM_DIR="results/$SAMPLE_NAME/mapping"
mkdir -p "$BAM_DIR"

# Paramètres de parallélisation
MAX_PARALLEL_JOBS=5    # Nombre max de jobs minimap2 en parallèle
THREADS_PER_JOB=$((THREADS / MAX_PARALLEL_JOBS))
[[ $THREADS_PER_JOB -lt 2 ]] && THREADS_PER_JOB=2

# === Fonction pour traitement en lot avec parallélisation contrôlée ===
process_fastq_batch() {
    local files=("$@")
    local mode=$1  # "separate" ou "merge"
    shift
    files=("$@")
    
    local pids=()
    local active_jobs=0
    
    for fq in "${files[@]}"; do
        # Attendre si on a atteint le maximum de jobs parallèles
        while [[ $active_jobs -ge $MAX_PARALLEL_JOBS ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    unset pids[$i]
                    ((active_jobs--))
                fi
            done
            pids=("${pids[@]}")  # Réorganiser le tableau
            sleep 2
        done
        
        # Lancer le traitement du fichier en arrière-plan
        (
            BASENAME=$(basename "$fq")
            BASENAME=${BASENAME%.fastq.gz}
            BASENAME=${BASENAME%.fastq}
            OUT_BAM="$BAM_DIR/${BASENAME}.bam"
            
            echo "[$(date '+%H:%M:%S')] Début alignement: $fq → $OUT_BAM"
            
            # Options optimisées pour minimap2
            # -K 100M : augmente la taille des minimizers (plus rapide, légèrement moins précis)
            # --secondary=no : évite les alignements secondaires (plus rapide)
            # -I 8G : augmente la taille d'index en mémoire si assez de RAM
            minimap2 -t "$THREADS_PER_JOB" \
                     -Y -ax map-ont \
                     -K 100M \
                     --secondary=no \
                     -I 8G \
                     "$REFERENCE" "$fq" | \
                samtools sort -@ "$THREADS_PER_JOB" -m 2G -o "$OUT_BAM" -
            
            if [[ $? -eq 0 ]]; then
                # N'indexer que si mode séparé (barcode) ou si c'est le fichier final
                if [[ "$mode" == "separate" ]]; then
                    samtools index "$OUT_BAM"
                fi
                echo "[$(date '+%H:%M:%S')] Terminé: $OUT_BAM"
                echo "bam_file=$OUT_BAM" >> "$CONFIG_FILE"
            else
                echo "[ERREUR] Échec alignement: $fq" >&2
            fi
        ) &
        
        pids+=($!)
        ((active_jobs++))
    done
    
    # Attendre tous les jobs restants
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# === Fonction pour fusion intelligente par chunks ===
smart_merge_bams() {
    local bam_files=("$@")
    local output_bam="$BAM_DIR/${SAMPLE_NAME}.bam"
    local chunk_size=20
    local temp_bams=()
    
    echo " Fusion intelligente de ${#bam_files[@]} fichiers BAM..."
    
    # Si peu de fichiers, fusion directe
    if [[ ${#bam_files[@]} -le $chunk_size ]]; then
        samtools merge -@ "$THREADS" "$output_bam" "${bam_files[@]}"
        samtools index "$output_bam"
        return
    fi
    
    # Fusion par chunks pour éviter "too many open files"
    local chunk_num=0
    for ((i=0; i<${#bam_files[@]}; i+=chunk_size)); do
        chunk=("${bam_files[@]:$i:$chunk_size}")
        temp_bam="$BAM_DIR/temp_chunk_${chunk_num}.bam"
        
        echo "  Chunk $((chunk_num+1)): fusion de ${#chunk[@]} fichiers..."
        samtools merge -@ "$THREADS" "$temp_bam" "${chunk[@]}"
        temp_bams+=("$temp_bam")
        ((chunk_num++))
    done
    
    # Fusion finale des chunks
    echo "  Fusion finale des $chunk_num chunks..."
    samtools merge -@ "$THREADS" "$output_bam" "${temp_bams[@]}"
    samtools index "$output_bam"
    
    # Nettoyage des fichiers temporaires
    rm -f "${temp_bams[@]}"
    echo "bam_file=$output_bam" >> "$CONFIG_FILE"
}

# === TRAITEMENT PRINCIPAL ===
if [[ -d "$INPUT_PATH" ]]; then
    echo " Dossier détecté : $INPUT_PATH"
    
    # Collecte des fichiers FASTQ
    fastq_files=()
    for fq in "$INPUT_PATH"/*.fastq "$INPUT_PATH"/*.fastq.gz; do
        [[ -f "$fq" ]] && fastq_files+=("$fq")
    done
    
    if [[ ${#fastq_files[@]} -eq 0 ]]; then
        echo "Aucun fichier FASTQ trouvé dans $INPUT_PATH"
        exit 1
    fi
    
    echo " ${#fastq_files[@]} fichiers FASTQ détectés"
    
    # Affichage des tailles pour diagnostic
    echo " Tailles des fichiers :"
    for fq in "${fastq_files[@]}"; do
        size=$(du -h "$fq" | cut -f1)
        echo "  $(basename "$fq"): $size"
    done
    
    # Détection du type de fichiers
    contains_barcode="no"
    for fq in "${fastq_files[@]}"; do
        if [[ "$(basename "$fq")" == *barcode* ]]; then
            contains_barcode="yes"
            break
        fi
    done
    
    if [[ "$contains_barcode" == "yes" ]]; then
        echo " Mode barcode: alignements séparés avec indexation"
        process_fastq_batch "separate" "${fastq_files[@]}"
    else
        echo " Mode fusion: alignement puis fusion (pas d'indexation intermédiaire)"
        bam_parts=()
        
        # Traitement en lot SANS indexation
        process_fastq_batch "merge" "${fastq_files[@]}"
        
        # Collecte des BAM générés pour fusion
        for fq in "${fastq_files[@]}"; do
            BASENAME=$(basename "$fq")
            BASENAME=${BASENAME%.fastq.gz}
            BASENAME=${BASENAME%.fastq}
            bam_parts+=("$BAM_DIR/${BASENAME}.bam")
        done
        
        # Fusion intelligente (avec indexation finale seulement)
        smart_merge_bams "${bam_parts[@]}"
        
        # Nettoyage des BAM partiels (pas d'index à supprimer)
        echo " Nettoyage des fichiers intermédiaires..."
        rm -f "${bam_parts[@]}"
    fi
    
elif [[ -f "$INPUT_PATH" ]]; then
    echo " Fichier unique détecté : $INPUT_PATH"
    
    # Affichage de la taille pour diagnostic
    size=$(du -h "$INPUT_PATH" | cut -f1)
    echo " Taille: $size"
    
    BASENAME=$(basename "$INPUT_PATH")
    BASENAME=${BASENAME%.fastq.gz}
    BASENAME=${BASENAME%.fastq}
    
    if [[ "$BASENAME" == *barcode* ]]; then
        OUT_BAM="$BAM_DIR/${BASENAME}.bam"
    else
        OUT_BAM="$BAM_DIR/${SAMPLE_NAME}.bam"
    fi
    
    echo  "$INPUT_PATH → $OUT_BAM"
    
    # Options optimisées pour fichier unique
    minimap2 -t "$THREADS" \
             -Y -ax map-ont \
             -K 100M \
             --secondary=no \
             -I 8G \
             "$REFERENCE" "$INPUT_PATH" | \
        samtools sort -@ "$THREADS" -m 2G -o "$OUT_BAM" -
    
    samtools index "$OUT_BAM"
    echo "bam_file=$OUT_BAM" >> "$CONFIG_FILE"
    
else
    echo "Chemin invalide : $INPUT_PATH"
    exit 1
fi

echo "Alignement terminé pour $SAMPLE_NAME"
echo " Résultats dans: $BAM_DIR"