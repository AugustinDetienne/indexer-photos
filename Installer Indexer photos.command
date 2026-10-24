#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
#  Installer Indexer photos
#  Indexation automatique de photos par IA locale (Ollama + Gemma 4)
#  Mots-clés en français écrits en IPTC/XMP, lisibles par Lightroom.
#  Peut être relancé sans risque : il complète ou met à jour ce qui manque.
# ════════════════════════════════════════════════════════════════════════════

set -u
KIT="$(cd "$(dirname "$0")" && pwd)"
SRC="$KIT/fichiers"
cd "$HOME" || cd /   # le dossier courant peut avoir été supprimé (ex. ~/photo_indexer)
DIR="$HOME/photo_indexer"
MODEL_STANDARD="gemma4:26b"           # Mac de 32 Go et plus
MODEL_LEGER="qwen3-vl:8b-instruct"     # mode léger : Mac de 16 à 31 Go
APP_NAME="Indexer photos"

vert()  { printf "\033[32m✔ %s\033[0m\n" "$*"; }
jaune() { printf "\033[33m! %s\033[0m\n" "$*"; }
rouge() { printf "\033[31m✘ %s\033[0m\n" "$*"; }
etape() { printf "\n\033[1;35m── %s\033[0m\n" "$*"; }
stop()  { rouge "$*"; echo; read -r -p "Appuie sur Entrée pour fermer." _; exit 1; }
oui()   { local r; read -r -p "$1 [o/N] " r; [[ "$r" =~ ^[oOyY] ]]; }

clear
printf "\033[1;35m📷  Installation d'Indexer photos\033[0m\n"
echo "Durée : 10 à 30 min selon la connexion (modèle d'IA de 6 à 18 Go selon le Mac)."
[ -d "$SRC" ] || stop "Dossier « fichiers » introuvable à côté de l'installateur. Décompresse tout le kit avant de lancer."

# macOS (confidentialité) peut interdire au Terminal de lire Téléchargements, Bureau, Documents…
acces_refuse() {
  rouge "macOS empêche le Terminal de lire : $1"
  echo "  Corrige-le une fois pour toutes (le Terminal servira aussi à lire tes dossiers de photos) :"
  echo "  1. Réglages Système > Confidentialité et sécurité > Accès complet au disque"
  echo "  2. Active « Terminal » (ajoute-le avec + s'il n'est pas listé : Applications > Utilitaires)"
  echo "  3. Quitte complètement le Terminal (⌘Q), rouvre-le et relance l'installateur."
  echo; read -r -p "Appuie sur Entrée pour fermer." _; exit 1
}
head -c 1 "$SRC/photo_indexer.py" >/dev/null 2>&1 || acces_refuse "$KIT"

# ── 1. Vérifications ──────────────────────────────────────────────────────────
etape "1/7  Vérification du Mac"
[ "$(uname)" = "Darwin" ] || stop "Cet installateur est réservé à macOS."

if [ "$(uname -m)" != "arm64" ]; then
  jaune "Mac Intel détecté : le modèle tournera très lentement (plusieurs dizaines de secondes par image)."
  oui "Continuer quand même ?" || exit 0
else
  vert "Mac Apple Silicon"
fi

RAM_GO=$(( $(sysctl -n hw.memsize) / 1073741824 ))
if [ "$RAM_GO" -ge 32 ]; then
  MODEL="$MODEL_STANDARD"; MODE="standard"; BESOIN_GO=30
  vert "Mémoire : ${RAM_GO} Go → mode standard ($MODEL)"
elif [ "$RAM_GO" -ge 16 ]; then
  MODEL="$MODEL_LEGER"; MODE="léger"; BESOIN_GO=15
  jaune "Mémoire : ${RAM_GO} Go → MODE LÉGER ($MODEL)."
  echo "  Le modèle standard demande 32 Go. Le mode léger fonctionne, mais :"
  echo "  • il est nettement plus lent (plusieurs secondes par image, davantage sur un petit Mac) ;"
  echo "  • les mots-clés sont un peu moins justes (quelques erreurs sur 20 images en test)."
  oui "Installer en mode léger ?" || exit 0
else
  jaune "Mémoire : ${RAM_GO} Go. C'est insuffisant : 16 Go minimum, 32 Go recommandés."
  oui "Essayer quand même en mode léger (déconseillé) ?" || exit 0
  MODEL="$MODEL_LEGER"; MODE="léger"; BESOIN_GO=15
