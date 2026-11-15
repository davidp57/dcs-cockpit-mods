"""Builds the Open Mod Manager packages of this repository, for the "Game files" channel.

Two packages:
- hook: Cockpit_Mods_Hook_v<version>.ozp, the shared hook. It holds COCKPIT_MODS/_loader.lua
  and a full copy of the DCS file KNEEBOARD/declare_kneeboard_device.lua with one line
  added, since Open Mod Manager can only replace whole files (it backs up the original and
  puts it back on uninstall). The kneeboard file is taken from the DCS install given, so the
  package matches that DCS version: rebuild it after a DCS update that changes the file.
- cycles: Cockpit_Cycles_v<version>.ozp, the cockpit cycles, with one config per aircraft
  (AH-64D so far). It needs the hook package.

Each package also holds modpack.xml and readme.md, as Open Mod Manager expects.

Usage: python tools/build_omm.py hook|cycles VERSION [DCS path] [output folder]
       python tools/build_omm.py hook 1.0.0 "C:/jeux/DCS World" dist
"""

import re
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

REPO = Path(__file__).resolve().parent.parent
COCKPIT = Path("Scripts/Aircrafts/_Common/Cockpit")
KNEEBOARD = COCKPIT / "KNEEBOARD" / "declare_kneeboard_device.lua"

# The line added to the kneeboard file. pcall: a missing or broken hook must not take the
# module's other devices down with it.
HOOK_LINE = (
    'do local ok, err = pcall(dofile, LockOn_Options.common_script_path.."COCKPIT_MODS/_loader.lua") '
    'if not ok and print then print("COCKPIT_MODS: hook failed: "..tostring(err)) end end'
)
MARKER = "COCKPIT-MODS"
# Blocks left in the kneeboard file by development installs, stripped from the copy.
DEV_MARKERS = (MARKER, "IFR-CURTAIN")

CATEGORY = "COMMUN - Amélioration"

PACKAGES = {
    "hook": {
        "name": "Cockpit_Mods_Hook",
        "source": REPO / "hook" / "mod",
        "kneeboard": True,
        "description": """Accroche partagée des mods de cockpit (rideau IFR, cycles de cockpit…) : permet à plusieurs mods de déclarer leurs équipements sans remplacer chacun le même fichier de DCS.

Seul, ce paquet ne fait rien ; il est demandé par les mods qui s'en servent.

Remplace Scripts\\Aircrafts\\_Common\\Cockpit\\KNEEBOARD\\declare_kneeboard_device.lua (une ligne ajoutée) : à reconstruire si une mise à jour de DCS modifie ce fichier. Ne passe pas l'IC.""",
        "readme": """# Cockpit mods hook

Accroche partagée des mods de cockpit pour DCS World.
Elle ajoute une ligne au fichier du kneeboard, chargé par la plupart des modules, qui lit le dossier `Scripts\\Aircrafts\\_Common\\Cockpit\\COCKPIT_MODS` : chaque mod y dépose son fichier de déclaration.
Plusieurs mods peuvent ainsi ajouter leurs équipements, alors qu'Open Mod Manager ne laisse qu'un paquet remplacer le fichier du kneeboard.

- Seule, elle ne fait rien.
- Remplace `declare_kneeboard_device.lua` (une ligne ajoutée) : à reconstruire si une mise à jour de DCS modifie ce fichier.
- Ne passe pas l'IC : solo et serveurs qui ne vérifient pas les scripts.
- Ce qu'elle charge est écrit dans `dcs.log`, lignes `COCKPIT_MODS`.
""",
    },
    "cycles": {
        "name": "Cockpit_Cycles",
        "source": REPO / "cycles" / "mod",
        "kneeboard": False,
        "description": """Cycles de cockpit : un seul bouton du HOTAS fait défiler plusieurs boutons du cockpit (les pages d'un écran, par exemple), et un appui long peut aller directement sur l'un d'eux.

Avions pris en charge : AH-64D (pages des deux MPD : FCR, WPN, TSD, VID, ENG, ASE ; appui long sur l'une d'elles).

Demande le paquet Cockpit_Mods_Hook (« game files »). Touches : fournies par Custom_Keybinds (« user files »), avec Quaggles Injector (« game files »). Ne passe pas l'IC.

Source et documentation : https://github.com/davidp57/dcs-cockpit-mods""",
        "readme": """# Cockpit cycles

Un seul bouton du HOTAS fait défiler plusieurs boutons du cockpit (les pages d'un écran, par exemple), et un appui long (0,5 s) peut aller directement sur l'un d'eux.

Avions pris en charge :

- AH-64D, catégorie « MPD page cycles » : chaque MPD fait défiler FCR, WPN, TSD, VID, ENG, ASE (ENG et ASE par le menu M). Sept commandes par MPD : « Left MPD: next page » (la page change dès l'appui), et « Left MPD: next page, hold FCR » (ou WPN, TSD, VID, ENG, ASE) où un appui long va directement sur cette page. Même chose pour « Right MPD ». Pilote et tireur. Demande Custom_Keybinds du 2026-11-15 ou plus récent.

Pour tous :

- On choisit l'action de l'appui long en assignant la commande correspondante, sans fichier à modifier.
- Demande le paquet Cockpit_Mods_Hook ; commandes fournies par le paquet Custom_Keybinds avec Quaggles Injector.
- Chaque appui est écrit dans `dcs.log`, lignes `COCKPIT_CYCLES`.
- Ne passe pas l'IC : solo et serveurs qui ne vérifient pas les scripts.

Source et documentation : https://github.com/davidp57/dcs-cockpit-mods
""",
    },
}


