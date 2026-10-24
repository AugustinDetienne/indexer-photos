#!/usr/bin/env python3
"""
photo_indexer.py — Indexation automatique de photos par IA locale (Ollama)
Génère des mots-clés en français et les écrit dans les métadonnées IPTC/XMP,
lisibles par Lightroom, Bridge, Capture One.

  - JPG / TIFF / DNG : mots-clés écrits DANS le fichier (IPTC + XMP)
  - RAW (NEF, CR2, CR3, ARW, RAF, ORF, RW2) : sidecar .xmp à côté du fichier,
    comme le fait Lightroom ; le RAW lui-même n'est jamais modifié
  - Additif    : les mots-clés existants sont conservés, pas de doublons
  - Reprise    : un fichier d'état permet de relancer après interruption

Installé et configuré par « Installer Indexer photos.command ».

Usage :
  python photo_indexer.py /dossier --dry-run --limit 20     # test sans rien écrire
  python photo_indexer.py /dossier --limit 50               # test réel sur 50 images
  python photo_indexer.py /dossier                          # tout le dossier
  python photo_indexer.py /dossier --model gemma4:26b       # préciser le modèle
  python photo_indexer.py /dossier --reset                  # repartir de zéro
"""

from __future__ import annotations   # compatibilité Python 3.9 (macOS)

import argparse
import base64
import os
import re
import io
import json
import logging
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

try:
    from PIL import Image
    from tqdm import tqdm
except ImportError as e:
    print(f"[ERREUR] Module manquant : {e}")
    print("Installe les dépendances : pip install pillow tqdm")
    sys.exit(1)

# ─── Configuration ────────────────────────────────────────────────────────────

DEFAULT_MODEL = "gemma4:26b"      # vérifier le nom exact avec : ollama list
OLLAMA_URL = "http://localhost:11434"

IMAGE_EXT = {".jpg", ".jpeg", ".tif", ".tiff"}             # lus par Pillow, écrits dedans
RAW_EXT = {".nef", ".cr2", ".cr3", ".arw", ".raf", ".orf", ".rw2", ".dng"}  # aperçu via exiftool
EMBED_EXT = IMAGE_EXT | {".dng"}   # Lightroom lit les métadonnées DANS les DNG, pas de sidecar
SUPPORTED_EXT = IMAGE_EXT | RAW_EXT

PREVIEW_MAX_PX = 1024   # côté long de l'aperçu envoyé au modèle
PREVIEW_QUALITY = 85
NUM_CTX = 8192          # contexte du modèle : largement suffisant (prompt + image + réponse)
                        # et beaucoup moins gourmand en mémoire que le défaut (jusqu'à 256K)
REQUEST_TIMEOUT = 300   # secondes par image (le 1er appel charge le modèle)
STATE_FILE = ".photo_indexer_state.jsonl"

SYSTEM_PROMPT = """Tu es un documentaliste photo professionnel.
Tu indexes des photographies (numériques ou scans d'argentique, couleur et noir et blanc)
pour une recherche dans Lightroom. Tu réponds UNIQUEMENT en JSON valide."""

USER_PROMPT = """Analyse cette photographie et donne entre 6 et {n} mots-clés en français,
du plus important au moins important. Pas de remplissage : chaque mot-clé doit pouvoir
servir à retrouver cette image parmi des milliers.

À couvrir, dans cet ordre de priorité :
1. sujets visibles : personnes (nombre, genre apparent), objets, animaux, éléments
   du paysage (phare, arbre, immeubles…) ;
2. actions et gestes visibles : étreinte, sourire, danse, baignade, regard caméra, profil ;
3. lieu ou type de lieu (une ville seulement si elle est clairement reconnaissable) ;
4. activité ou événement (mariage, séance studio, voyage…) ;
5. cadrage seulement s'il est marquant : gros plan, vue aérienne, portrait, photo de groupe ;
6. une émotion ou atmosphère seulement si elle est évidente (joie, tendresse, contemplation) ;
7. toujours « noir et blanc » ou « couleur » ;
8. si ce n'est pas une photo directe : nature de l'image (reproduction de tableau,
   tirage photographié, document, charte colorimétrique) ET ce que l'œuvre représente.

Vêtements : seulement s'ils sont distinctifs (robe de mariée, costume, uniforme, salopette),
jamais les tenues ordinaires (t-shirt, débardeur, pantalon).

Interdits :
- ne nomme aucune personne ;
- pas d'époque ni de décennie, pas de « style argentique » (la date réelle est connue) ;
- pas de lien supposé entre personnes (famille, couple, amis, collègues) ;
- pas de genre artistique non évident (nature morte, portrait de famille…) ;
- pas de termes techniques vagues : « plan moyen », « plan large », « composition centrée »,
  « lumière naturelle », « couleur dominante ».
Mots-clés en minuscules, 1 à 3 mots chacun. N'invente rien qui ne soit pas visible.

Format exact :
{{"keywords": ["...", "..."], "description": "Une phrase décrivant l'image."}}"""

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("photo_indexer")