fi
# réinstallation : on garde le modèle déjà choisi dans les réglages
if [ -f "$DIR/config.sh" ]; then
  ANCIEN=$(grep -E '^MODEL=' "$DIR/config.sh" | head -1 | cut -d'"' -f2)
  if [ -n "$ANCIEN" ] && [ "$ANCIEN" != "$MODEL" ]; then
    echo "  Réglages existants : modèle « $ANCIEN » conservé."
    MODEL="$ANCIEN"
  fi
fi
if [ "$RAM_GO" -ge 64 ]; then WORKERS=2; else WORKERS=1; fi

LIBRE_GO=$(df -g "$HOME" | awk 'NR==2 {print $4}')
if [ "${LIBRE_GO:-0}" -lt "$BESOIN_GO" ]; then
  jaune "Espace libre : ${LIBRE_GO} Go. Il en faut environ ${BESOIN_GO} Go."
  oui "Continuer quand même ?" || exit 0
else
  vert "Espace libre : ${LIBRE_GO} Go"
fi

# ── 2. Homebrew ───────────────────────────────────────────────────────────────
etape "2/7  Homebrew (gestionnaire de logiciels)"
BREW=""
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && BREW="$b" && break; done
if [ -z "$BREW" ]; then
  echo "Homebrew va être installé. Ton mot de passe de session sera demandé (rien ne s'affiche à la frappe, c'est normal)."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || stop "L'installation de Homebrew a échoué."
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && BREW="$b" && break; done
  [ -n "$BREW" ] || stop "Homebrew introuvable après installation."
fi
eval "$("$BREW" shellenv)"
LIGNE="eval \"\$($BREW shellenv)\""
grep -qsF "$LIGNE" "$HOME/.zprofile" || { echo "$LIGNE" >> "$HOME/.zprofile"; vert "Homebrew ajouté au profil du terminal"; }
vert "Homebrew $(brew --version | head -1 | awk '{print $2}')"

# ── 3. exiftool + Python ──────────────────────────────────────────────────────
etape "3/7  exiftool et Python"
brew install exiftool python@3.13 || stop "Installation d'exiftool / Python impossible."
PY="$(brew --prefix)/bin/python3.13"
[ -x "$PY" ] || stop "Python 3.13 introuvable ($PY)."
vert "exiftool $(exiftool -ver)"
vert "$("$PY" --version)"

# ── 4. Ollama ─────────────────────────────────────────────────────────────────
etape "4/7  Ollama (moteur d'IA locale)"
# appli Ollama déjà présente mais commande absente du terminal : on utilise celle de l'appli
OLLAMA_APP_BIN="/Applications/Ollama.app/Contents/Resources/ollama"
command -v ollama >/dev/null 2>&1 || { [ -x "$OLLAMA_APP_BIN" ] && export PATH="$PATH:$(dirname "$OLLAMA_APP_BIN")"; }
if command -v ollama >/dev/null 2>&1; then
  vert "Ollama déjà installé ($(ollama --version 2>/dev/null | awk '{print $NF}'))"
else
  brew install ollama || stop "Installation d'Ollama impossible."
  vert "Ollama installé"
fi
if ! curl -s -m 3 http://localhost:11434/api/tags >/dev/null; then
  echo "Démarrage d'Ollama…"
  if [ -d "/Applications/Ollama.app" ]; then open -a Ollama; else brew services start ollama >/dev/null; fi
  for _ in $(seq 1 30); do curl -s -m 2 http://localhost:11434/api/tags >/dev/null && break; sleep 1; done
fi
curl -s -m 3 http://localhost:11434/api/tags >/dev/null || stop "Ollama ne répond pas. Lance-le puis relance l'installateur."
vert "Ollama répond"

# ── 5. Modèle ─────────────────────────────────────────────────────────────────
etape "5/7  Modèle d'IA ($MODEL)"
if ollama list | awk 'NR>1 {print $1}' | grep -q "^${MODEL}"; then
  vert "Modèle déjà présent"
else
  echo "Téléchargement du modèle (6 à 18 Go). Ne ferme pas cette fenêtre."
  ollama pull "$MODEL" || stop "Téléchargement du modèle impossible. Vérifie le nom sur ollama.com/library"
  vert "Modèle téléchargé"
fi

