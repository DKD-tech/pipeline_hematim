# #!/bin/bash
# exec > >(tee -a run_pipeline_debug.log) 2>&1
# set -x

# Configuration
PIPELINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVS_DIR="${PIPELINE_DIR}/envs"
REQUIRED_ENVS=("sv_env" "sv_sniff" "cnvkittenv")

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE} Démarrage du pipeline ${NC}"
echo "================================================"

# Fonction : Vérifier si conda est installé
check_conda() {
    if ! command -v conda &> /dev/null; then
        echo -e "${RED} ERREUR : conda n'est pas installé ou pas dans le PATH${NC}"
        echo "   Veuillez installer Miniconda/Anaconda et réessayer"
        exit 1
    fi
    echo -e "${GREEN} conda détecté${NC}"
}

# Fonction : Vérifier si un environnement existe
env_exists() {
    conda env list | grep -q "^$1 "
}

# Fonction : Installer un environnement
install_env() {
    local env_name=$1
    local yml_file="${ENVS_DIR}/${env_name}.yml"
    
    echo -e "${YELLOW} Installation de l'environnement ${env_name}...${NC}"
    
    if conda env create -f "$yml_file" --quiet; then
        echo -e "${GREEN} ${env_name} installé avec succès${NC}"
        return 0
    else
        echo -e "${RED} Échec de l'installation de ${env_name}${NC}"
        return 1
    fi
}