# ─── Vérifications ────────────────────────────────────────────────────────────

def check_exiftool() -> bool:
    try:
        r = subprocess.run(["exiftool", "-ver"], capture_output=True, text=True)
        log.info(f"exiftool v{r.stdout.strip()} détecté.")
        return True
    except FileNotFoundError:
        log.error("exiftool introuvable. Installe-le : brew install exiftool")
        return False


def check_ollama(model: str) -> bool:
    try:
        with urllib.request.urlopen(f"{OLLAMA_URL}/api/tags", timeout=10) as r:
            tags = json.load(r)
    except (urllib.error.URLError, OSError):
        log.error("Ollama ne répond pas sur localhost:11434. Lance l'application Ollama "
                  "(ou : brew services start ollama).")
        return False
    names = [m["name"] for m in tags.get("models", [])]
    if not any(n == model or n.split(":")[0] == model or n.startswith(model + ":") for n in names):
        log.error(f"Modèle « {model} » absent. Modèles installés : {', '.join(names) or 'aucun'}")
        log.error(f"Installe-le avec : ollama pull {model}")
        return False
    log.info(f"Ollama OK, modèle « {model} » disponible.")
    return True

# ─── Préparation de l'image ───────────────────────────────────────────────────

def extract_raw_preview(path: Path) -> bytes | None:
    """Extrait le JPEG embarqué d'un RAW (pas de dématriçage, rapide)."""
    for tag in ("-JpgFromRaw", "-PreviewImage", "-OtherImage"):
        r = subprocess.run(["exiftool", "-b", tag, str(path)], capture_output=True)
        if r.returncode == 0 and len(r.stdout) > 1000:
            return r.stdout
    return None


def make_preview(path: Path) -> str:
    """Retourne un JPEG réduit, encodé en base64."""
    if path.suffix.lower() in RAW_EXT:
        data = extract_raw_preview(path)
        if data is None:
            raise ValueError("aucun aperçu JPEG embarqué dans le RAW")
        img = Image.open(io.BytesIO(data))
    else:
        img = Image.open(path)
    img.draft("RGB", (PREVIEW_MAX_PX, PREVIEW_MAX_PX))  # accélère les gros JPEG
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")                          # TIFF 16 bits, CMJN…
    img.thumbnail((PREVIEW_MAX_PX, PREVIEW_MAX_PX))
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "JPEG", quality=PREVIEW_QUALITY)
    return base64.b64encode(buf.getvalue()).decode()

# ─── Appel au modèle ──────────────────────────────────────────────────────────

THINK_SUPPORTED = True   # passe à False si le modèle refuse le paramètre "think"


def _post_chat(payload: dict) -> dict:
    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/chat",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as r:
        return json.load(r)


def ask_model(image_b64: str, model: str, n: int) -> dict:
    global THINK_SUPPORTED
    payload = {
        "model": model,
        "stream": False,
        "format": "json",
        "keep_alive": "30m",
        "options": {"temperature": 0.2, "num_predict": 400, "num_ctx": NUM_CTX},
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": USER_PROMPT.format(n=n), "images": [image_b64]},
        ],
    }
    if THINK_SUPPORTED:
        payload["think"] = False   # coupe le raisonnement interne : beaucoup plus rapide
    try:
        resp = _post_chat(payload)
    except urllib.error.HTTPError as e:
        if THINK_SUPPORTED and e.code == 400:
            THINK_SUPPORTED = False          # modèle sans mode « thinking »
            payload.pop("think", None)
            resp = _post_chat(payload)
        else:
            raise
    content = resp["message"]["content"]
    data = json.loads(content)
    raw = data.get("keywords", [])
    if isinstance(raw, str):                     # certains modèles renvoient une chaîne
        raw = raw.split(",")
    kws = clean_keywords(raw, n)
    desc = clean_description(data.get("description", ""))
    return {"keywords": kws, "description": desc}


def ask_model_checked(image_b64: str, model: str, n: int) -> dict:
    """Interroge le modèle ; refait une demande si la réponse est vide ou trop pauvre."""
    last_err = None
    for _ in range(2):
        try:
            res = ask_model(image_b64, model, n)
            if len(res["keywords"]) >= 3 and res["description"]:
                return res
            last_err = ValueError(f"réponse trop pauvre : {res}")
        except (json.JSONDecodeError, KeyError) as e:
            last_err = ValueError(f"réponse illisible du modèle : {e}")
    if 'res' in locals() and res["keywords"]:
        return res                               # mieux que rien après deux essais
    raise last_err

