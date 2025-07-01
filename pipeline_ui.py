import streamlit as st
import os
import subprocess
import json
from pathlib import Path
from datetime import datetime

# Définit ici le dossier de base contenant les FASTQ
base_folder_fastq = "/scratch/dkdiakite/data/archives/test_pipline/fastq_pass"
def list_files(base_path, extensions=None):
    """Liste tous les fichiers dans un dossier avec les extensions spécifiées"""
    files_list = []
    if not os.path.exists(base_path):
        st.warning(f"Le dossier {base_path} n'existe pas.")
        return files_list
        
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if extensions:
                if any(file.endswith(ext) for ext in extensions):
                    files_list.append(os.path.relpath(os.path.join(root, file), base_path))
            else:
                files_list.append(os.path.relpath(os.path.join(root, file), base_path))
    return sorted(files_list)
# Configuration de la page
st.set_page_config(
    page_title="Pipeline Nanopore - UPJV",
    page_icon="🧬",
    layout="wide",
    initial_sidebar_state="expanded"
)

st.title("🧬 Pipeline de détection de variants Nanopore - UPJV")

# Sidebar pour la configuration
st.sidebar.header("Configuration")

# Variables de session pour maintenir l'état
if 'sample_name' not in st.session_state:
    st.session_state.sample_name = ""
if 'config_loaded' not in st.session_state:
    st.session_state.config_loaded = False

# Fonction pour charger la configuration
def load_config(sample_name):
    config_file = f"results/{sample_name}/config_{sample_name}.txt"
    config = {}
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            for line in f:
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    config[key] = value
    return config

# Fonction pour sauvegarder la configuration
def save_config(sample_name, config):
    result_dir = f"results/{sample_name}"
    os.makedirs(result_dir, exist_ok=True)
    config_file = f"{result_dir}/config_{sample_name}.txt"
    
    with open(config_file, 'w') as f:
        for key, value in config.items():
            f.write(f"{key}={value}\n")

def run_pipeline_command(command):
    """Exécute une commande bash de manière sécurisée avec gestion des erreurs."""
    import shlex
    try:
        if isinstance(command, str):
            cmd_list = shlex.split(command)
        else:
            cmd_list = command


        process = subprocess.run(
            cmd_list,
            capture_output=True,
            text=True,
            timeout=600,
            env=os.environ.copy(),
            cwd=os.getcwd()
        )
        return process.returncode, process.stdout, process.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Timeout: La commande a dépassé le temps limite"
    except FileNotFoundError as e:
        return -1, "", f"Fichier ou commande introuvable: {str(e)}"
    except Exception as e:
        return -1, "", f"Erreur inconnue: {str(e)}"




def display_debug_info(returncode, stdout, stderr, command):
    """Affiche le résultat de la commande avec détails."""
    if returncode == 0:
        st.success(f"✅ Commande exécutée avec succès (code: {returncode})")
    else:
        st.error(f"❌ Erreur d'exécution (code: {returncode})")


    with st.expander("🔍 Commande exécutée"):
        st.code(" ".join(command) if isinstance(command, list) else command, language="bash")


    if stdout:
        with st.expander("📤 Sortie Standard (stdout)"):
            st.text_area("Sortie", stdout, height=200)


    if stderr:
        with st.expander("❌ Erreurs (stderr)"):
            st.text_area("Erreurs", stderr, height=200)




def save_debug_log(sample_name, command, returncode, stdout, stderr):
    """Sauvegarde les logs dans le dossier logs/"""
    os.makedirs("logs", exist_ok=True)
    from datetime import datetime
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_filename = f"debug_{sample_name}_{timestamp}.log"
    log_path = os.path.join("logs", log_filename)
    try:
        with open(log_path, 'w') as f:
            f.write(f"=== DEBUG LOG ===\n")
            f.write(f"Timestamp: {datetime.now()}\n")
            f.write(f"Sample: {sample_name}\n")
            f.write(f"Return Code: {returncode}\n")
            f.write(f"Command: {' '.join(command) if isinstance(command, list) else command}\n\n")
            f.write("=== STDOUT ===\n")
            f.write(stdout or "Aucune sortie\n")
            f.write("\n=== STDERR ===\n")
            f.write(stderr or "Aucune erreur\n")
        st.info(f"📁 Log sauvegardé dans {log_path}")
    except Exception as e:
        st.error(f"❌ Erreur lors de la sauvegarde du log: {str(e)}")

# Configuration de base

# with st.sidebar:
#     # Onglets pour nouvel échantillon ou modifier existant
#     tab_config1, tab_config2 = st.tabs(["➕ Nouvel échantillon", "📝 Modifier existant"])
    
#     with tab_config1:
#         st.markdown("**Créer un nouvel échantillon**")
        
#         # Nom de l'échantillon
#         sample_name = st.text_input(
#             "Nom de l'échantillon",
#             value="",
#             placeholder="Entrez le nom du nouvel échantillon",
#             key="new_sample"
#         )
    
#     with tab_config2:
#         st.markdown("**Modifier un échantillon existant**")
        
#         # Liste des échantillons existants
#         existing_samples = []
#         results_dir = "results"
#         if os.path.exists(results_dir):
#             for item in os.listdir(results_dir):
#                 sample_dir = os.path.join(results_dir, item)
#                 if os.path.isdir(sample_dir):
#                     config_file = os.path.join(sample_dir, f"config_{item}.txt")
#                     if os.path.exists(config_file):
#                         existing_samples.append(item)
        
#         if existing_samples:
#             selected_sample = st.selectbox(
#                 "Sélectionner un échantillon",
#                 [""] + existing_samples,
#                 help="Choisissez un échantillon existant à modifier"
#             )
            
#             if selected_sample:
#                 sample_name = selected_sample
#                 # Charger la configuration existante
#                 config = load_config(sample_name)
#                 if config:
#                     st.success(f"Configuration chargée pour {sample_name}")
#                     st.session_state.config_loaded = True
#                     # Pré-remplir les valeurs si disponibles dans la config
#                     if 'reference' in config:
#                         st.session_state.loaded_reference = config['reference']
#                     if 'partition' in config:
#                         st.session_state.loaded_partition = config['partition']
#                     if 'threads' in config:
#                         st.session_state.loaded_threads = int(config['threads'])
#                 else:
#                     st.session_state.config_loaded = False
#             else:
#                 sample_name = ""
#         else:
#             st.info("Aucun échantillon existant trouvé")
#             sample_name = ""
    
#     # Mettre à jour l'état de session
#     if sample_name and sample_name != st.session_state.get('sample_name', ''):
#         st.session_state.sample_name = sample_name

#     # Paramètres de configuration
#     # Fichier de référence
#     reference = st.text_input(
#         "Fichier de référence", 
#         value=st.session_state.get('loaded_reference', "/users/dkdiakite/mes_jobs/input/hg38.fa"),
#         help="Chemin vers le génome de référence"
#     )
    
#     # Partition SLURM
#     partition = st.text_input(
#         "Partition SLURM", 
#         value=st.session_state.get('loaded_partition', "bigmem,bigmem-amd"),
#         help="Partitions SLURM disponibles"
#     )
    
#     # Nombre de threads avec contrôles + et -
#     st.markdown("**Nombre de threads**")
#     col_minus, col_input, col_plus = st.columns([1, 2, 1])
    
#     # Initialiser la valeur des threads
#     if 'threads_value' not in st.session_state:
#         st.session_state.threads_value = st.session_state.get('loaded_threads', 16)
    
#     with col_minus:
#         if st.button("➖", key="minus_threads", help="Diminuer"):
#             if st.session_state.threads_value > 1:
#                 st.session_state.threads_value -= 1
#                 st.rerun()
    
#     with col_input:
#         threads = st.number_input(
#             "threads",
#             min_value=1,
#             max_value=64,
#             value=st.session_state.threads_value,
#             label_visibility="collapsed"
#         )
#         st.session_state.threads_value = threads
    
#     with col_plus:
#         if st.button("➕", key="plus_threads", help="Augmenter"):
#             if st.session_state.threads_value < 64:
#                 st.session_state.threads_value += 1
#                 st.rerun()

# with st.sidebar:
#     # Onglets pour nouvel échantillon ou modifier existant
#     tab_config1, tab_config2 = st.tabs(["➕ Nouvel échantillon", "📝 Modifier existant"])
    
#     # Initialiser sample_name dans session_state si pas présent
#     if 'sample_name' not in st.session_state:
#         st.session_state.sample_name = ""
    
#     with tab_config1:
#         st.markdown("**Créer un nouvel échantillon**")
        
#         # Nom de l'échantillon avec callback
#         sample_name_input = st.text_input(
#             "Nom de l'échantillon",
#             value=st.session_state.sample_name if st.session_state.get('current_tab') == 'new' else "",
#             placeholder="Entrez le nom du nouvel échantillon",
#             key="new_sample"
#         )
        