# ── 6. Script + environnement Python ─────────────────────────────────────────
etape "6/7  Script d'indexation"
mkdir -p "$DIR"
# suppression préalable : un ancien fichier en lecture seule ou verrouillé ne bloque pas la mise à jour
chflags nouchg "$DIR/photo_indexer.py" "$DIR/run_indexer.sh" 2>/dev/null
rm -f "$DIR/photo_indexer.py" "$DIR/run_indexer.sh"
cp "$SRC/photo_indexer.py" "$SRC/run_indexer.sh" "$DIR/" || stop "Copie du script impossible dans $DIR."
chmod 644 "$DIR/photo_indexer.py"; chmod 755 "$DIR/run_indexer.sh"
grep -q "clean_keywords" "$DIR/photo_indexer.py" || stop "Le script installé n'est pas la bonne version."
vert "Script à jour"
if [ -f "$DIR/config.sh" ]; then
  vert "Réglages existants conservés ($DIR/config.sh)"
else
  sed -e "s/__WORKERS__/$WORKERS/" -e "s/__MODEL__/$MODEL/" "$SRC/config.sh" > "$DIR/config.sh"
  vert "Réglages créés (mode $MODE, modèle $MODEL, requêtes simultanées : $WORKERS)"
fi
if [ ! -x "$DIR/venv/bin/python" ] || ! "$DIR/venv/bin/python" -c 'import sys; sys.exit(sys.version_info < (3, 13))'; then
  rm -rf "$DIR/venv"
  "$PY" -m venv "$DIR/venv" || stop "Création de l'environnement Python impossible."
fi
"$DIR/venv/bin/python" -m pip install -q --upgrade pip pillow tqdm || stop "Installation de Pillow / tqdm impossible."
vert "Environnement Python prêt"

# ── 7. Application ────────────────────────────────────────────────────────────
etape "7/7  Application « $APP_NAME »"
if [ -w /Applications ]; then APPDIR="/Applications"; else APPDIR="$HOME/Applications"; mkdir -p "$APPDIR"; fi
APP="$APPDIR/$APP_NAME.app"
rm -rf "$APP"
osacompile -o "$APP" "$SRC/$APP_NAME.applescript" || stop "Création de l'application impossible."
# icône
cp "$SRC/applet.icns" "$APP/Contents/Resources/applet.icns"
rm -f "$APP/Contents/Resources/Assets.car"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$APP/Contents/Info.plist" >/dev/null 2>&1
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile applet" "$APP/Contents/Info.plist" >/dev/null 2>&1
# signature locale (requise après modification du paquet) + levée de la quarantaine
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || jaune "Signature locale impossible (l'appli devrait fonctionner quand même)."
xattr -dr com.apple.quarantine "$APP" 2>/dev/null
touch "$APP"
vert "Application créée : $APP"

if oui "Ajouter « $APP_NAME » au Dock ?"; then
  defaults write com.apple.dock persistent-apps -array-add \
    "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
  killall Dock
  vert "Ajoutée au Dock"
fi

# ── Test final ────────────────────────────────────────────────────────────────
etape "Test final"
TMP="$(mktemp -d)"
"$DIR/venv/bin/python" - "$TMP/test.jpg" <<'EOF'
import sys
from PIL import Image, ImageDraw
im = Image.new("RGB", (800, 600), (135, 190, 235))
d = ImageDraw.Draw(im)
d.rectangle([0, 420, 800, 600], fill=(60, 140, 70))
d.ellipse([560, 60, 700, 200], fill=(255, 215, 0))
d.rectangle([120, 280, 320, 440], fill=(200, 60, 50))
d.polygon([(100, 280), (220, 180), (340, 280)], fill=(120, 40, 30))
im.save(sys.argv[1])
EOF
echo "Analyse d'une image de test (le premier chargement du modèle peut prendre une minute)…"
if "$DIR/venv/bin/python" "$DIR/photo_indexer.py" "$TMP" --dry-run --model "$MODEL" --workers 1; then
  vert "L'indexation fonctionne"
else
  jaune "Le test a échoué : voir les messages ci-dessus."
fi
rm -rf "$TMP"

echo
printf "\033[1;32m🎉  Installation terminée\033[0m\n"
echo "• Glisse un dossier de photos sur l'icône « $APP_NAME » (ou double-clique dessus)."
echo "• Commence par un dossier de COPIES pour vérifier le résultat dans Lightroom."
echo "• Réglages : $DIR/config.sh"
echo
read -r -p "Appuie sur Entrée pour fermer." _