# ─── Nettoyage des mots-clés ──────────────────────────────────────────────────
# Filet de sécurité appliqué quel que soit le modèle : certains respectent mal
# les consignes du prompt (vêtements, anglais, mots-clés fusionnés…).

TRADUCTIONS = {
    "turtleneck": "col roulé", "sweater": "pull", "hoodie": "sweat à capuche",
    "wedding": "mariage", "bride": "mariée", "groom": "marié", "beach": "plage",
    "sea": "mer", "portrait photo": "portrait", "black and white": "noir et blanc",
    "colour": "couleur", "color": "couleur", "ceremonie": "cérémonie",
    "reproduction tableau": "reproduction de tableau", "main jointe": "mains jointes",
    "colorchecker": "charte colorimétrique",
}
VETEMENTS_ORDINAIRES = (
    "t-shirt", "tee-shirt", "tshirt", "débardeur", "pantalon", "jean", "sweat", "tunique",
    "pull", "top ", "short", "chaussure", "basket", "chaussette", "maillot", "chemise",
    "veste", "blouson", "gilet", "legging", "jupe", "polo",
)
COULEURS = {
    "noir", "blanc", "gris", "bleu", "rose", "beige", "rouge", "vert", "jaune", "marron",
    "orange", "violet", "doré", "argenté", "noire", "blanche", "grise", "bleue", "verte",
}
TERMES_VAGUES = {
    "plan moyen", "plan large", "plan américain", "composition centrée", "lumière naturelle",
    "couleur dominante", "style argentique", "argentique", "photographie argentique",
    "photographie", "photo", "image", "social media", "réseaux sociaux", "extérieur jour",
}


def clean_keywords(raw, n: int) -> list[str]:
    out = []
    for k in raw:
        k = str(k).strip().lower().strip(".;:!?\"'«»“”[](){}#*- ")
        k = re.sub(r"\s+", " ", k)
        k = TRADUCTIONS.get(k, k)
        if not k or len(k) < 2:
            continue
        if ":" in k or "description" in k or len(k.split()) > 4:   # fuite de format, fusion
            continue
        if re.search(r"\b(années|siècle|époque|vintage|rétro)\b|\b1[89]\d0s?\b", k):
            continue                                   # pas de datation devinée
        if k in COULEURS or k in TERMES_VAGUES:
            continue
        if k.startswith(VETEMENTS_ORDINAIRES) and "mariée" not in k:
            continue
        if k not in out:
            out.append(k[:64])                         # IPTC limite à 64 caractères
    return out[:n]


def clean_description(d) -> str:
    d = str(d or "").strip().strip('"').strip()
    if d and d[-1] not in ".!?":
        d += "."
    return d[:2000]

# ─── Écriture des métadonnées ─────────────────────────────────────────────────

def write_metadata(path: Path, kws: list[str], desc: str) -> None:
    args = ["exiftool", "-q", "-m", "-overwrite_original", "-charset", "iptc=UTF8",
            "-IPTC:CodedCharacterSet=UTF8"]
    for k in kws:
        # retirer puis ajouter = ajout sans doublon, existants conservés
        args += [f"-XMP-dc:Subject-={k}", f"-XMP-dc:Subject+={k}"]
        if path.suffix.lower() in EMBED_EXT:
            args += [f"-IPTC:Keywords-={k}", f"-IPTC:Keywords+={k}"]
    if desc:
        # « -TAG-= » vide puis « -TAG=x » : n'écrit que si aucune légende n'existe déjà
        args += ["-XMP-dc:Description-=", f"-XMP-dc:Description={desc}"]

    if path.suffix.lower() not in EMBED_EXT:
        sidecar = path.with_suffix(".xmp")
        if sidecar.exists():
            target = [str(sidecar)]
        else:
            # crée le sidecar à partir du RAW sans toucher au RAW
            target = ["-o", str(sidecar), str(path)]
            args = [a for a in args if a != "-overwrite_original"]
    else:
        target = [str(path)]

    r = subprocess.run(args + target, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"exiftool : {r.stderr.strip()[:300]}")

# ─── État / reprise ───────────────────────────────────────────────────────────

