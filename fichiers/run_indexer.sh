#!/bin/bash
# run_indexer.sh — lancé par l'application « Indexer photos »
# Usage : run_indexer.sh /dossier1 [/dossier2 …]

DIR="$HOME/photo_indexer"

# Homebrew dans le PATH (Mac Apple Silicon ou Intel)
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [ -x "$b" ] && eval "$("$b" shellenv)" && break
done

# commande ollama fournie par l'appli si elle n'est pas dans le PATH
command -v ollama >/dev/null 2>&1 || PATH="$PATH:/Applications/Ollama.app/Contents/Resources"

# Réglages (modèle, workers, conteneurs à mettre en pause)
MODEL="gemma4:26b"; WORKERS=1; PAUSE_CONTAINERS=""
[ -f "$DIR/config.sh" ] && source "$DIR/config.sh"

source "$DIR/venv/bin/activate" || { echo "Environnement Python introuvable : relance l'installateur."; exit 1; }

# ── Remise en état à la sortie (posée AVANT toute mise en pause) ─────────────
PAUSED=()
WATCH_PID=""
nettoyer() {
  [ -n "$WATCH_PID" ] && kill "$WATCH_PID" 2>/dev/null
  ollama stop "$MODEL" >/dev/null 2>&1 && echo "Modèle déchargé : $MODEL"
  for c in "${PAUSED[@]}"; do docker unpause "$c" >/dev/null 2>&1 && echo "Conteneur relancé : $c"; done
}
trap nettoyer EXIT
trap 'echo; echo "Interrompu. Relance le même dossier pour reprendre où tu t’es arrêté."; exit 130' INT TERM HUP

# ── Ollama doit répondre ──────────────────────────────────────────────────────
if ! curl -s -m 3 http://localhost:11434/api/tags >/dev/null; then
  echo "Démarrage d'Ollama…"
  if [ -d "/Applications/Ollama.app" ]; then open -a Ollama; else brew services start ollama >/dev/null 2>&1; fi
  for _ in $(seq 1 30); do curl -s -m 2 http://localhost:11434/api/tags >/dev/null && break; sleep 1; done
fi

# ── Libérer le GPU ────────────────────────────────────────────────────────────
for c in $PAUSE_CONTAINERS; do
  docker pause "$c" >/dev/null 2>&1 && PAUSED+=("$c") && echo "Conteneur en pause : $c"
done

# décharge tout modèle Ollama autre que celui de l'indexation (nom exact)
decharger_autres() {
  ollama ps 2>/dev/null | awk 'NR>1 {print $1}' | while read -r m; do
    [ "$m" = "$MODEL" ] || [ "$m" = "$MODEL:latest" ] && continue
    ollama stop "$m" >/dev/null 2>&1 && echo "$1$m"
  done
}
decharger_autres "Modèle déchargé : "

# filet de sécurité : un client non mis en pause peut recharger un modèle en cours de lot
( while sleep 20; do decharger_autres "Modèle rechargé par un autre logiciel, déchargé : "; done ) &
WATCH_PID=$!

# autres moteurs d'IA locaux hors Ollama : simple avertissement
pgrep -qif "LM Studio" && echo "⚠ LM Studio est ouvert : il peut occuper la puce graphique."

# ── Indexation, un dossier après l'autre ─────────────────────────────────────
for dossier in "$@"; do
  echo; echo "=== $dossier ==="
  caffeinate -i python "$DIR/photo_indexer.py" "$dossier" --model "$MODEL" --workers "$WORKERS"
done

osascript -e 'display notification "Indexation terminée" with title "Indexer photos" sound name "Glass"' 2>/dev/null
echo; echo "=== Terminé. Tu peux fermer cette fenêtre. ==="