#         # Mettre à jour l'état si changement détecté
#         if sample_name_input != st.session_state.sample_name:
#             st.session_state.sample_name = sample_name_input
#             st.session_state.current_tab = 'new'
#             st.session_state.config_loaded = False  # Reset config chargée
#             # Nettoyer les valeurs chargées
#             if 'loaded_reference' in st.session_state:
#                 del st.session_state.loaded_reference
#             if 'loaded_partition' in st.session_state:
#                 del st.session_state.loaded_partition
#             if 'loaded_threads' in st.session_state:
#                 del st.session_state.loaded_threads
#             st.rerun()  # Forcer le rafraîchissement
    
#     with tab_config2:
#         st.markdown("**Modifier un échantillon existant**")
        
#         # Liste des échantillons existants
#         existing_samples = []
#         results_dir = "results"
#         if os.path.exists(results_dir):
#             for item in os.listdir(results_dir):
#                 sample_dir = os.path.join(results_dir, item)
#                 if os.path.isdir(sample_dir):
#                     config_file = os.path.join(sample_dir, f"config_{item}.txt")
#                     if os.path.exists(config_file):
#                         existing_samples.append(item)
        
#         if existing_samples:
#             # Déterminer l'index par défaut pour la selectbox
#             default_index = 0
#             if st.session_state.get('current_tab') == 'modify' and st.session_state.sample_name in existing_samples:
#                 default_index = existing_samples.index(st.session_state.sample_name) + 1
            
#             selected_sample = st.selectbox(
#                 "Sélectionner un échantillon",
#                 [""] + existing_samples,
#                 help="Choisissez un échantillon existant à modifier",
#                 index=default_index
#             )
            
#             if selected_sample:
#                 # Mettre à jour seulement si c'est différent
#                 if selected_sample != st.session_state.sample_name:
#                     st.session_state.sample_name = selected_sample
#                     st.session_state.current_tab = 'modify'
#                     # Charger la configuration existante
#                     config = load_config(selected_sample)
#                     if config:
#                         st.success(f"Configuration chargée pour {selected_sample}")
#                         st.session_state.config_loaded = True
#                         # Pré-remplir les valeurs si disponibles dans la config
#                         if 'reference' in config:
#                             st.session_state.loaded_reference = config['reference']
#                         if 'partition' in config:
#                             st.session_state.loaded_partition = config['partition']
#                         if 'threads' in config:
#                             st.session_state.loaded_threads = int(config['threads'])
#                         if 'fastq_input' in config:
#                             st.session_state.loaded_fastq = config['fastq_input']
#                         st.rerun()  # Forcer le rafraîchissement
#                     else:
#                         st.session_state.config_loaded = False
#                 elif st.session_state.get('current_tab') == 'modify':
#                     # Si c'est le même échantillon et qu'on est déjà en mode modify, afficher le statut
#                     if st.session_state.get('config_loaded'):
#                         st.success(f"Configuration chargée pour {selected_sample}")
#             else:
#                 # Si rien n'est sélectionné, vider le nom d'échantillon uniquement si on était en mode modify
#                 if st.session_state.get('current_tab') == 'modify':
#                     st.session_state.sample_name = ""
#                     st.session_state.config_loaded = False
#                     # Nettoyer les valeurs chargées
#                     for key in ['loaded_reference', 'loaded_partition', 'loaded_threads', 'loaded_fastq']:
#                         if key in st.session_state:
#                             del st.session_state[key]
#         else:
#             st.info("Aucun échantillon existant trouvé")
#             if st.session_state.get('current_tab') == 'modify':
#                 st.session_state.sample_name = ""
#                 st.session_state.config_loaded = False

#     # Récupérer le nom d'échantillon final
#     sample_name = st.session_state.sample_name

#     # Paramètres de configuration
#     # Fichier de référence
#     reference = st.text_input(
#         "Fichier de référence", 
#         value=st.session_state.get('loaded_reference', "/users/dkdiakite/mes_jobs/input/hg38.fa"),
#         help="Chemin vers le génome de référence"
#     )
    
#     # Partition SLURM
#     partition = st.text_input(
#         "Partition SLURM", 
#         value=st.session_state.get('loaded_partition', "bigmem,bigmem-amd"),
#         help="Partitions SLURM disponibles"
#     )
    
#     # Nombre de threads avec contrôles + et -
#     st.markdown("**Nombre de threads**")
#     col_minus, col_input, col_plus = st.columns([1, 2, 1])
    
#     # Initialiser la valeur des threads
#     if 'threads_value' not in st.session_state:
#         st.session_state.threads_value = st.session_state.get('loaded_threads', 16)
    
#     with col_minus:
#         if st.button("➖", key="minus_threads", help="Diminuer"):
#             if st.session_state.threads_value > 1:
#                 st.session_state.threads_value -= 1
#                 st.rerun()
    
#     with col_input:
#         threads = st.number_input(
#             "threads",
#             min_value=1,
#             max_value=64,
#             value=st.session_state.threads_value,
#             label_visibility="collapsed"
#         )
#         st.session_state.threads_value = threads
    
#     with col_plus:
#         if st.button("➕", key="plus_threads", help="Augmenter"):
#             if st.session_state.threads_value < 64:
#                 st.session_state.threads_value += 1
#                 st.rerun()               

# with st.sidebar:
#     tab_new, tab_modify = st.tabs(["➕ Nouvel échantillon", "📝 Modifier existant"])


#     if 'current_tab' not in st.session_state:
#         st.session_state.current_tab = 'new'
#     if 'sample_name' not in st.session_state:
#         st.session_state.sample_name = ""


#     with tab_new:
#         st.markdown("**Créer un nouvel échantillon**")
#         new_sample = st.text_input(
#             "Nom de l'échantillon",
#             value=st.session_state.sample_name if st.session_state.current_tab == 'new' else "",
#             key="new_sample_input",
#             placeholder="Entrez le nom du nouvel échantillon"
#         )


#         if new_sample != st.session_state.sample_name:
#             st.session_state.sample_name = new_sample
#             st.session_state.current_tab = 'new'
#             st.session_state.config_loaded = False
#             for key in ['loaded_reference', 'loaded_partition', 'loaded_threads', 'loaded_fastq']:
#                 st.session_state.pop(key, None)


#     with tab_modify:
#         st.markdown("**Modifier un échantillon existant**")


#         results_dir = "results"
#         existing_samples = []
#         if os.path.exists(results_dir):
#             existing_samples = [
#                 item for item in os.listdir(results_dir)
#                 if os.path.isdir(os.path.join(results_dir, item))
#                 and os.path.exists(os.path.join(results_dir, item, f"config_{item}.txt"))
#             ]


#         if existing_samples:
#             default_index = 0
#             if st.session_state.current_tab == 'modify' and st.session_state.sample_name in existing_samples:
#                 default_index = existing_samples.index(st.session_state.sample_name) + 1


#             selected_sample = st.selectbox(
#                 "Sélectionner un échantillon",
#                 [""] + existing_samples,
#                 index=default_index
#             )


#             if selected_sample:
#                 if selected_sample != st.session_state.sample_name or st.session_state.current_tab != 'modify':
#                     st.session_state.sample_name = selected_sample
#                     st.session_state.current_tab = 'modify'
#                     config = load_config(selected_sample)
#                     if config:
#                         st.session_state.loaded_reference = config.get('reference', '')
#                         st.session_state.loaded_partition = config.get('partition', '')
#                         st.session_state.loaded_threads = config.get('threads', 16)
#                         st.session_state.loaded_fastq = config.get('fastq_input', '')
#                         st.session_state.config_loaded = True
#                         st.success(f"Configuration chargée pour {selected_sample}")
#                     else:
#                         st.warning("Fichier de configuration non trouvé")
#                         st.session_state.config_loaded = False
#             else:
#                 if st.session_state.current_tab == 'modify':
#                     st.session_state.sample_name = ""
#                     st.session_state.config_loaded = False
#                     for key in ['loaded_reference', 'loaded_partition', 'loaded_threads', 'loaded_fastq']:
#                         st.session_state.pop(key, None)
#         else:
#             st.info("Aucun échantillon existant trouvé")
#             if st.session_state.current_tab == 'modify':
#                 st.session_state.sample_name = ""
#                 st.session_state.config_loaded = False


#     # ------------------------------
#     # Paramètres partagés
#     # ------------------------------
#     sample_name = st.session_state.sample_name


#     st.markdown(f"### Échantillon sélectionné : `{sample_name}`")


