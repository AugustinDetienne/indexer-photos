#!/bin/bash
# Désinstaller Indexer photos
# Supprime l'application et le script. Les mots-clés déjà écrits dans les photos restent en place.
# Homebrew, exiftool, Python et Ollama ne sont pas touchés (d'autres logiciels peuvent s'en servir).

oui() { local r; read -r -p "$1 [o/N] " r; [[ "$r" =~ ^[oOyY] ]]; }
APP_NAME="Indexer photos"
cd "$HOME" || cd /   # le dossier courant peut avoir été supprimé (ex. ~/photo_indexer)

echo "Désinstallation d'Indexer photos"
echo "Les mots-clés déjà écrits dans tes photos ne seront PAS supprimés."
echo
oui "Continuer ?" || exit 0

for d in /Applications "$HOME/Applications"; do
  [ -d "$d/$APP_NAME.app" ] && rm -rf "$d/$APP_NAME.app" && echo "✔ Application supprimée ($d)"
done

echo "→ Si l'icône reste dans le Dock : clic droit dessus > Options > Supprimer du Dock."

MODEL="gemma4:26b"
[ -f "$HOME/photo_indexer/config.sh" ] && MODEL=$(grep -E '^MODEL=' "$HOME/photo_indexer/config.sh" | head -1 | cut -d'"' -f2)
[ -d "$HOME/photo_indexer" ] && rm -rf "$HOME/photo_indexer" && echo "✔ Script et réglages supprimés"

command -v ollama >/dev/null 2>&1 || PATH="$PATH:/Applications/Ollama.app/Contents/Resources"
if [ -n "$MODEL" ] && command -v ollama >/dev/null 2>&1 && oui "Supprimer aussi le modèle d'IA $MODEL (libère 6 à 18 Go) ?"; then
  ollama rm "$MODEL" && echo "✔ Modèle supprimé"
fi

echo
echo "Terminé. Les fichiers .photo_indexer_state.jsonl laissés dans les dossiers indexés peuvent être supprimés."
read -r -p "Appuie sur Entrée pour fermer." _
