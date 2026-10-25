<p align="center"><img src="fichiers/icone.png" width="140" alt="Indexer photos"></p>

<h1 align="center">Indexer photos</h1>

Je suis photographe. Comme beaucoup d'entre vous, j'ai accumulé des centaines de milliers d'images qu'il est impossible de retrouver faute de mots-clés. Les services en ligne existent, mais ils supposent d'envoyer ses photos sur des serveurs inconnus, et souvent de payer un abonnement.

J'ai donc construit **Indexer photos**, un outil gratuit et open source pour Mac. Une IA qui tourne **entièrement sur votre ordinateur** regarde chaque photo et écrit des mots-clés en français et une courte description. Ils sont lisibles directement dans Lightroom, Bridge ou Capture One.

L'outil donne le meilleur de lui-même **au fil de l'eau** : on glisse le dossier d'une séance ou d'un reportage sur l'icône, et quelques minutes à une heure plus tard selon le Mac, les mots-clés sont là. Pour cataloguer d'un coup une très grosse banque d'images, il faut de la patience. Comptez quelques nuits sur un Mac puissant, et plusieurs semaines sur un Mac de 16 Go : à ce rythme-là, mieux vaut avancer par étapes.

L'outil restera gratuit. S'il vous fait gagner des heures de catalogage, ou si vous avez enfin retrouvé une photo perdue depuis des années, vous pouvez [m'offrir un café sur Ko-fi](https://ko-fi.com/AugustinDetienne). Chaque contribution m'aide à l'améliorer : version anglaise, nouveaux réglages, compatibilité avec de nouveaux modèles.

Merci, et bon catalogage !

<p align="center"><a href="https://ko-fi.com/AugustinDetienne"><img src="https://img.shields.io/badge/Soutenir%20le%20projet-Ko--fi-FF5E5B?logo=ko-fi&logoColor=white" alt="Soutenir sur Ko-fi"></a> <img src="https://img.shields.io/badge/licence-GPL--3.0-blue" alt="Licence GPL-3.0"> <img src="https://img.shields.io/badge/macOS%2014%2B-Apple%20Silicon-black?logo=apple" alt="macOS 14+ Apple Silicon"></p>

> **English summary** — Free, fully local AI keywording for photographers on macOS 14+ (Apple Silicon). A vision model running in [Ollama](https://ollama.com) looks at each image and writes 6–10 **French** keywords plus a one-sentence description into IPTC/XMP metadata (embedded in JPG/TIFF/DNG, `.xmp` sidecars for RAW files). Additive, resumable, no image ever leaves your Mac. One-click installer, drag-and-drop Dock app. GPL-3.0.

---

## Ce que ça fait

- **100 % local** : aucune image ne quitte votre Mac, aucun abonnement, aucun compte.
- **6 à 10 mots-clés en français** et une phrase de description par image, pensés pour la recherche dans Lightroom (sujets, gestes, lieu, événement, noir et blanc ou couleur, reproductions d'œuvres…).
- **JPG, TIFF, DNG** : métadonnées écrites dans le fichier. **RAW** (NEF, CR2, CR3, ARW, RAF, ORF, RW2) : fichier `.xmp` à côté, comme Lightroom ; le RAW n'est jamais modifié.
- **Additif** : les mots-clés existants sont conservés, une légende existante n'est jamais remplacée.
- **Reprise** : on peut interrompre à tout moment ; relancer le même dossier reprend là où on s'était arrêté.
- **Prudent** : l'IA ne nomme jamais les personnes, ne devine ni l'époque ni les liens entre les gens ; un filtre retire le remplissage (vêtements ordinaires, mots anglais, datations, termes vagues).
- **Appli du Dock** : glissez un dossier sur l'icône, c'est tout.

## Configuration requise

| Mémoire du Mac | Mode | Modèle | Qualité | Vitesse mesurée |
|---|---|---|---|---|
| 32 Go et plus | standard | `gemma4:26b` (18 Go) | très bonne | ~1 s / image (Mac Studio M4 Max) |
| 16 à 31 Go | léger | `qwen3-vl:8b-instruct` (6 Go) | bonne, quelques erreurs | ~3,5 s (M4 Max) à ~11 s (MacBook Pro M2 Pro 16 Go) |
| moins de 16 Go | déconseillé | | | |

- Mac **Apple Silicon** (M1 ou plus récent) sous **macOS 14 Sonoma ou plus récent** (exigence d'Ollama). Sur Intel : possible mais très lent (pas d'accélération graphique).
- 30 Go d'espace libre (mode standard) ou 15 Go (mode léger), connexion internet pendant l'installation.

L'installateur choisit le mode automatiquement selon la mémoire.

## Installation

1. Téléchargez **`Indexer photos - installation.zip`** dans la page [Releases](../../releases/latest) et décompressez-le (laissez tous les fichiers ensemble).
2. Ouvrez le **Terminal** (Applications > Utilitaires).
3. Tapez `bash` suivi d'un espace, glissez **« Installer Indexer photos.command »** dans la fenêtre, puis Entrée.
4. Répondez aux questions (10 à 30 minutes, surtout le téléchargement du modèle).

L'installateur met en place Homebrew, exiftool, Python 3.13, Ollama, le modèle d'IA, le script et l'application avec son icône. Il peut être relancé sans risque pour réparer ou mettre à jour ; vos réglages sont conservés.

> **macOS bloque l'installateur ?** Le double-clic déclenche souvent Gatekeeper : utilisez la méthode `bash` ci-dessus. Si l'installateur indique que « macOS empêche le Terminal de lire », activez le Terminal dans *Réglages Système > Confidentialité et sécurité > Accès complet au disque*, quittez-le (⌘Q) et relancez.

## Utilisation

- Glissez un ou plusieurs dossiers sur l'icône **Indexer photos** (Dock ou Applications), ou double-cliquez dessus pour choisir.
- Une fenêtre Terminal affiche la progression ; une notification signale la fin.
- **Dans Lightroom** : les nouvelles photos arrivent avec leurs mots-clés ; pour des photos déjà cataloguées, *Métadonnées > Lire les métadonnées à partir des fichiers*.

Pendant l'indexation, les autres modèles chargés dans Ollama sont déchargés, et les conteneurs Docker listés dans `PAUSE_CONTAINERS` sont mis en pause puis relancés à la fin.

### ⚠️ Précautions

- Le script **écrit dans vos fichiers** : travaillez sur des photos sauvegardées ailleurs, et faites d'abord un essai sur un dossier de **copies**.
- Les mots-clés sont proposés par une IA : fiables dans l'ensemble, pas infaillibles.

## Réglages

`~/photo_indexer/config.sh` :

| Variable | Rôle |
|---|---|
| `MODEL` | modèle Ollama (`gemma4:26b` ou `qwen3-vl:8b-instruct`) |
| `WORKERS` | requêtes simultanées (2 à partir de 64 Go de mémoire, sinon 1) |
| `PAUSE_CONTAINERS` | conteneurs Docker à mettre en pause pendant l'indexation |

En ligne de commande :

```bash
cd ~/photo_indexer && source venv/bin/activate
python photo_indexer.py ~/Pictures/essai --dry-run --limit 20   # aperçu, n'écrit rien
python photo_indexer.py ~/Pictures/essai --reset                # retraiter tout le dossier
```

Options : `--model`, `--workers`, `--max-keywords` (10), `--preview-px` (1024), `--num-ctx` (8192), `--limit`, `--dry-run`, `--reset`.

## Désinstallation

Même méthode que l'installation, avec **« Désinstaller Indexer photos.command »**. Les mots-clés déjà écrits dans les photos restent en place.

## Soutenir le projet

Indexer photos est gratuit. S'il vous fait gagner des heures de catalogage, vous pouvez soutenir son développement :

<a href="https://ko-fi.com/AugustinDetienne"><img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Soutenir sur Ko-fi"></a>

## Signaler un problème

Les retours sont bienvenus dans les [Issues](../../issues) : modèle de Mac, mémoire, mode utilisé et message d'erreur. Les contributions de code ne sont pas acceptées pour le moment.

## Licence

Code sous licence **[GPL-3.0](LICENSE)** © 2026 Augustin Détienne. Vous pouvez utiliser, modifier et redistribuer ce logiciel, y compris pour un usage professionnel ; toute version modifiée et redistribuée doit rester sous GPL-3.0, avec son code source.

Les modèles d'IA ne sont pas inclus : Ollama les télécharge sur votre Mac. Ils restent soumis à leurs propres licences (Apache 2.0 pour `gemma4` comme pour `qwen3-vl`, à vérifier sur la fiche de chaque modèle). Homebrew, exiftool, Python, Pillow, tqdm et Ollama sont installés depuis leurs sources officielles, sous leurs licences respectives.
