# Réglages d'Indexer photos — modifiables avec n'importe quel éditeur de texte.
# Ce fichier n'est pas écrasé quand on relance l'installateur.

# Modèle vision Ollama (vérifier le nom exact avec : ollama list)
#   gemma4:26b            mode standard, Mac de 32 Go et plus (recommandé)
#   qwen3-vl:8b-instruct  mode léger, Mac de 16 Go : plus lent, un peu moins juste
# Après un changement, télécharger le modèle : ollama pull <nom>
MODEL="__MODEL__"

# Requêtes simultanées : 2 sur un Mac de 64 Go ou plus, sinon 1
WORKERS=__WORKERS__

# Conteneurs Docker à mettre en pause pendant l'indexation pour libérer le GPU
# (ex. un Paperless qui utilise lui aussi Ollama). Séparés par des espaces.
# Exemple : PAUSE_CONTAINERS="paperless-webserver-1"
PAUSE_CONTAINERS=""