# Fonction : Setup automatique des environnements
setup_environments() {
    echo -e "${BLUE}🔧 Vérification des environnements...${NC}"
    
    local missing_envs=()
    
    # Vérifier quels environnements manquent
    for env in "${REQUIRED_ENVS[@]}"; do
        if env_exists "$env"; then
            echo -e "${GREEN} ${env} : OK${NC}"
        else
            echo -e "${YELLOW}  ${env} : manquant${NC}"
            missing_envs+=("$env")
        fi
    done
    
    # Installer les environnements manquants
    if [ ${#missing_envs[@]} -gt 0 ]; then
        echo -e "${BLUE} Installation des environnements manquants...${NC}"
        
        for env in "${missing_envs[@]}"; do
            install_env "$env"
        done
        
        echo -e "${GREEN} Tous les environnements sont maintenant installés !${NC}"
    else
        echo -e "${GREEN} Tous les environnements sont déjà installés !${NC}"
    fi
}



non_interactive=false
CONFIG_FILE="user_config.txt"

# Si on connaît déjà le nom de l’échantillon (via --sample), on construit tout de suite le bon chemin
if [[ -n "$sample_name" ]]; then
    RESULT_DIR="results/${sample_name}"
    mkdir -p "$RESULT_DIR"
    CONFIG_FILE="${RESULT_DIR}/config_${sample_name}.txt"
    echo " ➤ Utilisation du fichier de config : $CONFIG_FILE"
fi

# === Fonction pour lire la config existante ===
function load_user_config() {
    if [[ -n "$sample_name" && -f "$CONFIG_FILE" ]]; then
        echo " Configuration existante détectée dans $CONFIG_FILE. Chargement..."
        source "$CONFIG_FILE"
        return
    fi

   # else
        echo "️  Première utilisation : configuration rapide"

        # Demander uniquement le nom d’échantillon
        read -p "Nom de l’échantillon : " sample_name


        # Construire le fichier de config à partir du nom fourni
        RESULT_DIR="results/${sample_name}"
        mkdir -p "$RESULT_DIR"
        CONFIG_FILE="${RESULT_DIR}/config_${sample_name}.txt"
        echo " ➤ Fichier de config : $CONFIG_FILE"
    
        # Référence par défaut
        reference="/users/dkdiakite/mes_jobs/input/hg38.fa"
        #  reference="/scratch/dkdiakite/data/test_data/wf-human-variation-demo/demo.fasta"
        if [[ ! -f "$reference" ]]; then
            echo " Référence $reference introuvable, vérifie le chemin dans le script."
            exit 1
        fi

        # Valeurs par défaut pour le cluster
        partition="bigmem,bigmem-amd"
        threads=16

        echo "  Paramètres utilisés :"
        echo "  ➤ Échantillon     : $sample_name"
        echo "  ➤ Référence       : $reference"
        echo "  ➤ Partition SLURM : $partition"
        echo "  ➤ Threads         : $threads"

        # Sauvegarde
        cat <<EOF > "$CONFIG_FILE"
sample_name=$sample_name
reference=$reference
partition=$partition
threads=$threads
EOF
        echo "Configuration enregistrée dans $CONFIG_FILE"
  
}

# === Réinitialiser la configuration utilisateur ===
function reset_config() {
    echo ""
    echo " Cette action va supprimer votre configuration actuelle."
    read -p "Êtes-vous sûr ? (o/N) : " confirm
    if [[ "$confirm" == "o" || "$confirm" == "O" ]]; then
        rm -f "$CONFIG_FILE"
        echo "️  Configuration supprimé : $CONFIG_FILE."
        load_user_config  # Relance immédiate de la config
    else
        echo "Réinitialisation annulée."
    fi
}

# === Fonction pour afficher le menu ===
function show_menu() {
    echo ""
    echo "========================================================="
    echo " Pipeline de détection de variants Nanopore - UPJV"
    echo "========================================================="
    echo "Veuillez choisir une action :"
    echo "0 - Réinitialiser la configuration utilisateur"
    echo "1 - Lancer tout le pipeline"
    echo "2 - Lancer une ou plusieurs étapes manuellement"
    echo "3 - Afficher les explications sur chaque étape"
    echo "4 - Quitter"
    echo "---------------------------------------------------------"
    read -p "Votre choix [0-4] : " choice
}

function execute_steps_with_dependencies() {
    echo "DEBUG :: Début de execute_steps_with_dependencies"
    echo "DEBUG :: Étapes reçues : $*"
    local steps=("$@")
    local jobids=()
    
    # Charger le BAM si présent dans le fichier de config
    if [[ -z "$bam_file" && -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi

   
    echo ""
    echo "🔄 Exécution des étapes avec gestion des dépendances : ${steps[*]}"
    echo ""
   
    # Variables pour stocker les job IDs des étapes critiques
    local jobid_align=""
    local jobid_snps=""
    local jobid_svs=""
    local jobid_cnv=""
    local jobid_qc=""
    local jobid_methylation=""
    local jobid_annotation=""
   
    # Traitement séquentiel des étapes avec dépendances
    for step in "${steps[@]}"; do
        case $step in
            1) # Alignement
                echo " Étape 1 - Alignement"
                if [[ -z "$fastq_input" ]]; then
                    read -p "Chemin du fichier FASTQ ou dossier FASTQ à aligner : " fastq_input
                    if [[ ! -e "$fastq_input" ]]; then
                        echo "[ERREUR] Fichier ou dossier FASTQ introuvable : $fastq_input"
                        continue
                    fi
                fi
               
                jobid_align=$(sbatch --partition="$partition" --cpus-per-task="$threads" --mem=128G \
                    --output="logs/step1_align_%j.out" \
                    sbatch/step1_align.sbatch "$sample_name" "$threads" "$fastq_input" "$reference" | awk '{print $4}')
               
                if [[ -n "$jobid_align" ]]; then
                    echo "Alignement soumis - Job ID : $jobid_align"
                else
                    echo "Erreur lors de la soumission de l'alignement"
                    return 1
                fi
                ;;
               
            2) # SNPs
                echo " Étape 2 - Détection de SNPs"
               
                # Déterminer les dépendances
                local dep_opt=""
                if [[ -n "$jobid_align" ]]; then
                    dep_opt="--dependency=afterok:$jobid_align"
                    echo "  Dépend de l'alignement (Job $jobid_align)"
                fi
               
                # Vérifier/demander le BAM si nécessaire
                local bam_to_use="${bam_file:-results/${sample_name}/mapping/${sample_name}.bam}"
                if [[ -z "$jobid_align" && ! -f "$bam_to_use" ]]; then
                    read -p "Chemin du fichier BAM pour les SNPs : " bam_to_use
                    if [[ ! -f "$bam_to_use" ]]; then
                        echo "Fichier BAM introuvable : $bam_to_use"
                        continue
                    fi
                fi
               
                # Demander BED et phasage si pas déjà définis
                if [[ "$non_interactive" != "true" && -z "$bed_file" ]]; then
                read -p 'Fichier BED (optionnel, Entrée pour ignorer) : ' bed_file
                fi
                if [[ -z "$do_phasing" ]]; then
                    read -p "Effectuer le phasage avec WhatsHap ? (o/N) : " phasing_answer
                    if [[ "$phasing_answer" == "o" || "$phasing_answer" == "O" ]]; then
                        do_phasing="yes"
                    else
                        do_phasing="no"
                    fi
                fi
               
                jobid_snps=$(sbatch $dep_opt --partition="$partition" --cpus-per-task="$threads" --mem=256G \
                    --output="logs/step2_snps_%j.out" \
                    sbatch/step2_snps.sbatch "$sample_name" "$bam_to_use" "$reference" "$threads" "$bed_file" "$do_phasing" | awk '{print $4}')
               
                if [[ -n "$jobid_snps" ]]; then
                    echo "SNPs soumis - Job ID : $jobid_snps"
                else
                    echo "Erreur lors de la soumission des SNPs"
                fi
                ;;
               
            3) # SVs
                echo " Étape 3 - Détection de SVs"
               
                # Déterminer les dépendances
                local dep_opt=""
                if [[ -n "$jobid_align" ]]; then
                    dep_opt="--dependency=afterok:$jobid_align"
                    echo "    Dépend de l'alignement (Job $jobid_align)"
                fi
               
                # Vérifier/demander le BAM si nécessaire
                local bam_to_use="results/${sample_name}/mapping/${sample_name}.bam"
                if [[ -z "$jobid_align" && ! -f "$bam_to_use" ]]; then
                    read -p "Chemin du fichier BAM pour les SVs : " bam_to_use
                    if [[ ! -f "$bam_to_use" ]]; then
                        echo "Fichier BAM introuvable : $bam_to_use"
                        continue
                    fi
                fi
               
                jobid_svs=$(sbatch $dep_opt --partition="$partition" --cpus-per-task="$threads" --mem=256G \
                    --output="logs/step3_svs_%j.out" \
                    sbatch/step3_svs.sbatch "$sample_name" "$bam_to_use" "$reference" "$threads" "$bed_file" | awk '{print $4}')
               
                if [[ -n "$jobid_svs" ]]; then
                    echo "SVs soumis - Job ID : $jobid_svs"
                else
                    echo "Erreur lors de la soumission des SVs"
                fi
                ;;
               
            4) # CNVkit
                echo " Étape 4 - Détection de CNVs"
               
                # Déterminer les dépendances (peut dépendre de l'alignement ou des SVs)
                local dep_opt=""
                if [[ -n "$jobid_svs" ]]; then
                    dep_opt="--dependency=afterok:$jobid_svs"
                    echo "   Dépend des SVs (Job $jobid_svs)"
                elif [[ -n "$jobid_align" ]]; then
                    dep_opt="--dependency=afterok:$jobid_align"
                    echo "   Dépend de l'alignement (Job $jobid_align)"
                fi
               
                # Vérifier/demander le BAM si nécessaire
                local bam_to_use="results/${sample_name}/mapping/${sample_name}.bam"
                if [[ -z "$jobid_align" && ! -f "$bam_to_use" ]]; then
                    read -p "Chemin du fichier BAM pour CNVkit : " bam_to_use
                    if [[ ! -f "$bam_to_use" ]]; then
                        echo "Fichier BAM introuvable : $bam_to_use"
                        continue
                    fi
                fi
               
                jobid_cnv=$(sbatch $dep_opt --partition="$partition" --cpus-per-task="$threads" --mem=256G \
                    --output="logs/step4_cnvkit_%j.out" \
                    sbatch/step4_cnvkit.sbatch "$sample_name" "$reference" "$threads" "$bed_file" "$bam_to_use" | awk '{print $4}')
               
                if [[ -n "$jobid_cnv" ]]; then
                    echo "CNVkit soumis - Job ID : $jobid_cnv"
                else
                    echo "Erreur lors de la soumission de CNVkit"
                fi
                ;;
               
            5) # Méthylation
                echo " Étape 5 - Méthylation"
               
                # Déterminer les dépendances
                local dep_opt=""
                if [[ -n "$jobid_align" ]]; then
                    dep_opt="--dependency=afterok:$jobid_align"
                    echo "  Dépend de l'alignement (Job $jobid_align)"
                fi
               
                # Demander les fichiers spécifiques pour la méthylation
                if [[ -z "$modified_bam" ]]; then
                    read -p "Chemin du fichier BAM modifié (annoté avec modkit) : " modified_bam
                    if [[ ! -f "$modified_bam" ]]; then
                        echo "Fichier BAM modifié introuvable : $modified_bam"
                        continue
                    fi
                fi
               
                if [[ -z "$region_file" ]]; then
                    read -p "Chemin du fichier de régions (BED) : " region_file
                    if [[ ! -f "$region_file" ]]; then
                        echo "Fichier de régions introuvable : $region_file"
                        continue
                    fi
                fi
               
                jobid_methylation=$(sbatch $dep_opt --partition="$partition" --cpus-per-task="$threads" --mem=256G \
                    --output="logs/step5_methylation_%j.out" \
                    sbatch/step5_methylation.sbatch "$sample_name" "$reference" "$threads" "$region_file" "$modified_bam" | awk '{print $4}')
               
                if [[ -n "$jobid_methylation" ]]; then
                    echo "Méthylation soumise - Job ID : $jobid_methylation"
                else
                    echo "Erreur lors de la soumission de la méthylation"
                fi
                ;;
               
            6) # QC
                echo " Étape 6 - Contrôle qualité"
               
                # Déterminer les dépendances
                local dep_opt=""
                if [[ -n "$jobid_align" ]]; then
                    dep_opt="--dependency=afterok:$jobid_align"
                    echo "   Dépend de l'alignement (Job $jobid_align)"
                fi
               
                # Vérifier/demander le BAM si nécessaire
                local bam_to_use="results/${sample_name}/mapping/${sample_name}.bam"
                if [[ -z "$jobid_align" && ! -f "$bam_to_use" ]]; then
                    read -p "Chemin du fichier BAM pour le QC : " bam_to_use
                    if [[ ! -f "$bam_to_use" ]]; then
                        echo "Fichier BAM introuvable : $bam_to_use"
                        continue
                    fi
                fi
               
                jobid_qc=$(sbatch $dep_opt --partition="$partition" --cpus-per-task="$threads" --mem=256G \
                    --output="logs/step6_qc_%j.out" \
                    sbatch/step6_qc.sbatch "$sample_name" "$bam_to_use" "$threads" "$reference" "$bed_file" | awk '{print $4}')
               
                if [[ -n "$jobid_qc" ]]; then
                    echo "QC soumis - Job ID : $jobid_qc"
                else
                    echo "Erreur lors de la soumission du QC"
                fi
                ;;
               
            7) # Annotation
                echo " Étape 7 - Annotation"
               
                # Déterminer les dépendances
                local dep_opt=""
                if [[ -n "$jobid_snps" ]]; then
                    dep_opt="--dependency=afterok:$jobid_snps"
                    echo "   Dépend des SNPs (Job $jobid_snps)"
                fi
               
                # Vérifier/demander le VCF si nécessaire
                local vcf_to_use="results/${sample_name}/snps_clair3/merge_output.vcf.gz"
                if [[ -z "$jobid_snps" && ! -f "$vcf_to_use" ]]; then
                    read -p "Chemin du fichier VCF pour l'annotation : " vcf_to_use
                    if [[ ! -f "$vcf_to_use" ]]; then
                        echo "Fichier VCF introuvable : $vcf_to_use"
                        continue
                    fi
                fi
               
                jobid_annotation=$(sbatch $dep_opt --partition="$partition" --cpus-per-task="$threads" --mem=256G \
                    --output="logs/step7_annotation_%j.out" \
                    sbatch/step7_annotation.sbatch "$sample_name" "$vcf_to_use" "$threads" "$reference" | awk '{print $4}')
               
                if [[ -n "$jobid_annotation" ]]; then
                    echo "Annotation soumise - Job ID : $jobid_annotation"
                else
                    echo "Erreur lors de la soumission de l'annotation"
                fi
                ;;
               
            *)
                echo "Étape inconnue : $step"
                ;;
        esac
    done
   
    echo ""
    echo " Résumé des jobs soumis :"
    [[ -n "$jobid_align" ]] && echo "   ➤ Alignement     : $jobid_align"
    [[ -n "$jobid_snps" ]] && echo "   ➤ SNPs           : $jobid_snps"
    [[ -n "$jobid_svs" ]] && echo "   ➤ SVs            : $jobid_svs"
    [[ -n "$jobid_cnv" ]] && echo "   ➤ CNVkit         : $jobid_cnv"
    [[ -n "$jobid_methylation" ]] && echo "   ➤ Méthylation    : $jobid_methylation"
    [[ -n "$jobid_qc" ]] && echo "   ➤ QC             : $jobid_qc"
    [[ -n "$jobid_annotation" ]] && echo "   ➤ Annotation     : $jobid_annotation"
    echo ""
}