#     reference = st.text_input(
#         "Fichier de référence",
#         value=st.session_state.get('loaded_reference', "/users/dkdiakite/mes_jobs/input/hg38.fa"),
#         help="Chemin vers le génome de référence"
#     )


#     partition = st.text_input(
#         "Partition SLURM",
#         value=st.session_state.get('loaded_partition', "bigmem,bigmem-amd"),
#         help="Partitions SLURM disponibles"
#     )


#     st.markdown("**Nombre de threads**")
#     col_minus, col_input, col_plus = st.columns([1, 2, 1])


#     if 'threads_value' not in st.session_state:
#         st.session_state.threads_value = st.session_state.get('loaded_threads', 16)


#     with col_minus:
#         if st.button("➖", key="minus_threads"):
#             if st.session_state.threads_value > 1:
#                 st.session_state.threads_value -= 1


#     with col_input:
#         threads = st.number_input(
#             "threads",
#             min_value=1,
#             max_value=64,
#             value=st.session_state.threads_value,
#             label_visibility="collapsed"
#         )
#         st.session_state.threads_value = threads


#     with col_plus:
#         if st.button("➕", key="plus_threads"):
#             if st.session_state.threads_value < 64:
#                 st.session_state.threads_value += 1

with st.sidebar:

    # Choix entre créer un nouvel échantillon ou modifier un existant
    choix = st.radio(
        "Sélectionnez le mode :",
        ["➕ Nouvel échantillon", "📝 Modifier existant"],
        key="mode_selection"
    )


    # Initialiser sample_name si absent
    if 'sample_name' not in st.session_state:
        st.session_state.sample_name = ""


    # 🆕 Mode : Nouvel échantillon
    if choix == "➕ Nouvel échantillon":
        st.markdown("**Créer un nouvel échantillon**")


        new_sample = st.text_input(
            "Nom de l'échantillon",
            # value=st.session_state.sample_name if st.session_state.get('mode_selection_previous') == "➕ Nouvel échantillon" else "",
            key="new_sample_input",
            placeholder="Entrez le nom du nouvel échantillon"
        )


        if new_sample != st.session_state.sample_name:
            st.session_state.sample_name = new_sample
            st.session_state.config_loaded = False
            for key in ['loaded_reference', 'loaded_partition', 'loaded_threads', 'loaded_fastq']:
                st.session_state.pop(key, None)
            

    # 📝 Mode : Modifier un échantillon existant
    elif choix == "📝 Modifier existant":
        st.markdown("**Modifier un échantillon existant**")


        results_dir = "results"
        existing_samples = []


        if os.path.exists(results_dir):
            existing_samples = [
                item for item in os.listdir(results_dir)
                if os.path.isdir(os.path.join(results_dir, item))
                and os.path.exists(os.path.join(results_dir, item, f"config_{item}.txt"))
            ]


        if existing_samples:
            # default_index = 0
            # if (
            #     st.session_state.sample_name in existing_samples and
            #     st.session_state.get('mode_selection_previous') == "📝 Modifier existant"
            # ):
            #     default_index = existing_samples.index(st.session_state.sample_name) + 1


            # selected_sample = st.selectbox(
            #     "Sélectionner un échantillon",
            #     [""] + existing_samples,
            #     index=default_index
            # )
            selected_sample = st.selectbox(
                "Sélectionner un échantillon",
                [""] + existing_samples,
                index=0,
                key="select_existing_sample"
            )

            if selected_sample:
                if selected_sample != st.session_state.sample_name:
                    st.session_state.sample_name = selected_sample
                    config = load_config(selected_sample)  # ⚠️ Adapter à ta fonction
                    if config:
                        st.session_state.loaded_reference = config.get('reference', '')
                        st.session_state.loaded_partition = config.get('partition', '')
                        st.session_state.loaded_threads = int(config.get('threads', 16))
                        st.session_state.loaded_fastq = config.get('fastq_input', '')
                        st.session_state.threads_value = int(config.get('threads', 16))
                        st.session_state.config_loaded = True
                        st.success(f"Configuration chargée pour {selected_sample}")
                    else:
                        st.warning("Fichier de configuration non trouvé")
                        st.session_state.config_loaded = False
            else:
                st.session_state.sample_name = ""
                st.session_state.config_loaded = False
                for key in ['loaded_reference', 'loaded_partition', 'loaded_threads', 'loaded_fastq']:
                    st.session_state.pop(key, None)
        else:
            st.info("Aucun échantillon existant trouvé")
            st.session_state.sample_name = ""
            st.session_state.config_loaded = False


    # 🔄 Sauvegarder l'état précédent (permet de gérer le changement de mode)
    st.session_state.mode_selection_previous = choix

    # ------------------------------
    # ⚙️ Paramètres partagés
    # ------------------------------
    sample_name = st.session_state.sample_name


    st.markdown(f"### Échantillon sélectionné : `{sample_name}`")


    reference = st.text_input(
        "Fichier de référence",
        value=st.session_state.get('loaded_reference', "/users/dkdiakite/mes_jobs/input/hg38.fa"),
        help="Chemin vers le génome de référence"
    )


    partition = st.text_input(
        "Partition SLURM",
        value=st.session_state.get('loaded_partition', "bigmem,bigmem-amd"),
        help="Partitions SLURM disponibles"
    )


    st.markdown("**Nombre de threads**")
    col_minus, col_input, col_plus = st.columns([1, 2, 1])


    if 'threads_value' not in st.session_state:
        st.session_state.threads_value = int(st.session_state.get('loaded_threads', 16))


    with col_minus:
        if st.button("➖", key="minus_threads"):
            if st.session_state.threads_value > 1:
                st.session_state.threads_value -= 1


    with col_input:
        threads = st.number_input(
            "threads",
            min_value=1,
            max_value=64,
            value=st.session_state.threads_value,
            label_visibility="collapsed"
        )
        st.session_state.threads_value = threads


    with col_plus:
        if st.button("➕", key="plus_threads"):
            if st.session_state.threads_value < 64:
                st.session_state.threads_value += 1


# Onglets principaux
tab1, tab2, tab3, tab4 = st.tabs(["🚀 Pipeline Complet", "⚙️ Étapes Manuelles", "📊 Monitoring", "📈 Résultats et Suivi"])