def pristine_kneeboard(dcs: Path) -> str:
    """The DCS kneeboard declaration, without any block left by a development install."""
    text = (dcs / KNEEBOARD).read_bytes().decode("utf-8")
    for marker in DEV_MARKERS:
        text = re.sub(rf"(?ms)^[ \t]*-- {marker} BEGIN.*?-- {marker} END[ \t]*(\r?\n|\Z)", "", text)
    return text


def hooked_kneeboard(text: str) -> str:
    nl = "\r\n" if "\r\n" in text else "\n"
    if not text.endswith("\n"):
        text += nl
    return text + f"-- {MARKER} BEGIN{nl}{HOOK_LINE}{nl}-- {MARKER} END{nl}"


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in PACKAGES:
        sys.exit(__doc__)
    package_info = PACKAGES[sys.argv[1]]
    version = sys.argv[2]
    dcs = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("C:/jeux/DCS World")
    out_dir = Path(sys.argv[4]) if len(sys.argv) > 4 else REPO / "dist"

    name = f"{package_info['name']}_v{version}"
    out_dir.mkdir(parents=True, exist_ok=True)
    package = out_dir / f"{name}.ozp"

    modpack = (
        "<Open_Mod_Manager_Package>\n"
        f"\t<install>{name}</install>\n"
        f"\t<category>{CATEGORY}</category>\n"
        f"\t<description>{escape(package_info['description'])}</description>\n"
        "</Open_Mod_Manager_Package>\n"
    )
    source = package_info["source"]
    with zipfile.ZipFile(package, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("modpack.xml", modpack.encode("utf-8"))
        z.writestr("readme.md", package_info["readme"].encode("utf-8"))
        for f in sorted(source.rglob("*")):
            if f.is_file():
                z.write(f, f"{name}/{f.relative_to(source).as_posix()}")
        if package_info["kneeboard"]:
            z.writestr(f"{name}/{KNEEBOARD.as_posix()}", hooked_kneeboard(pristine_kneeboard(dcs)).encode("utf-8"))

    print(f"Written: {package}")
    with zipfile.ZipFile(package) as z:
        for n in z.namelist():
            print("  ", n)


if __name__ == "__main__":
    main()