if [[ "$1" == "--non-interactive" ]]; then
non_interactive=true
    # Mode non-interactif : lire les paramètres depuis les arguments
    selected_steps=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --sample) sample_name="$2"; shift 2 ;;
            --reference) reference="$2"; shift 2 ;;
            --partition) partition="$2"; shift 2 ;;
            --threads) threads="$2"; shift 2 ;;
            --fastq_input) fastq_input="$2"; shift 2 ;;
            --bed) bed_file="$2"; shift 2 ;;
            --phase) do_phasing="yes"; shift ;;
            --option) menu_choice="$2"; shift 2 ;;
            --step) selected_steps+=("$2"); shift 2 ;;
            --bam_input) bam_file="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

  if [[ "$menu_choice" == "1" ]]; then
    echo "🧪 Pipeline complet sélectionné (--option 1)"
    
    # Vérification de l'échantillon
    if [[ -z "$sample_name" ]]; then
        echo "[ERREUR] --sample non fourni"
        exit 1
    fi

    CONFIG_FILE="results/${sample_name}/config_${sample_name}.txt"

    # Charger la configuration si elle existe
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "🔁 Chargement de la configuration depuis : $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        echo "[ERREUR] Fichier de configuration introuvable pour l’échantillon : $sample_name"
        exit 1
    fi

    # Vérifications essentielles
    if [[ -z "$reference" ]]; then
        echo "[ERREUR] --reference manquant"
        exit 1
    fi
    if [[ -z "$fastq_input" ]]; then
        echo "[ERREUR] --fastq_input manquant"
        exit 1
    fi

    # Récupération fallback du BED et phasage
    bed_file="${bed_file:-$BED}"
    do_phasing="${do_phasing:-$DO_PHASING}"

    # Si aucune étape n'est fournie, définir les étapes par défaut
    if [[ ${#selected_steps[@]} -eq 0 ]]; then
        selected_steps=(1 2 3 4 6 7)
    fi

    # Debug print (important pour Streamlit)
    echo "✅ Étapes à exécuter : ${selected_steps[*]}"

    # Workaround pour s'assurer que la variable est bien transmise
    steps_to_run=("${selected_steps[@]}")
    echo "DEBUG :: Appel à execute_steps_with_dependencies avec : ${steps_to_run[*]}"
    
    # Appel explicite
    execute_steps_with_dependencies "${steps_to_run[@]}"

    echo "✅ Tous les jobs ont été soumis."
    exit 0
fi
if [[ "$menu_choice" == "2" ]]; then
    echo "🔧 Mode manuel sélectionné (--option 2)"
    
    if [[ ${#selected_steps[@]} -eq 0 ]]; then
        echo "[ERREUR] Aucun --step spécifié"
        exit 1
    fi

    echo "✅ Étapes manuelles demandées : ${selected_steps[*]}"
    execute_steps_with_dependencies "${selected_steps[@]}"
    echo "✅ Étapes terminées."
    exit 0
fi

fi

# === Fonction pour lancer une étape manuelle ===
function choose_steps() {
    load_user_config
    
    echo ""
    echo "Étapes disponibles :"
    echo "1 - Alignement (minimap2 + samtools)"
    echo "2 - Détection de SNPs (Clair3 ou bcftools)"
    echo "3 - Détection de SVs (Sniffles2, cuteSV + SURVIVOR)"
    echo "4 - CNV (CNVkit)"
    echo "5 - Méthylation (modkit + methylArtist)"
    echo "6 - QC (Samtools_stats, NanoStat, MultiQC)"
    echo "7 - Annotation des SNPs (VEP, Annovar )"
    echo "8 - Retour au menu principal"
    echo ""
    echo " Les dépendances seront automatiquement gérées :"
    echo "   • SNPs, SVs, CNV, QC dépendent de l'Alignement"
    echo "   • CNVkit peut dépendre des SVs si les deux sont sélectionnés"
    echo "   • Annotation dépend des SNPs"
    echo ""

    read -p "Entrez les numéros des étapes à exécuter (ex: 1 3 5) : " steps_input

 # Conversion en tableau
    read -ra selected_steps <<< "$steps_input"
   
    # Vérification de la validité des étapes
    valid_steps=()
    for step in "${selected_steps[@]}"; do
        if [[ "$step" =~ ^[1-7]$ ]]; then
            valid_steps+=("$step")
        elif [[ "$step" == "8" ]]; then
            echo " Retour au menu principal"
            return
        else
            echo " Étape ignorée (invalide) : $step"
        fi
    done
   
    if [[ ${#valid_steps[@]} -eq 0 ]]; then
        echo "Aucune étape valide sélectionnée"
        return
    fi
   
    # Tri des étapes pour respecter l'ordre logique
    IFS=$'\n' sorted_steps=($(sort -n <<< "${valid_steps[*]}"))
    unset IFS
   
    echo ""
    echo " Étapes sélectionnées (ordre d'exécution) : ${sorted_steps[*]}"
    read -p "Confirmer l'exécution ? (o/N) : " confirm
   
    if [[ "$confirm" == "o" || "$confirm" == "O" ]]; then
        execute_steps_with_dependencies "${sorted_steps[@]}"
    else
        echo "Exécution annulée"
    fi
    
     for step in $steps; do
        case $step in
            1) run_alignment ;;
            2) run_snps ;;
            3) run_svs ;;
            4) run_cnvkit ;;
            5) run_methylation ;;
            6) run_qc ;;
            7) run_annotation ;;
            *) echo " Étape inconnue : $step" ;;
        esac
    done
}


function run_alignment() {
    load_user_config


    echo "Étape 1 - Alignement"
    read -p "Chemin du fichier FASTQ ou dossier FASTQ à aligner (dossier si fusion désirée) : " fastq_input


    fastq_files_list=()


    #  Collecte des fichiers FASTQ
    if [[ -d "$fastq_input" ]]; then
        echo " Dossier détecté : $fastq_input"
        for f in "$fastq_input"/*.fastq "$fastq_input"/*.fastq.gz; do
            [[ -f "$f" ]] && fastq_files_list+=("$f")
        done
    elif [[ -f "$fastq_input" ]]; then
        fastq_files_list+=("$fastq_input")
    else
        IFS=',' read -ra inputs <<< "$fastq_input"
        for f in "${inputs[@]}"; do
            if [[ -f "$f" ]]; then
                fastq_files_list+=("$f")
            else
                echo "[ERREUR] Fichier introuvable : $f"
                exit 1
            fi
        done
    fi


    if [[ ${#fastq_files_list[@]} -eq 0 ]]; then
        echo "[ERREUR] Aucun fichier FASTQ détecté."
        exit 1
    fi


    mkdir -p logs results/"$sample_name"/mapping


    #  Enregistrement de l'entrée dans la config (fastq_dir ou fastq_files)
    if [[ -d "$fastq_input" ]]; then
        echo "fastq_dir=$fastq_input" >> "$CONFIG_FILE"
    else
        echo "fastq_files=${fastq_files_list[*]}" >> "$CONFIG_FILE"
    fi


    #  Soumission SLURM (le script .sbatch gère tout)
    # for fq in "${fastq_files_list[@]}"; do
    #     fq_base=$(basename "$fq")
    #     fq_base=${fq_base%.fastq.gz}
    #     fq_base=${fq_base%.fastq}


       echo " Soumission SLURM pour l'alignement..."
    sbatch --partition="$partition" --cpus-per-task="$threads" --mem=128G \
        --output="logs/step1_align_%j.out" \
        sbatch/step1_align.sbatch "$sample_name" "$threads" "$fastq_input" "$reference"

    # done


    echo " Le fichier BAM final sera automatiquement renseigné par le script SBATCH dans :"
    echo "  results/$sample_name/config_${sample_name}.txt"
}


function run_snps() {
    load_user_config
    local dependency=$1
    local dep_opt=""
    [[ -n "$dependency" ]] && dep_opt="--dependency=afterok:$dependency"
    
    # Chemin BAM attendu depuis l'alignement automatique
    expected_bam="results/${sample_name}/mapping/${sample_name}.bam"

    # === LOGIQUE FLEXIBLE POUR LE BAM ===
    # 1. Si bam_file est déjà défini dans la config ET existe → l'utiliser
    if [[ -n "$bam_file" && -f "$bam_file" ]]; then
        echo "BAM détecté depuis la configuration : $bam_file"
        
    # 2. Si le BAM attendu (depuis alignement) existe → l'utiliser
    elif [[ -f "$expected_bam" ]]; then
        echo "BAM détecté depuis l'alignement automatique : $expected_bam"
        bam_file="$expected_bam"
        # Mise à jour de la config
        sed -i '/^bam_file=/d' "$CONFIG_FILE"
        echo "bam_file=$bam_file" >> "$CONFIG_FILE"
        
    # 3. Sinon, demander à l'utilisateur
    else
        echo ""
        echo "  Aucun fichier BAM automatique trouvé pour l'échantillon '$sample_name'"
        echo "   ➤ BAM attendu (depuis alignement) : $expected_bam"
        echo "   ➤ BAM actuellement configuré : ${bam_file:-'non défini'}"
        echo ""
        read -p " Souhaitez-vous fournir un chemin BAM personnalisé ? (o/N) : " answer
        
        if [[ "$answer" == "o" || "$answer" == "O" ]]; then
            read -p " Chemin complet du fichier BAM : " user_bam
            
            # Vérification de l'existence du fichier fourni
            if [[ -f "$user_bam" ]]; then
                echo "Fichier BAM valide : $user_bam"
                bam_file="$user_bam"
                # Mise à jour propre du fichier de config
                sed -i '/^bam_file=/d' "$CONFIG_FILE"
                echo "bam_file=$bam_file" >> "$CONFIG_FILE"
                echo " Configuration mise à jour avec le nouveau BAM"
            else
                echo "Fichier introuvable : $user_bam"
                echo "Vérifiez le chemin et les permissions d'accès"
                return 1
            fi
        else
            echo " Annulation de l'étape SNPs."
            return 1
        fi
    fi
    
    # === À ce point, bam_file est forcément défini et valide ===
    echo "fichier BAM utilisé : $bam_file"
    
    # === DEMANDE DU FICHIER BED (optionnel) ===
    read -p " Souhaitez-vous fournir un fichier BED pour restreindre les régions ? (o/N) : " answer
    if [[ "$answer" == "o" || "$answer" == "O" ]]; then
        read -p "Chemin du fichier BED : " bed_file
        if [[ ! -f "$bed_file" ]]; then
            echo " Fichier BED introuvable : $bed_file"
            echo "Continuation sans fichier BED"
            bed_file=""
        else
            echo "Fichier BED valide : $bed_file"
        fi
    else
        bed_file=""
    fi
    
    # === DEMANDE DU PHASAGE ===
    read -p " Souhaitez-vous effectuer le phasage avec WhatsHap ? (o/N) : " phasing_answer
    if [[ "$phasing_answer" == "o" || "$phasing_answer" == "O" ]]; then
        do_phasing="yes"
        echo " Phasage activé avec WhatsHap"
    else
        do_phasing="no"
        echo "  Phasage désactivé"
    fi

    # === SOUMISSION SLURM ===
    echo ""
    echo "Soumission de l'étape SNPs avec Clair3..."
    echo "   ➤ Échantillon : $sample_name"
    echo "   ➤ BAM : $bam_file"
    echo "   ➤ Référence : $reference"
    echo "   ➤ Threads : $threads"
    echo "   ➤ BED : ${bed_file:-'aucun'}"
    echo "   ➤ Phasage : $do_phasing"
    
    mkdir -p logs
    
    jobid=$(sbatch $dep_opt --partition="$partition" --cpus-per-task="$threads" --mem=256G \
        --output="logs/step2_snps_%j.out" \
        sbatch/step2_snps.sbatch "$sample_name" "$bam_file" "$reference" "$threads" "$bed_file" "$do_phasing" | awk '{print $4}')
    
    if [[ -n "$jobid" ]]; then
        echo "Job SLURM soumis avec succès"
        echo "   ➤ Job ID : $jobid"
        echo "   ➤ Log : logs/step2_snps_${jobid}.out"
        echo "   ➤ Résultats attendus : results/$sample_name/snps_clair3/"
        return 0
    else
        echo "Erreur lors de la soumission du job SLURM"
        return 1
    fi
}
function run_annotation() {
  load_user_config
    local dependency=$1
    local dep_opt=""
    [[ -n "$dependency" ]] && dep_opt="--dependency=afterok:$dependency"  
    
    expected_vcf="results/${sample_name}/snps_clair3/merge_output.vcf.gz"

    # Vérification du fichier utilisateur
    if [[ "$vcf_file" != "$expected_vcf" || ! -f "$vcf_file" ]]; then
        echo ""
        echo "  Aucun fichier VCF correspondant à l’échantillon actuel ($sample_name) n’a été trouvé."
        echo "   ➤ VCF attendu : $expected_vcf"
        read -p "Souhaitez-vous entrer un chemin VCF ? (o/N) : " answer
    
        if [[ "$answer" == "o" || "$answer" == "O" ]]; then
            read -p "Chemin du fichier VCF : " vcf_file
            if [[ ! -f "$vcf_file" ]]; then
                echo "Fichier introuvable : $vcf_file"
                return
            fi
            # Mise à jour propre dans la config
            sed -i '/^vcf_file=/d' "$CONFIG_FILE"
            echo "vcf_file=$vcf_file" >> "$CONFIG_FILE"
        else
            echo " Annulation de l'étape Annotation."
            return
        fi
    else
        echo " VCF détecté : $vcf_file"
    fi
    
    # Décompression automatique si l’utilisateur fournit un .vcf non compressé
    if [[ "$vcf_file" == *.vcf && ! "$vcf_file" == *.vcf.gz ]]; then
        echo "Compression du fichier utilisateur..."
        bgzip -c "$vcf_file" > "${vcf_file}.gz"
        vcf_file="${vcf_file}.gz"
    fi
    
    echo "Soumission de l'étape Annotation avec Vep & Annovar..."
    mkdir -p logs
    
    echo " Soumission SLURM de l'étape Annotation..."
    sbatch $dep_opt --partition="$partition" --cpus-per-task="$threads" --mem=256G \
    --output="logs/step7_annotation_%j.out" \
    sbatch/step7_annotation.sbatch "$sample_name" "$vcf_file" "$threads" "$reference"

}

function run_svs() {
    load_user_config
    local dependency=$1
    local dep_opt=""
    [[ -n "$dependency" ]] && dep_opt="--dependency=afterok:$dependency"

     if [[ -z "$bam_file" ]]; then
        source "$CONFIG_FILE"
    fi
    # Vérification du BAM en cohérence avec le sample
	expected_bam="results/${sample_name}/mapping/${sample_name}.bam"

	if [[ "$bam_file" != "$expected_bam" || ! -f "$bam_file" ]]; then
    	echo ""
    	echo "  Aucun fichier BAM correspondant à l’échantillon actuel ($sample_name) n’a été trouvé."
    	echo "   ➤ BAM attendu : $expected_bam"
    	read -p "Souhaitez-vous entrer un chemin BAM  ? (o/N) : " answer
    	if [[ "$answer" == "o" || "$answer" == "O" ]]; then
        	read -p "Chemin du fichier BAM : " bam_file
        	if [[ ! -f "$bam_file" ]]; then
            	echo " Fichier introuvable : $bam_file"
            	return
        	fi
        	# Mise à jour propre du fichier de config
        	sed -i '/^bam_file=/d' "$CONFIG_FILE"
        	echo "bam_file=$bam_file" >> "$CONFIG_FILE"
    	else
        	echo " Annulation de l'étape SVS."
        	return
    	fi
	else
    	echo " BAM détecté : $bam_file"
	fi
    
    # Demande d’un fichier BED optionnel
    read -p "Souhaitez-vous fournir un fichier BED pour restreindre les régions ? (o/N) : " answer
    if [[ "$answer" == "o" || "$answer" == "O" ]]; then
        read -p "Chemin du fichier BED : " bed_file
        if [[ ! -f "$bed_file" ]]; then
            echo "Fichier BED introuvable : $bed_file"
            return
        fi
    else
        bed_file=""
    fi
    
    echo " Étape 3 - Détection des SVs (Sniffles2 + CuteSV + SURVIVOR)"
    mkdir -p logs

    sbatch $dep_opt --partition="$partition" --cpus-per-task="$threads" --mem=256G \
        --output="logs/step3_svs_%j.out" \
        sbatch/step3_svs.sbatch "$sample_name" "$bam_file" "$reference" "$threads" "$bed_file"  | awk '{print $4}'
}

function run_cnvkit() {
    load_user_config
    local dependency=$1
    local dep_opt=""
    [[ -n "$dependency" ]] && dep_opt="--dependency=afterok:$dependency"

    echo " Étape 4 - Détection de CNVs (CNVkit)"

   expected_bam="results/${sample_name}/mapping/${sample_name}.bam"

# === LOGIQUE FLEXIBLE POUR LE BAM ===
    # 1. Si cnv_bam est déjà défini dans la config ET existe → l'utiliser
    if [[ -n "$cnv_bam" && -f "$cnv_bam" ]]; then
        echo "BAM CNV détecté depuis la configuration : $cnv_bam"
    
    # 2. Si le BAM attendu (depuis alignement) existe → l'utiliser
    elif [[ -f "$expected_bam" ]]; then
        echo "BAM CNV détecté depuis l'alignement automatique : $expected_bam"
        cnv_bam="$expected_bam"
        # Mise à jour de la config
        sed -i '/^cnv_bam=/d' "$CONFIG_FILE"
        echo "cnv_bam=$cnv_bam" >> "$CONFIG_FILE"
        
    # 3. Sinon, demander à l'utilisateur
    else
        echo ""
        echo "  Aucun fichier BAM CNV automatique trouvé pour l'échantillon '$sample_name'"
        echo "   ➤ BAM attendu (depuis alignement) : $expected_bam"
        echo "   ➤ BAM CNV actuellement configuré : ${cnv_bam:-'non défini'}"
        echo ""
        read -p " Souhaitez-vous fournir un chemin BAM CNV personnalisé ? (o/N) : " answer
        
        if [[ "$answer" == "o" || "$answer" == "O" ]]; then
            read -p " Chemin complet du fichier BAM CNV : " user_bam
            
            # Vérification de l'existence du fichier fourni
            if [[ -f "$user_bam" ]]; then
                echo "Fichier BAM CNV valide : $user_bam"
                cnv_bam="$user_bam"
                # Mise à jour propre du fichier de config
                sed -i '/^cnv_bam=/d' "$CONFIG_FILE"
                echo "cnv_bam=$cnv_bam" >> "$CONFIG_FILE"
                echo " Configuration mise à jour avec le nouveau BAM CNV"
            else
                echo "Fichier introuvable : $user_bam"
                echo " Vérifiez le chemin et les permissions d'accès"
                return 1
            fi
        else
            echo "  Annulation de l'étape CNVkit."
            return 1
        fi
    fi
    
    # === À ce point, cnv_bam est forcément défini et valide ===
    echo " Fichier BAM CNV utilisé : $cnv_bam"
    

    # 2. Demande d’un fichier BED facultatif pour cibler certaines régions
    read -p "Souhaitez-vous fournir un fichier BED pour des régions spécifiques ? (o/N) : " answer
    if [[ "$answer" == "o" || "$answer" == "O" ]]; then
        read -p "Chemin du fichier BED : " bed_file
        if [[ ! -f "$bed_file" ]]; then
            echo "Fichier BED introuvable : $bed_file"
            return
        fi
    else
        bed_file=""
    fi

    mkdir -p logs

   jobid=$(sbatch $dep_opt --partition="$partition" --cpus-per-task="$threads" --mem=256G \
        --output="logs/step4_cnvkit_%j.out" \
        sbatch/step4_cnvkit.sbatch "$sample_name" "$reference" "$threads" "$bed_file" "$cnv_bam" | awk '{print $4}')
    
    if [[ -n "$jobid" ]]; then
        echo "Job SLURM soumis avec succès"
        echo "   ➤ Job ID : $jobid"
        echo "   ➤ Log : logs/step4_cnvkit_${jobid}.out"
        echo "   ➤ Résultats attendus : results/$sample_name/cnvkit/"
        return 0
    else
        echo "Erreur lors de la soumission du job SLURM"
        return 1
    fi

}


function run_methylation() {
    load_user_config
    local dependency=$1
    local dep_opt=""
    [[ -n "$dependency" ]] && dep_opt="--dependency=afterok:$dependency"
    

    echo " Étape 5 - Méthylation (MethylArtist - segmeth + segplot uniquement)"

    # 1. Demande du BAM annoté (obligatoire)
    read -p "Chemin du fichier BAM modifié (annoté avec modkit) : " modified_bam
    if [[ ! -f "$modified_bam" ]]; then
        echo "Le fichier BAM spécifié n'existe pas : $modified_bam"
        return
    fi

    # 2. Demande du fichier BED (obligatoire)
    read -p "Chemin du fichier de régions (BED ou nom_chr:start-end) : " region_file
    if [[ ! -f "$region_file" ]]; then
        echo "Le fichier de régions n'existe pas : $region_file"
        return
    fi

    # 3. Soumission SLURM
    mkdir -p logs
    echo " Soumission SLURM pour l'étape Méthylation..."

    sbatch $dep_opt --partition="$partition" --cpus-per-task="$threads" --mem=256G \
        --output="logs/step5_methylation_%j.out" \
        sbatch/step5_methylation.sbatch "$sample_name" "$reference" "$threads" "$region_file" "$modified_bam"
}


function run_qc() {
    load_user_config
    local dependency=$1
    local dep_opt=""
    [[ -n "$dependency" ]] && dep_opt="--dependency=afterok:$dependency"


    expected_bam="results/${sample_name}/mapping/${sample_name}.bam"

	if [[ "$bam_file" != "$expected_bam" || ! -f "$bam_file" ]]; then
    	echo ""
    	echo "  Aucun fichier BAM correspondant à l’échantillon actuel ($sample_name) n’a été trouvé."
    	echo "   ➤ BAM attendu : $expected_bam"
    	read -p "Souhaitez-vous entrer un chemin BAM  ? (o/N) : " answer
    	if [[ "$answer" == "o" || "$answer" == "O" ]]; then
        	read -p "Chemin du fichier BAM : " bam_file
        	if [[ ! -f "$bam_file" ]]; then
            	echo " Fichier introuvable : $bam_file"
            	return
        	fi
        	# Mise à jour propre du fichier de config
        	sed -i '/^bam_file=/d' "$CONFIG_FILE"
        	echo "bam_file=$bam_file" >> "$CONFIG_FILE"
    	else
        	echo " Annulation de l'étape SNPs."
        	return
    	fi
	else
    	echo " BAM détecté : $bam_file"
	fi

    read -p "Souhaitez-vous fournir un fichier BED pour la couverture ? (o/N) : " answer
    if [[ "$answer" == "o" || "$answer" == "O" ]]; then
        read -p "Chemin du fichier BED : " bed_file
        if [[ ! -f "$bed_file" ]]; then
            echo "Fichier BED introuvable : $bed_file"
            bed_file=""
        fi
    else
        bed_file=""
    fi


    echo " Soumission SLURM de l'étape QC..."
    sbatch $dep_opt --partition="$partition" --cpus-per-task="$threads" --mem=256G \
        --output="logs/step6_qc_%j.out" \
        sbatch/step6_qc.sbatch "$sample_name" "$bam_file" "$threads" "$reference" "$bed_file"
}



# === MAIN ===
load_user_config

while true; do
    show_menu
    case $choice in
        0) reset_config ;;
        1)
                   # Étape 1 : demande du FASTQ
             read -p "Chemin du fichier FASTQ ou dossier FASTQ à aligner (dossier si fusion désirée): " fastq_input
            if [[ ! -e "$fastq_input" ]]; then
                echo "[ERREUR] Fichier ou dossier FASTQ introuvable : $fastq_input"
                continue  # Retour au menu au lieu de break
            fi

            # Collecte des fichiers FASTQ (logique identique à run_alignment)
            fastq_files_list=()
            if [[ -d "$fastq_input" ]]; then
                echo " Dossier détecté : $fastq_input"
                for f in "$fastq_input"/*.fastq "$fastq_input"/*.fastq.gz; do
                    [[ -f "$f" ]] && fastq_files_list+=("$f")
                done
            elif [[ -f "$fastq_input" ]]; then
                echo "📄 Fichier détecté : $fastq_input"
                fastq_files_list+=("$fastq_input")
            else
                echo "[ERREUR] Le chemin spécifié n'est ni un fichier ni un dossier valide"
                continue
            fi

            if [[ ${#fastq_files_list[@]} -eq 0 ]]; then
                echo "[ERREUR] Aucun fichier FASTQ détecté dans : $fastq_input"
                continue
            fi
        
        
            # BED optionnel
           read -p "Souhaitez-vous fournir un fichier BED pour restreindre les régions ? (o/N) : " use_bed
            if [[ "$use_bed" == "o" || "$use_bed" == "O" ]]; then
                read -p "Chemin du fichier BED : " bed_file
                if [[ ! -f "$bed_file" ]]; then
                    echo "  Fichier BED introuvable : $bed_file"
                    echo " Continuation sans fichier BED"
                    bed_file=""
                else
                    echo "Fichier BED valide : $bed_file"
                fi
            else
                bed_file=""
            fi
        
        
            # Phasage
         read -p "Souhaitez-vous effectuer le phasage avec WhatsHap ? (o/N) : " phasing_answer
            if [[ "$phasing_answer" == "o" || "$phasing_answer" == "O" ]]; then
                do_phasing="yes"
                echo "🔬 Phasage activé"
            else
                do_phasing="no"
                echo "  Phasage désactivé"
            fi
        
        
            mkdir -p logs results/"$sample_name"
            CONFIG_FILE="results/$sample_name/config_${sample_name}.txt"
            expected_bam="results/${sample_name}/mapping/${sample_name}.bam"
        
        
            echo "sample_name=$sample_name" > "$CONFIG_FILE"
            echo "reference=$reference" >> "$CONFIG_FILE"
            echo "partition=$partition" >> "$CONFIG_FILE"
            echo "threads=$threads" >> "$CONFIG_FILE"
            echo "bed_file=$bed_file" >> "$CONFIG_FILE"
            echo "do_phasing=$do_phasing" >> "$CONFIG_FILE"
            echo "bam_file=$expected_bam" >> "$CONFIG_FILE"
             # Enregistrement des FASTQ dans la config
            if [[ -d "$fastq_input" ]]; then
                echo "fastq_dir=$fastq_input" >> "$CONFIG_FILE"
            else
                echo "fastq_files=${fastq_files_list[*]}" >> "$CONFIG_FILE"
            fi

            echo ""
            echo "📋 Résumé de la configuration :"
            echo "   ➤ Échantillon    : $sample_name"
            echo "   ➤ FASTQ          : $fastq_input"
            echo "   ➤ Nb fichiers    : ${#fastq_files_list[@]}"
            echo "   ➤ Référence      : $reference"
            echo "   ➤ BED            : ${bed_file:-'aucun'}"
            echo "   ➤ Phasage        : $do_phasing"
            echo "   ➤ BAM attendu    : $expected_bam"
            echo "   ➤ Config         : $CONFIG_FILE"
            echo ""
            
        
            # Étape 1 : alignement
                       echo "Soumission de l'étape Alignement..."
            jobid_align=$(sbatch --partition="$partition" --cpus-per-task="$threads" --mem=128G \
                --output="logs/step1_align_%j.out" \
                sbatch/step1_align.sbatch "$sample_name" "$threads" "$fastq_input" "$reference" | awk '{print $4}')
        
            if [[ -z "$jobid_align" ]]; then
                echo "Erreur lors de la soumission de l'alignement"
                continue
            fi
            echo "Alignement soumis - Job ID : $jobid_align"
            echo " BAM attendu : $expected_bam"
        
        
            # # On suppose que le script écrit bam_file=... dans le config
            # sleep 2
            # if [[ -f "$CONFIG_FILE" ]]; then
            #     source "$CONFIG_FILE"
            # fi
        
        
            # if [[ ! -f "$bam_file" ]]; then
            #     echo "[  ATTENTION] Le fichier BAM n'existe pas encore : $bam_file"
            #     echo "Les étapes suivantes dépendent de la complétion du job SLURM précédent."
            # fi

            # Étape 2 : SNPs
            echo "Soumission de l'étape SNPs (dépend de l'alignement)..."
            jobid_snps=$(sbatch --dependency=afterok:$jobid_align --partition="$partition" --cpus-per-task="$threads" --mem=256G \
            --output="logs/step2_snps_%j.out" \
            sbatch/step2_snps.sbatch "$sample_name" "$expected_bam" "$reference" "$threads" "$bed_file" "$do_phasing" | awk '{print $4}')

            # Étape 3 : SVs
            echo "Soumission de l'étape SVs (dépend de l'alignement)..."
            jobid_svs=$(sbatch --dependency=afterok:$jobid_align --partition="$partition" --cpus-per-task="$threads" --mem=256G \
            --output="logs/step3_svs_%j.out" \
            sbatch/step3_svs.sbatch "$sample_name" "$expected_bam" "$reference" "$threads" "$bed_file" | awk '{print $4}')

            # Étape 4 : CNVkit (dépend de SVs)
            echo "Soumission de l'étape CNVkit (dépend de SVs)..."
            jobid_cnv=$(sbatch --dependency=afterok:$jobid_svs --partition="$partition" --cpus-per-task="$threads" --mem=256G \
            --output="logs/step4_cnvkit_%j.out" \
            sbatch/step4_cnvkit.sbatch "$sample_name" "$reference" "$threads" "$bed_file" "$expected_bam" | awk '{print $4}')

            # # Étape 5 : Méthylation (interactif)
            # echo "Étape Méthylation (après CNV)..."
            # run_methylation

            # Étape 6 : Q_score
            echo "Soumission de l'étape QC (dépend de l'alignement)..."
            jobid_qc=$(sbatch --dependency=afterok:$jobid_align --partition="$partition" --cpus-per-task="$threads" --mem=256G \
            --output="logs/step6_qc_%j.out" \
            sbatch/step6_qc.sbatch "$sample_name" "$expected_bam" "$threads" "$reference" "$bed_file" | awk '{print $4}')

            # Étape 7 : Annotation (VEP + Annovar)
            echo "Soumission de l'étape Annotation (dépend de SNPs)..."
            expected_vcf="results/${sample_name}/snps_clair3/merge_output.vcf.gz"
            jobid_annotation=$(sbatch --dependency=afterok:$jobid_snps --partition="$partition" --cpus-per-task="$threads" --mem=256G \
            --output="logs/step6_annotation_%j.out" \
            sbatch/step7_annotation.sbatch "$sample_name" "$expected_vcf" "$threads" "$reference" | awk '{print $4}')

            echo ""
            echo " Pipeline complet soumis avec dépendances."
            echo " Résumé des jobs :"
            echo "   ➤ Alignement : $jobid_align"
            echo "   ➤ SNPs       : $jobid_snps (dépend de $jobid_align)"
            echo "   ➤ SVs        : $jobid_svs (dépend de $jobid_align)"
            echo "   ➤ CNVkit     : $jobid_cnv (dépend de $jobid_align)"
            echo "   ➤ QC         : $jobid_qc (dépend de $jobid_align)"
            echo "   ➤ Annotation : $jobid_annotation (dépend de $jobid_snps)"
            echo ""
            echo " Note : L'étape Méthylation nécessite une intervention manuelle"
            echo "   Utilisez l'option 2 pour la lancer après que l'alignement soit terminé"
            ;;
        2) choose_steps ;;
        3) echo " Explication des étapes (à venir)" ;;
        4) echo " Au revoir !" ; exit 0 ;;
        *) echo "Choix invalide, veuillez réessayer." ;;
    esac
done