with tab1:
    st.header("Lancement du Pipeline Complet")
    
    if not sample_name:
        st.warning("Veuillez d'abord spécifier un nom d'échantillon dans la sidebar")
    else:
        # Chargement des fichiers FASTQ
        with st.spinner("Chargement des fichiers FASTQ..."):
            fastq_files = list_files(base_folder_fastq, extensions=[".fastq", ".fastq.gz"])
    
            if not fastq_files:
                st.error(f"Aucun fichier FASTQ trouvé dans {base_folder_fastq}")
                st.stop()
        
        # Layout principal en deux colonnes
        col_files, col_options = st.columns([3, 2])
        
        # COLONNE GAUCHE - Fichiers d'entrée
        with col_files:
            st.subheader("📁 Fichiers d'entrée")
            
            # Informations sur le dossier source
            #st.info(f"📂 **Dossier source:** `{base_folder_fastq}`")
            #st.info(f"📊 **{len(fastq_files)} fichiers FASTQ** détectés")
            
            # Checkbox pour tout sélectionner
            select_all = st.checkbox(
                "🔄 Tout sélectionner", 
                help="Sélectionner tous les fichiers FASTQ disponibles"
            )
            
            # Logique de sélection
            if select_all:
                fastq_to_pass = base_folder_fastq
                selected_fastq_rel_list = fastq_files
                is_folder = True
                
                st.success(f"✅ Tous les fichiers sélectionnés ({len(fastq_files)} fichiers)")
                #st.text_input(
                #    "Chemin(s) FASTQ sélectionné(s) :", 
                #    value=fastq_to_pass, 
                 #   disabled=True,
                 #   key="fastq_path_all"
                #)
                
            else:
                # Gestion de la configuration chargée
                default_selection = []
                if st.session_state.get("config_loaded") and st.session_state.get("loaded_fastq"):
                    loaded_files = st.session_state["loaded_fastq"].split(",")
                    default_selection = [
                        os.path.relpath(f, base_folder_fastq) 
                        for f in loaded_files
                        if f.startswith(base_folder_fastq) and 
                           os.path.relpath(f, base_folder_fastq) in fastq_files
                    ]
                   
                selected_fastq_rel_list = st.multiselect(
                    "🎯 Choisissez un ou plusieurs fichiers FASTQ à aligner :",
                    fastq_files,
                    default=default_selection,
                    help="Utilisez Ctrl+clic pour sélectionner plusieurs fichiers"
                )
               
                if selected_fastq_rel_list:
                    fastq_paths = [os.path.join(base_folder_fastq, f) for f in selected_fastq_rel_list]
                    fastq_to_pass = ",".join(fastq_paths)
                    is_folder = False
                    
                    st.success(f"✅ {len(selected_fastq_rel_list)} fichier(s) sélectionné(s)")
                    # st.text_area(
                    #     "Chemin(s) FASTQ sélectionné(s) :", 
                    #     value=fastq_to_pass, 
                    #     disabled=True, 
                    #     height=120,
                    #     key="fastq_path_selected"
                    # )
                else:
                    st.warning("⚠️ Veuillez sélectionner au moins un fichier FASTQ")
                    fastq_to_pass = None
        
        # COLONNE DROITE - Options
        with col_options:
            st.subheader("⚙️ Options du pipeline")


                        # Dossier dédié pour les fichiers BED par échantillon
            bed_folder = f"results/{sample_name}/bed_files"
            os.makedirs(bed_folder, exist_ok=True)
            
            # Uploader un fichier BED
            uploaded_bed = st.file_uploader("📤 Uploader un fichier BED", type=["bed"])
            
            if uploaded_bed:
                saved_bed_path = os.path.join(bed_folder, uploaded_bed.name)
                with open(saved_bed_path, "wb") as f:
                    f.write(uploaded_bed.getbuffer())
                st.success(f"Fichier BED enregistré sous : {saved_bed_path}")
            
            # Lister tous les fichiers BED déjà présents dans le dossier
            bed_files_in_folder = [
                f for f in os.listdir(bed_folder) if f.endswith(".bed")
            ]
            
            # Choisir le fichier BED à utiliser
            bed_file = None
            if bed_files_in_folder:
                selected_bed = st.selectbox(
                    "📄 Choisir un fichier BED disponible :",
                    options=bed_files_in_folder
                )
                bed_file = os.path.join(bed_folder, selected_bed)
                st.info(f"Fichier BED sélectionné : {bed_file}")
            else:
                st.warning("⚠️ Aucun fichier BED disponible. Veuillez en uploader un.")

            
            do_phasing = st.checkbox(
                "🧬 Effectuer le phasage avec WhatsHap",
                help="Active le phasage des variants détectés"
            )
            
            # Validation du fichier BED
            if bed_file and not os.path.exists(bed_file):
                st.warning(f"⚠️ Fichier BED introuvable")
                
            # Résumé de la configuration
           # st.markdown("---")
           # st.markdown("**📋 Résumé:**")
           # st.write(f"• **Échantillon:** `{sample_name}`")
        #st.write(f"• **Threads:** `{threads}`")
            
            # if fastq_to_pass:
            #     if select_all:
            #         st.write(f"• **Fichiers:** Tous ({len(fastq_files)})")
            #     else:
            #         st.write(f"• **Fichiers:** {len(selected_fastq_rel_list)} sélectionné(s)")
            
            if bed_file and os.path.exists(bed_file):
                st.write(f"• **BED:** ✅ Spécifié")
            
            if do_phasing:
                st.write(f"• **Phasage:** ✅ Activé")
        
        # Validation du fichier BED
        if bed_file and not os.path.exists(bed_file):
            st.warning(f"⚠️ Fichier BED introuvable: {bed_file}")
        
        # Section Lancement
        st.markdown("---")
        #st.subheader("🚀 Lancement")
        
        # Vérifications avant lancement
        can_launch = True
        if not fastq_to_pass:
            can_launch = False
            st.error("❌ Aucun fichier FASTQ sélectionné")
        elif not select_all and not os.path.exists(fastq_to_pass.split(",")[0]):
            can_launch = False
            st.error("❌ Fichier FASTQ introuvable")
        
        # Résumé avant lancement
        if can_launch:
            with st.expander("📋 Résumé de la configuration", expanded=False):
                st.write(f"**Échantillon:** {sample_name}")
                st.write(f"**Référence:** {reference}")
                st.write(f"**Threads:** {threads}")
                st.write(f"**Partition:** {partition}")
                if select_all:
                    st.write(f"**Fichiers:** Tous les fichiers ({len(fastq_files)} fichiers)")
                else:
                    st.write(f"**Fichiers:** {len(selected_fastq_rel_list)} fichier(s) sélectionné(s)")
                if bed_file:
                    st.write(f"**Fichier BED:** {bed_file}")
                if do_phasing:
                    st.write("**Phasage:** Activé")
        
        # Bouton de lancement
        # Remplacez la section de lancement dans tab1 par ce code amélioré :

        # Bouton de lancement
        if st.button("🚀 Lancer le Pipeline Complet", type="primary", disabled=not can_launch):
            config = {
                "sample_name": sample_name,
                "reference": reference,
                "partition": partition,
                "threads": str(threads),
                "fastq_input": fastq_to_pass,
                "bed_file": bed_file if bed_file else "",
                "do_phasing": str(do_phasing)
            }
            save_config(sample_name, config)
            st.success("📁 Configuration sauvegardée avant lancement")
            # Construire la commande
            cmd = [
                "bash", "run_pipeline.sh", "--non-interactive",
                "--sample", sample_name,
                "--reference", reference,
                "--partition", partition,
                "--threads", str(threads),
                "--fastq_input", fastq_to_pass,
                "--option", "1"
            ]
            
            if bed_file and os.path.exists(bed_file):
                cmd.extend(["--bed", bed_file])
            
            if do_phasing:
                cmd.append("--phase")
            
            try:
                with st.spinner("⏳ Soumission du pipeline en cours..."):
                    command_str = " ".join(cmd)
                    returncode, stdout, stderr = run_pipeline_command(command_str)
                
                # 🔍 Affichage détaillé des résultats (comme dans tab2)
                st.markdown("### 🔍 Résultats de l'exécution")
                
                # Affichage de la commande exécutée
                with st.expander("🖥️ Commande exécutée", expanded=False):
                    st.code(command_str, language="bash")
                
                # Affichage des résultats
                col_result1, col_result2 = st.columns(2)
                
                with col_result1:
                    if returncode == 0:
                        st.success("✅ Pipeline soumis avec succès!")
                    else:
                        st.error(f"❌ Erreur lors de la soumission (Code: {returncode})")
                
                with col_result2:
                    st.info(f"📊 Code de retour: {returncode}")
                
                # Affichage de la sortie standard
                if stdout:
                    with st.expander("📤 Sortie standard (stdout)", expanded=returncode != 0):
                        st.code(stdout, language="text")
                
                # Affichage des erreurs
                if stderr:
                    with st.expander("⚠️ Erreurs (stderr)", expanded=True):
                        st.code(stderr, language="text")
                
                # Messages d'aide selon le code de retour
                if returncode != 0:
                    st.markdown("### 💡 Aide au diagnostic")
                    
                    if returncode == 127:
                        st.error("❌ **Commande introuvable**: Vérifiez que `run_pipeline.sh` existe et est exécutable")
                        st.code("chmod +x run_pipeline.sh", language="bash")
                    
                    elif returncode == 1:
                        st.warning("⚠️ **Erreur générale**: Consultez les logs stderr ci-dessus")
                    
                    elif returncode == 2:
                        st.warning("⚠️ **Erreur de paramètres**: Vérifiez les arguments passés au script")
                    
                    elif returncode == -1:
                        st.error("❌ **Erreur système**: Problème avec l'exécution de la commande")
                    
                    # Vérifications supplémentaires
                    st.markdown("**Vérifications suggérées:**")
                    
                    # Vérifier l'existence du script
                    if not os.path.exists("run_pipeline.sh"):
                        st.error("❌ Le fichier `run_pipeline.sh` n'existe pas dans le répertoire courant")
                    else:
                        st.success("✅ Le fichier `run_pipeline.sh` existe")
                        
                        # Vérifier les permissions
                        if not os.access("run_pipeline.sh", os.X_OK):
                            st.warning("⚠️ Le fichier `run_pipeline.sh` n'est pas exécutable")
                            st.code("chmod +x run_pipeline.sh", language="bash")
                        else:
                            st.success("✅ Le fichier `run_pipeline.sh` est exécutable")
                    
                    # Vérifier l'existence des fichiers d'entrée
                    if not select_all:
                        for fastq_path in fastq_to_pass.split(","):
                            if not os.path.exists(fastq_path):
                                st.error(f"❌ Fichier FASTQ introuvable: {fastq_path}")
                            else:
                                st.success(f"✅ Fichier FASTQ trouvé: {os.path.basename(fastq_path)}")
                    
                    # Vérifier le fichier BED
                    if bed_file:
                        if not os.path.exists(bed_file):
                            st.error(f"❌ Fichier BED introuvable: {bed_file}")
                        else:
                            st.success(f"✅ Fichier BED trouvé: {os.path.basename(bed_file)}")
                
                # 💾 Sauvegarde du log (comme dans tab2)
                save_debug_log(sample_name, command_str, returncode, stdout, stderr)
                
                # Sauvegarde de la configuration seulement en cas de succès
                # if returncode == 0:
                #     config = {
                #         "sample_name": sample_name,
                #         "reference": reference,
                #         "partition": partition,
                #         "threads": str(threads),
                #         "fastq_input": fastq_to_pass,
                #         "bed_file": bed_file if bed_file else "",
                #         "do_phasing": str(do_phasing)
                #     }
                #     save_config(sample_name, config)
                #     st.success("📁 Configuration sauvegardée")
                                
            except Exception as e:
                st.error(f"❌ Erreur Python: {str(e)}")
                
                # Affichage de détails supplémentaires pour le debugging
                with st.expander("🔧 Informations de débogage", expanded=True):
                    st.code(f"""
        Type d'erreur: {type(e).__name__}
        Message: {str(e)}
        Répertoire de travail: {os.getcwd()}
        Script existe: {os.path.exists('run_pipeline.sh')}
        Script exécutable: {os.access('run_pipeline.sh', os.X_OK) if os.path.exists('run_pipeline.sh') else 'N/A'}
                    """, language="text")
                
                # Sauvegarder aussi les erreurs Python
                save_debug_log(sample_name, command_str if 'command_str' in locals() else str(cmd), -999, "", str(e))
        # Message d'aide si pas de sélection
        if not can_launch and not fastq_to_pass:
            st.info("💡 **Astuce:** Sélectionnez des fichiers FASTQ ou cochez 'Tout sélectionner' pour continuer")