class State:
    def __init__(self, root: Path, reset: bool):
        self.file = root / STATE_FILE
        self.lock = threading.Lock()
        if reset and self.file.exists():
            self.file.unlink()
        self.done = set()
        if self.file.exists():
            for line in self.file.read_text(encoding="utf-8").splitlines():
                try:
                    self.done.add(json.loads(line)["path"])
                except (json.JSONDecodeError, KeyError):
                    pass

    def mark(self, path: Path, result: dict) -> None:
        with self.lock, self.file.open("a", encoding="utf-8") as f:
            f.write(json.dumps({"path": str(path), **result}, ensure_ascii=False) + "\n")

# ─── Pipeline ─────────────────────────────────────────────────────────────────

def collect_images(root: Path) -> list[Path]:
    return sorted(
        p for p in root.rglob("*")
        if p.is_file() and p.suffix.lower() in SUPPORTED_EXT and not p.name.startswith("._")
    )


def process_one(path: Path, model: str, n: int, dry_run: bool) -> dict:
    t0 = time.time()
    result = ask_model_checked(make_preview(path), model, n)
    if not dry_run:
        write_metadata(path, result["keywords"], result["description"])
    result["seconds"] = round(time.time() - t0, 1)
    return result


def main():
    ap = argparse.ArgumentParser(description="Indexation photo par IA locale (Ollama)")
    ap.add_argument("folder", type=Path)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--max-keywords", type=int, default=10)
    ap.add_argument("--workers", type=int, default=2, help="2 = optimum mesuré sur Mac Studio M4 Max")
    ap.add_argument("--limit", type=int, default=0, help="ne traiter que N images (test)")
    ap.add_argument("--dry-run", action="store_true", help="affiche sans rien écrire")
    ap.add_argument("--reset", action="store_true", help="ignore les images déjà traitées")
    ap.add_argument("--preview-px", type=int, default=PREVIEW_MAX_PX,
                    help="taille de l'aperçu envoyé au modèle (plus petit = plus rapide)")
    ap.add_argument("--num-ctx", type=int, default=NUM_CTX,
                    help="taille du contexte du modèle (défaut 8192 ; plus petit = moins de mémoire)")
    a = ap.parse_args()
    globals()["PREVIEW_MAX_PX"] = a.preview_px
    globals()["NUM_CTX"] = a.num_ctx

    root = a.folder.expanduser().resolve()
    if not root.is_dir():
        sys.exit(f"Dossier introuvable : {root}")
    if not (check_exiftool() and check_ollama(a.model)):
        sys.exit(1)

    try:
        state = State(root, a.reset)
        images = [p for p in collect_images(root) if a.dry_run or str(p) not in state.done]
    except PermissionError as e:
        log.error(f"macOS empêche le Terminal de lire ce dossier ({e.filename}).")
        log.error("Réglages Système > Confidentialité et sécurité > Accès complet au disque : "
                  "active « Terminal », quitte-le (⌘Q), puis relance.")
        sys.exit(1)
    if a.limit:
        images = images[: a.limit]
    log.info(f"{len(images)} image(s) à traiter ({len(state.done)} déjà faites).")
    if not images:
        return

    ok = err = 0
    durations = []
    t_start = time.time()
    pool = ThreadPoolExecutor(max_workers=a.workers)
    bar = tqdm(total=len(images), unit="img")
    try:
        futures = {pool.submit(process_one, p, a.model, a.max_keywords, a.dry_run): p for p in images}
        for fut in as_completed(futures):
            p = futures[fut]
            try:
                res = fut.result()
                ok += 1
                durations.append(res["seconds"])
                if a.dry_run:
                    tqdm.write(f"\n{p.name}  ({res['seconds']} s)\n  {res['description']}\n  → {', '.join(res['keywords'])}")
                else:
                    state.mark(p, res)
            except Exception as e:  # une image en erreur ne bloque pas le lot
                err += 1
                tqdm.write(f"[ERREUR] {p} : {e}")
            bar.update(1)
    except KeyboardInterrupt:
        bar.close()
        pool.shutdown(wait=False, cancel_futures=True)
        print(f"\nInterrompu après {ok} image(s). Relance le même dossier pour reprendre "
              f"là où tu t'es arrêté : les images déjà faites seront ignorées.", flush=True)
        os._exit(130)   # sortie immédiate, sans attendre les requêtes en cours
    bar.close()
    pool.shutdown(wait=True)

    if durations:
        moy = sum(durations) / len(durations)
        debit = (time.time() - t_start) / ok          # temps réel par image, tous workers confondus
        log.info(f"Terminé : {ok} OK, {err} erreur(s). {moy:.1f} s par requête, "
                 f"débit réel {debit:.2f} s/image ({a.workers} worker(s)) "
                 f"→ environ {debit * 10_000 / 3600:.1f} h pour 10 000 images.")


if __name__ == "__main__":
    main()