with tab2:
    st.header("Étapes Manuelles")
    
    if not sample_name:
        st.warning("Veuillez d'abord spécifier un nom d'échantillon")
    else:
        st.subheader("Sélection des étapes")
        
        col1, col2, col3 = st.columns(3)
        
        with col1:
            step1 = st.checkbox("1. Alignement (minimap2 + samtools)")
            step2 = st.checkbox("2. SNPs (Clair3)")
            step3 = st.checkbox("3. SVs (Sniffles2, cuteSV)")
            
        with col2:
            step4 = st.checkbox("4. CNV (CNVkit)")
            step5 = st.checkbox("5. Méthylation (modkit + methylArtist)")
        
        with col3:
            step6 = st.checkbox("6. QC (Samtools_stats, NanoStat)")
            step7 = st.checkbox("7. Annotation (VEP, Annovar)")
        
        # Collecte des étapes sélectionnées
        selected_steps = []
        if step1: selected_steps.append("1")
        if step2: selected_steps.append("2")
        if step3: selected_steps.append("3")
        if step4: selected_steps.append("4")
        if step5: selected_steps.append("5")
        if step6: selected_steps.append("6")
        if step7: selected_steps.append("7")
        
        if selected_steps:
            st.subheader("Paramètres spécifiques")
            
            # Analyse des dépendances
            alignment_selected = "1" in selected_steps
            needs_bam = any(step in selected_steps for step in ["2", "3", "4", "6"])
            needs_vcf = "7" in selected_steps
            needs_modified_bam = "5" in selected_steps
            
            # Messages d'information sur les dépendances
            if needs_bam or needs_vcf or needs_modified_bam:
                with st.expander("ℹ️ Informations sur les dépendances", expanded=False):
                    if alignment_selected and needs_bam:
                        st.info("✅ L'alignement étant sélectionné, il générera automatiquement le BAM nécessaire pour les autres étapes.")
                    elif needs_bam and not alignment_selected:
                        st.warning("⚠️ Les étapes sélectionnées nécessitent un fichier BAM. Veuillez le fournir ci-dessous.")
                    
                    if "7" in selected_steps and "2" not in selected_steps:
                        st.warning("⚠️ L'annotation nécessite un fichier VCF. Veuillez le fournir ci-dessous.")
                    elif "7" in selected_steps and "2" in selected_steps:
                        st.info("✅ La détection de SNPs générera automatiquement le VCF nécessaire pour l'annotation.")
            
            # Variables pour stocker les entrées
            fastq_input = None
            bam_input = None
            vcf_input = None
            modified_bam = None
            region_file = None
            do_phasing_manual = False
            
            # Paramètres d'entrée selon les dépendances
            if alignment_selected:
                # Si alignement sélectionné, on a besoin du FASTQ
                with st.spinner("Chargement des fichiers FASTQ..."):
                    fastq_files = list_files(base_folder_fastq, extensions=[".fastq", ".fastq.gz"])
                
                if fastq_files:
                    col_fastq1, col_fastq2 = st.columns([3, 1])
                    with col_fastq1:
                        # Option pour tout sélectionner
                        select_all_manual = st.checkbox("🔄 Utiliser tous les fichiers FASTQ", key="select_all_manual")
                        
                        if select_all_manual:
                            fastq_input = base_folder_fastq
                            st.success(f"✅ Tous les fichiers FASTQ sélectionnés ({len(fastq_files)} fichiers)")
                        else:
                            selected_fastq_manual = st.multiselect(
                                "📁 Sélectionnez les fichiers FASTQ :",
                                fastq_files,
                                help="Fichiers FASTQ pour l'alignement"
                            )
                            if selected_fastq_manual:
                                fastq_paths = [os.path.join(base_folder_fastq, f) for f in selected_fastq_manual]
                                fastq_input = ",".join(fastq_paths)
                else:
                    st.error("❌ Aucun fichier FASTQ trouvé")
            
            elif needs_bam:
                # Si alignement non sélectionné mais étapes nécessitant BAM sélectionnées
                bam_input = st.text_input(
                    "📄 Fichier BAM d'entrée :",
                    help="Fichier BAM aligné nécessaire pour les étapes sélectionnées",
                    placeholder="/chemin/vers/votre/fichier.bam"
                )
                if bam_input and not os.path.exists(bam_input):
                    st.warning(f"⚠️ Fichier BAM introuvable: {bam_input}")
            
            # Paramètres pour l'annotation (étape 7)
            if "7" in selected_steps and "2" not in selected_steps:
                vcf_input = st.text_input(
                    "📄 Fichier VCF d'entrée :",
                    help="Fichier VCF contenant les variants à annoter",
                    placeholder="/chemin/vers/votre/fichier.vcf"
                )
                if vcf_input and not os.path.exists(vcf_input):
                    st.warning(f"⚠️ Fichier VCF introuvable: {vcf_input}")
            
            # Paramètres pour la méthylation (étape 5)
            if needs_modified_bam:
                modified_bam = st.text_input(
                    "🧬 BAM modifié (pour méthylation) :",
                    help="Fichier BAM pré-annoté avec modkit pour l'analyse de méthylation",
                    placeholder="/chemin/vers/votre/fichier_modifie.bam"
                )
                if modified_bam and not os.path.exists(modified_bam):
                    st.warning(f"⚠️ Fichier BAM modifié introuvable: {modified_bam}")
            
            # Paramètres optionnels communs
            st.markdown("**Paramètres optionnels :**")
            col_opt1, col_opt2 = st.columns(2)
            
            with col_opt1:
                region_file = st.text_input(
                    "📋 Fichier de régions (BED) :",
                    help="Fichier BED pour restreindre l'analyse à certaines régions",
                    placeholder="/chemin/vers/regions.bed"
                )
                if region_file and not os.path.exists(region_file):
                    st.warning(f"⚠️ Fichier BED introuvable: {region_file}")
            
            with col_opt2:
                # Phasage disponible seulement si SNPs sélectionnés
                if "2" in selected_steps:
                    do_phasing_manual = st.checkbox(
                        "🧬 Effectuer le phasage (WhatsHap)",
                        help="Active le phasage des variants SNPs détectés"
                    )
                # else:
                #     st.text("🧬 Phasage (nécessite l'étape SNPs)")
            
            # Validation avant exécution
            st.markdown("---")
            can_execute = True
            error_messages = []
            
            # Vérifications des dépendances
            if alignment_selected and not fastq_input:
                can_execute = False
                error_messages.append("❌ Fichiers FASTQ requis pour l'alignement")
            
            if needs_bam and not alignment_selected and not bam_input:
                can_execute = False
                error_messages.append("❌ Fichier BAM requis pour les étapes sélectionnées")
            
            if "7" in selected_steps and "2" not in selected_steps and not vcf_input:
                can_execute = False
                error_messages.append("❌ Fichier VCF requis pour l'annotation")
            
            if needs_modified_bam and not modified_bam:
                can_execute = False
                error_messages.append("❌ BAM modifié requis pour l'analyse de méthylation")
            
            # Affichage des erreurs
            if error_messages:
                for msg in error_messages:
                    st.error(msg)
            
            # Résumé de la configuration
            if can_execute:
                with st.expander("📋 Résumé de la configuration", expanded=False):
                    st.write(f"**Étapes sélectionnées:** {', '.join(selected_steps)}")
                    if fastq_input:
                        if fastq_input == base_folder_fastq:
                            st.write(f"**FASTQ:** Tous les fichiers du dossier")
                        else:
                            nb_files = len(fastq_input.split(','))
                            st.write(f"**FASTQ:** {nb_files} fichier(s) sélectionné(s)")
                    if bam_input:
                        st.write(f"**BAM:** {bam_input}")
                    if vcf_input:
                        st.write(f"**VCF:** {vcf_input}")
                    if modified_bam:
                        st.write(f"**BAM modifié:** {modified_bam}")
                    if region_file:
                        st.write(f"**Régions:** {region_file}")
                    if do_phasing_manual:
                        st.write("**Phasage:** Activé")
            
            # Bouton d'exécution
            if st.button("▶️ Exécuter les étapes sélectionnées", type="primary", disabled=not can_execute):
                # Construire la commande
                cmd = [
                    "bash", "run_pipeline.sh", "--non-interactive",
                    "--sample", sample_name,
                    "--reference", reference,
                    "--partition", partition,
                    "--threads", str(threads)
                ]

                cmd.extend(["--option", "2"])
                # Ajouter les étapes
                for step in selected_steps:
                    cmd.extend(["--step", step])


                # Ajouter les fichiers d'entrée
                if fastq_input:
                    cmd.extend(["--fastq_input", fastq_input])


                if bam_input:
                    cmd.extend(["--bam_input", bam_input])


                if vcf_input:
                    cmd.extend(["--vcf_input", vcf_input])


                if modified_bam:
                    cmd.extend(["--modified_bam", modified_bam])


                if region_file and os.path.exists(region_file):
                    cmd.extend(["--bed", region_file])


                if do_phasing_manual:
                    cmd.append("--phase")


                # 🔥 Exécution robuste
                with st.spinner("⏳ Soumission des étapes en cours..."):
                    command_str = " ".join(cmd)
                    returncode, stdout, stderr = run_pipeline_command(command_str)


                # 🔍 Affichage des résultats
                display_debug_info(returncode, stdout, stderr, cmd)


                # 💾 Sauvegarde du log
                save_debug_log(sample_name, command_str, returncode, stdout, stderr)


                if returncode == 0:
                    st.success("✅ Étapes soumises avec succès!")
                else:
                    st.error("❌ Une erreur est survenue. Vérifiez les logs.")

            # Message d'aide
            if not can_execute:
                st.info("💡 **Astuce:** Vérifiez que tous les fichiers requis sont spécifiés et existants")

with tab3:
    st.header("Monitoring des Jobs")
    
    if st.button("🔄 Actualiser le statut"):
        try:
            # Commande pour vérifier les jobs SLURM
            result = subprocess.run(["squeue", "-u", os.getenv("USER", "")], 
                                  capture_output=True, text=True)
            
            if result.returncode == 0:
                st.subheader("Jobs en cours")
                st.code(result.stdout)
            else:
                st.warning("Impossible de récupérer le statut des jobs")
                
        except Exception as e:
            st.error(f"Erreur: {str(e)}")
    
    # Affichage des logs récents
    # if sample_name:
    #     log_dir = "logs"
    #     if os.path.exists(log_dir):
    #         log_files = [f for f in os.listdir(log_dir) if f.endswith('.out')]
    #         log_files.sort(key=lambda x: os.path.getmtime(os.path.join(log_dir, x)), reverse=True)
            
    #         if log_files:
    #             st.subheader("Logs récents")
    #             selected_log = st.selectbox("Sélectionner un log", log_files[:10])
                
    #             if selected_log:
    #                 log_path = os.path.join(log_dir, selected_log)
    #                 try:
    #                     with open(log_path, 'r') as f:
    #                         log_content = f.read()
    #                     st.code(log_content, height=300)
    #                 except Exception as e:
    #                     st.error(f"Erreur lors de la lecture du log: {str(e)}")
    # Remplacez cette partie dans votre code existant :
    # Section des logs - toujours visible
   # Section des logs - toujours visible
    st.subheader("Gestion des logs")

    # Gestion de l'état d'ouverture/fermeture avec toggle
    if "show_logs" not in st.session_state:
        st.session_state.show_logs = False

    # Bouton pour afficher/masquer les logs
    if st.button("📝 Voir les logs des jobs en cours" if not st.session_state.show_logs else "❌ Fermer les logs"):
        st.session_state.show_logs = not st.session_state.show_logs

    # Affichage des logs si l'état est activé
    if st.session_state.show_logs:
        log_dir = "logs"
        if os.path.exists(log_dir):
            # Récupérer tous les fichiers de logs
            all_log_files = [f for f in os.listdir(log_dir) if f.endswith('.out')]
            
            # Filtrer par sample_name seulement s'il est défini et existe
            if 'sample_name' in locals() and sample_name:
                sample_log_files = [f for f in all_log_files if sample_name in f]
                log_files = sample_log_files
                title = f"Logs pour l'échantillon '{sample_name}'"
            else:
                log_files = all_log_files
                title = "Tous les fichiers de logs"
            
            # Trier par date de modification (plus récents en premier)
            if log_files:
                log_files = sorted(
                    log_files,
                    key=lambda x: os.path.getmtime(os.path.join(log_dir, x)),
                    reverse=True
                )
                
                # Sélecteur de fichier de log
                selected_log = st.selectbox(
                    title,
                    log_files[:10],  # Les 10 plus récents
                    key="log_selector"  # Ajout d'une clé unique
                )
                
                if selected_log:
                    log_path = os.path.join(log_dir, selected_log)
                    try:
                        with open(log_path, 'r', encoding='utf-8') as f:
                            log_content = f.read()
                        
                        # Affichage du contenu du log
                        st.text_area(
                            f"Contenu de {selected_log}",
                            log_content,
                            height=300,
                            key="log_content"  # Ajout d'une clé unique
                        )
                        
                        # Bouton pour télécharger le log
                        st.download_button(
                            label="📥 Télécharger ce log",
                            data=log_content,
                            file_name=selected_log,
                            mime="text/plain"
                        )
                        
                    except Exception as e:
                        st.error(f"Erreur lors de la lecture du log: {str(e)}")
            else:
                if 'sample_name' in locals() and sample_name:
                    st.info(f"Aucun fichier de log trouvé pour l'échantillon '{sample_name}'")
                else:
                    st.info("Aucun fichier de log trouvé dans le dossier logs/")
        else:
            st.warning("Le dossier 'logs' n'existe pas. Vérifiez que vos jobs génèrent bien des logs dans ce répertoire.")


# with tab4:
#     st.header("Aide et Documentation")
    
#     st.markdown("""
#     ## Pipeline de détection de variants Nanopore
    
#     Ce pipeline intègre plusieurs outils pour l'analyse de données Nanopore :
    
#     ### Étapes du pipeline :
    
#     1. **Alignement** : minimap2 + samtools
#        - Aligne les reads Nanopore sur le génome de référence
#        - Produit un fichier BAM indexé
    
#     2. **Détection de SNPs** : Clair3 + WhatsHap (optionnel)
#        - Détecte les variants ponctuels et petites indels
#        - Phasage optionnel avec WhatsHap
    
#     3. **Détection de SVs** : Sniffles2 + cuteSV + SURVIVOR
#        - Détecte les variants structuraux
#        - Fusion des résultats avec SURVIVOR
    
#     4. **CNV** : CNVkit
#        - Détection des variations du nombre de copies
    
#     5. **Méthylation** : modkit + methylArtist
#        - Analyse de la méthylation de l'ADN
#        - Nécessite un BAM pré-annoté avec modkit
    
#     6. **Contrôle qualité** : samtools stats + NanoStat + MultiQC
#        - Évaluation de la qualité des données et de l'alignement
    
#     7. **Annotation** : VEP + Annovar
#        - Annotation fonctionnelle des variants détectés
    
#     ### Dépendances entre étapes :
#     - Les étapes 2, 3, 6 dépendent de l'étape 1 (Alignement)
#     - L'étape 4 peut dépendre de l'étape 3 (SVs)
#     - L'étape 7 dépend de l'étape 2 (SNPs)
    
#     ### Configuration requise :
#     - Cluster SLURM avec partitions configurées
#     - Outils bioinformatiques installés (minimap2, samtools, Clair3, etc.)
#     - Génome de référence (hg38 par défaut)
#     """)

# Ajoutez ceci après votre tab3 (Monitoring des Jobs)
# with tab4:
#     st.header("📈 Résultats et Suivi")
    
#     # Sélection d'échantillon avec info contextuelle
#     if 'sample_name' in locals() and sample_name:
#         selected_sample = sample_name
#         st.info(f"🔍 Affichage des résultats pour l'échantillon sélectionné : **{sample_name}**")
#     else:
#         # Si pas d'échantillon sélectionné, permettre la sélection
#         results_dir = Path("results")
#         if results_dir.exists():
#             available_samples = [d.name for d in results_dir.iterdir() if d.is_dir()]
#             if available_samples:
#                 selected_sample = st.selectbox("📋 Sélectionner un échantillon", available_samples)
#             else:
#                 st.warning("Aucun résultat d'échantillon trouvé dans le dossier 'results/'")
#                 selected_sample = None
#         else:
#             st.warning("Dossier 'results/' non trouvé")
#             selected_sample = None
    
#     if selected_sample:
#         sample_dir = Path("results") / selected_sample
        
#         # Sous-onglets pour organiser les résultats
#         sub_tab1, sub_tab2, sub_tab3, sub_tab4 = st.tabs([
#             "🎯 État d'avancement", 
#             "📁 Fichiers de sortie", 
#             "📊 Métriques QC", 
#             "📋 Rapports"
#         ])
        
#         with sub_tab1:
#             st.subheader(f"État d'avancement - {selected_sample}")
            
#             # Définition des étapes avec informations détaillées
#             steps_info = {
#                 "🧬 Alignement": {
#                     "files": [f"{selected_sample}.bam", f"{selected_sample}.bam.bai"],
#                     "path": "mapping",
#                     "description": "Alignement des reads sur le génome de référence"
#                 },
#                 "🔍 Appel de variants (SNPs/INDELs)": {
#                     "files": ["merge_output.vcf.gz", "merge_output.vcf.gz.tbi"],
#                     "path": "snps_clair3",
#                     "description": "Détection des variants courts avec Clair3"
#                 },
#                 "📏 Variants structuraux (SVs)": {
#                     "files": ["merged_sv.vcf", "merged_sv.vcf.gz"],
#                     "path": "svs",
#                     "description": "Détection des variants structuraux"
#                 },
#                 "📈 Variations du nombre de copies (CNVs)": {
#                     "files": [f"{selected_sample}.cns", f"{selected_sample}.cnr"],
#                     "path": "cnvkit",
#                     "description": "Analyse des variations du nombre de copies"
#                 },
#                 "✅ Contrôle qualité": {
#                     "files": ["multiqc_report.html", "multiqc_data/"],
#                     "path": "qc",
#                     "description": "Rapport de qualité global"
#                 },
#                 "🏷️ Annotation": {
#                     "files": ["annotated.vcf", "annotated.html"],
#                     "path": "annotation",
#                     "description": "Annotation fonctionnelle des variants"
#                 }
#             }
            
#             # Affichage en colonnes pour un meilleur layout
#             col1, col2 = st.columns([2, 1])
            
#             completed_steps = 0
#             total_steps = len(steps_info)
            
#             for step_name, step_info in steps_info.items():
#                 step_path = sample_dir / step_info["path"]
#                 files_found = []
                
#                 if step_path.exists():
#                     for file_pattern in step_info["files"]:
#                         if "/" in file_pattern:  # C'est un dossier
#                             if (step_path / file_pattern.split("/")[0]).exists():
#                                 files_found.append(file_pattern)
#                         else:  # C'est un fichier
#                             if (step_path / file_pattern).exists():
#                                 files_found.append(file_pattern)
                
#                 with col1:
#                     if files_found:
#                         st.success(f"✅ **{step_name}**")
#                         st.caption(step_info["description"])
#                         with st.expander(f"Fichiers générés ({len(files_found)})"):
#                             for file_name in files_found:
#                                 st.text(f"📄 {file_name}")
#                         completed_steps += 1
#                     else:
#                         st.error(f"❌ **{step_name}**")
#                         st.caption(step_info["description"])
#                         st.caption("⏳ En attente ou en cours...")
            
#             # Barre de progression globale
#             with col2:
#                 progress = completed_steps / total_steps
#                 st.metric("Progression globale", f"{completed_steps}/{total_steps}")
#                 st.progress(progress)
                
#                 if progress == 1.0:
#                     st.balloons()
#                     st.success("🎉 Pipeline terminé !")
#                 elif progress > 0:
#                     st.info(f"⚡ {completed_steps} étapes terminées")
#                 else:
#                     st.warning("🔄 Pipeline en cours de démarrage")
        
#         with sub_tab2:
#             st.subheader("📁 Fichiers de sortie disponibles")
            
#             if sample_dir.exists():
#                 # Types de fichiers importants avec descriptions
#                 file_types = {
#                     "*.vcf*": "🧬 Fichiers de variants",
#                     "*.bam": "📊 Fichiers d'alignement",
#                     "*.html": "📋 Rapports HTML",
#                     "*.pdf": "📄 Rapports PDF",
#                     "*.cns": "📈 Données CNV",
#                     "*.png": "📸 Graphiques"
#                 }
                
#                 all_files = []
#                 for pattern, description in file_types.items():
#                     files = list(sample_dir.rglob(pattern))
#                     if files:
#                         st.write(f"**{description}**")
#                         for file_path in files[:10]:  # Limiter l'affichage
#                             file_size = file_path.stat().st_size / (1024 * 1024)  # MB
#                             file_date = datetime.fromtimestamp(file_path.stat().st_mtime)
                            
#                             col1, col2, col3, col4 = st.columns([3, 1, 1, 1])
#                             with col1:
#                                 st.text(f"📄 {file_path.name}")
#                             with col2:
#                                 st.text(f"{file_size:.1f} MB")
#                             with col3:
#                                 st.text(file_date.strftime("%H:%M"))
#                             with col4:
#                                 if st.button("⬇️", key=f"download_{file_path.name}"):
#                                     try:
#                                         with open(file_path, 'rb') as f:
#                                             st.download_button(
#                                                 label="Télécharger",
#                                                 data=f.read(),
#                                                 file_name=file_path.name,
#                                                 key=f"dl_{file_path.name}"
#                                             )
#                                     except Exception as e:
#                                         st.error(f"Erreur de téléchargement: {e}")
#                         st.divider()
#             else:
#                 st.warning("📂 Répertoire de résultats non trouvé")
        
#         with sub_tab3:
#             st.subheader("📊 Métriques de qualité")
            
#             # Recherche de fichiers de métriques
#             qc_files = {
#                 "MultiQC": sample_dir / "qc" / "multiqc_report.html",
#                 "NanoPlot": sample_dir / "qc" / "NanoPlot-report.html", 
#                 "FastQC": sample_dir / "qc" / "fastqc_report.html"
#             }
            
#             metrics_found = False
#             for qc_name, qc_path in qc_files.items():
#                 if qc_path.exists():
#                     metrics_found = True
#                     col1, col2 = st.columns([3, 1])
#                     with col1:
#                         st.success(f"✅ Rapport {qc_name} disponible")
#                     with col2:
#                         if st.button(f"👁️ Voir", key=f"view_{qc_name}"):
#                             st.info(f"Ouverture du rapport {qc_name}...")
            
#             if not metrics_found:
#                 st.info("📊 Aucun rapport de qualité trouvé pour cet échantillon")
#                 st.caption("Les rapports seront disponibles une fois l'étape QC terminée")
        
#         with sub_tab4:
#             st.subheader("📋 Rapports détaillés")
            
#             # Boutons pour générer des rapports personnalisés
#             col1, col2, col3 = st.columns(3)
            
#             with col1:
#                 if st.button("📊 Rapport de variants"):
#                     st.info("🔄 Génération du rapport de variants en cours...")
#                     # Ici vous pourriez appeler une fonction pour générer le rapport
            
#             with col2:
#                 if st.button("📈 Rapport CNV"):
#                     st.info("🔄 Génération du rapport CNV en cours...")
            
#             with col3:
#                 if st.button("🧬 Rapport complet"):
#                     st.info("🔄 Génération du rapport complet en cours...")
            
#             st.divider()
            
#             # Espace pour afficher des visualisations
#             st.subheader("📈 Visualisations")
            
#             # Placeholder pour des graphiques
#             if st.checkbox("Afficher les statistiques d'alignement"):
#                 # Ici vous pourriez ajouter des graphiques avec matplotlib/plotly
#                 st.info("📊 Graphiques d'alignement à implémenter")
            
#             if st.checkbox("Afficher la distribution des variants"):
#                 st.info("📊 Distribution des variants à implémenter")
    
#     else:
#         st.info("👆 Sélectionnez un échantillon pour voir ses résultats")

with tab4:
    st.header("📈 Résultats et Suivi")
    
    # Sélection d'échantillon avec info contextuelle
    if 'sample_name' in locals() and sample_name:
        selected_sample = sample_name
        st.info(f"🔍 Affichage des résultats pour l'échantillon sélectionné : **{sample_name}**")
    else:
        # Si pas d'échantillon sélectionné, permettre la sélection
        results_dir = Path("results")
        if results_dir.exists():
            available_samples = [d.name for d in results_dir.iterdir() if d.is_dir()]
            if available_samples:
                selected_sample = st.selectbox("📋 Sélectionner un échantillon", available_samples)
            else:
                st.warning("Aucun résultat d'échantillon trouvé dans le dossier 'results/'")
                selected_sample = None
        else:
            st.warning("Dossier 'results/' non trouvé")
            selected_sample = None
    
    if selected_sample:
        sample_dir = Path("results") / selected_sample
        
        # Sous-onglets pour organiser les résultats
        sub_tab1, sub_tab2, sub_tab3, sub_tab4 = st.tabs([
            "🎯 État d'avancement", 
            "📁 Fichiers de sortie", 
            "📊 Métriques QC", 
            "📋 Rapports"
        ])
        
        with sub_tab1:
            st.subheader(f"État d'avancement - {selected_sample}")
            
            # Définition des étapes avec informations détaillées
            steps_info = {
                "🧬 Alignement": {
                    "files": [f"{selected_sample}.bam", f"{selected_sample}.bam.bai"],
                    "path": "mapping",
                    "description": "Alignement des reads sur le génome de référence"
                },
                "🔍 Appel de variants (SNPs/INDELs)": {
                    "files": ["merge_output.vcf.gz", "merge_output.vcf.gz.tbi"],
                    "path": "snps_clair3",
                    "description": "Détection des variants courts avec Clair3"
                },
                "📏 Variants structuraux (SVs)": {
                    "files": ["*.vcf", "*.vcf.gz", "*.sv", "*.bed"],
                    "path": "svs",
                    "description": "Détection des variants structuraux"
                },
                "📈 Variations du nombre de copies (CNVs)": {
                    "files": [f"{selected_sample}.cns", f"{selected_sample}.cnr"],
                    "path": "cnvkit",
                    "description": "Analyse des variations du nombre de copies"
                },
                "✅ Contrôle qualité": {
                    "files": ["multiqc_report.html", "multiqc_data"],
                    "path": "qc",
                    "description": "Rapport de qualité global"
                },
                "🏷️ Annotation": {
                    "files": ["*_annotation_vep.tsv", "*_annovar_pileup.hg38_multianno.vcf", "*_annovar_pileup.hg38_multianno.txt"],
                    "path": "annotation",
                    "description": "Annotation fonctionnelle des variants"
                }
            }
            
            # Affichage en colonnes pour un meilleur layout
            col1, col2 = st.columns([2, 1])
            
            completed_steps = 0
            total_steps = len(steps_info)
            
            for step_name, step_info in steps_info.items():
                step_path = sample_dir / step_info["path"]
                files_found = []
                
                # Vérification améliorée de l'existence des fichiers
                if step_path.exists():
                    for file_pattern in step_info["files"]:
                        file_path = step_path / file_pattern
                        
                        # Vérifier si c'est un fichier ou un dossier
                        if file_path.exists():
                            files_found.append(file_pattern)
                        else:
                            # Essayer avec des patterns glob pour plus de flexibilité
                            glob_results = list(step_path.glob(file_pattern))
                            if glob_results:
                                files_found.extend([f.name for f in glob_results])
                
                with col1:
                    if files_found:
                        st.success(f"✅ **{step_name}**")
                        st.caption(step_info["description"])
                        with st.expander(f"Fichiers générés ({len(files_found)})"):
                            for file_name in files_found:
                                st.text(f"📄 {file_name}")
                        completed_steps += 1
                    else:
                        st.error(f"❌ **{step_name}**")
                        st.caption(step_info["description"])
                        st.caption("⏳ En attente ou en cours...")
                        
                        # Debug : afficher le chemin recherché
                        if st.checkbox(f"Debug {step_name}", key=f"debug_{step_name}"):
                            st.text(f"Chemin recherché: {step_path}")
                            st.text(f"Chemin existe: {step_path.exists()}")
                            if step_path.exists():
                                st.text("Fichiers dans le dossier:")
                                for item in step_path.iterdir():
                                    st.text(f"  - {item.name} ({'dir' if item.is_dir() else 'file'})")
            
            # Barre de progression globale
            with col2:
                progress = completed_steps / total_steps
                st.metric("Progression globale", f"{completed_steps}/{total_steps}")
                st.progress(progress)
                
                if progress == 1.0:
                    st.balloons()
                    st.success("🎉 Pipeline terminé !")
                elif progress > 0:
                    st.info(f"⚡ {completed_steps} étapes terminées")
                else:
                    st.warning("🔄 Pipeline en cours de démarrage")
        
        with sub_tab2:
            st.subheader("📁 Fichiers de sortie disponibles")
            
            if sample_dir.exists():
                # Types de fichiers importants avec descriptions
                file_types = {
                    "*.vcf*": "🧬 Fichiers de variants",
                    "*.bam": "📊 Fichiers d'alignement",
                    "*.html": "📋 Rapports HTML",
                    "*.pdf": "📄 Rapports PDF",
                    "*.cns": "📈 Données CNV",
                    "*.png": "📸 Graphiques"
                }
                
                all_files = []
                for pattern, description in file_types.items():
                    files = list(sample_dir.rglob(pattern))
                    if files:
                        st.write(f"**{description}**")
                        for file_path in files[:10]:  # Limiter l'affichage
                            file_size = file_path.stat().st_size / (1024 * 1024)  # MB
                            file_date = datetime.fromtimestamp(file_path.stat().st_mtime)
                            
                            col1, col2, col3, col4 = st.columns([3, 1, 1, 1])
                            with col1:
                                st.text(f"📄 {file_path.name}")
                            with col2:
                                st.text(f"{file_size:.1f} MB")
                            with col3:
                                st.text(file_date.strftime("%H:%M"))
                            with col4:
                                if st.button("⬇️", key=f"download_{file_path.name}"):
                                    try:
                                        with open(file_path, 'rb') as f:
                                            st.download_button(
                                                label="Télécharger",
                                                data=f.read(),
                                                file_name=file_path.name,
                                                key=f"dl_{file_path.name}"
                                            )
                                    except Exception as e:
                                        st.error(f"Erreur de téléchargement: {e}")
                        st.divider()
            else:
                st.warning("📂 Répertoire de résultats non trouvé")
        
        with sub_tab3:
            st.subheader("📊 Métriques de qualité")
            
            # Recherche de fichiers de métriques
            qc_files = {
                "MultiQC": sample_dir / "qc" / "multiqc_report.html",
                "NanoPlot": sample_dir / "qc" / "NanoPlot-report.html", 
                "FastQC": sample_dir / "qc" / "fastqc_report.html"
            }
            
            metrics_found = False
            for qc_name, qc_path in qc_files.items():
                if qc_path.exists():
                    metrics_found = True
                    col1, col2 = st.columns([3, 1])
                    with col1:
                        st.success(f"✅ Rapport {qc_name} disponible")
                    with col2:
                        if st.button(f"👁️ Voir", key=f"view_{qc_name}"):
                            st.info(f"Ouverture du rapport {qc_name}...")
            
            if not metrics_found:
                st.info("📊 Aucun rapport de qualité trouvé pour cet échantillon")
                st.caption("Les rapports seront disponibles une fois l'étape QC terminée")
        
        with sub_tab4:
            st.subheader("📋 Rapports détaillés")
            
            # Boutons pour générer des rapports personnalisés
            col1, col2, col3 = st.columns(3)
            
            with col1:
                if st.button("📊 Rapport de variants"):
                    st.info("🔄 Génération du rapport de variants en cours...")
                    # Ici vous pourriez appeler une fonction pour générer le rapport
            
            with col2:
                if st.button("📈 Rapport CNV"):
                    st.info("🔄 Génération du rapport CNV en cours...")
            
            with col3:
                if st.button("🧬 Rapport complet"):
                    st.info("🔄 Génération du rapport complet en cours...")
            
            st.divider()
            
            # Espace pour afficher des visualisations
            st.subheader("📈 Visualisations")
            
            # Placeholder pour des graphiques
            if st.checkbox("Afficher les statistiques d'alignement"):
                # Ici vous pourriez ajouter des graphiques avec matplotlib/plotly
                st.info("📊 Graphiques d'alignement à implémenter")
            
            if st.checkbox("Afficher la distribution des variants"):
                st.info("📊 Distribution des variants à implémenter")
    
    else:
        st.info("👆 Sélectionnez un échantillon pour voir ses résultats")

# Footer
st.markdown("---")
st.markdown("*Pipeline développé pour l'UPJV - Version Streamlit*")