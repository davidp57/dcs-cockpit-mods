# DCS cockpit mods

Mods de cockpit pour DCS World, et l'accroche qui leur permet de cohabiter :

- **l'accroche partagée** (`hook/`) : charge les mods de cockpit depuis un dossier commun, pour qu'ils ne remplacent pas chacun le même fichier de DCS ;
- **les cycles de commandes** (`cycles/`) : un seul bouton du HOTAS fait défiler plusieurs boutons du cockpit, avec une action différente pour un appui long.

Le [rideau IFR](https://github.com/davidp57/dcs-ifr-curtain) passe aussi par l'accroche, depuis sa version 2.0.

## L'accroche partagée

Un mod de cockpit déclare ses équipements (un `avLuaDevice`, un écran) dans le `device_init.lua` du module.
Le seul point d'entrée commun à la plupart des modules est `Scripts\Aircrafts\_Common\Cockpit\KNEEBOARD\declare_kneeboard_device.lua`, chargé par leur `device_init.lua`.
Open Mod Manager ne sait que remplacer des fichiers entiers, et un seul paquet peut remplacer un même fichier : deux mods qui ajoutent chacun leur ligne au fichier du kneeboard sont en conflit.

L'accroche est ce seul paquet.
Elle ajoute une ligne au fichier du kneeboard, qui exécute `COCKPIT_MODS\_loader.lua` ; celui-ci exécute chaque fichier du dossier `COCKPIT_MODS`, un par mod (`IFR_CURTAIN.lua`, `COCKPIT_CYCLES.lua`…).
Chaque mod décide lui-même s'il concerne l'avion chargé.
Un mod qui échoue est écrit dans `dcs.log` et n'empêche pas les autres de se charger ; la ligne du kneeboard est protégée de la même façon, pour qu'une accroche cassée ne prive pas le module de ses autres équipements.

Pour lister le dossier, il faut `lfs`, que rien ne garantit dans `device_init.lua` : aucun `device_init.lua` d'ED ne s'en sert (seuls des scripts d'écran et d'équipement le font).
L'accroche l'essaie donc à l'exécution :

| `lfs` dans `device_init.lua` | L'accroche charge |
|---|---|
| disponible | tous les fichiers `.lua` du dossier, par ordre alphabétique, sauf ceux qui commencent par `_` |
| indisponible | les mods connus, liste `KNOWN_MODS` de `_loader.lua` ; un fichier absent est sauté |

Le cas retenu et chaque mod chargé sont écrits dans `dcs.log`, lignes `COCKPIT_MODS`.
Un nouveau mod s'ajoute à `KNOWN_MODS` tant que le premier cas n'est pas confirmé en jeu.

Identifiants d'équipement pris par les mods : 250 pour le rideau, 251 pour les cycles.
Chaque mod s'abstient si le sien est déjà pris dans l'avion.

## Les cycles de commandes

Huit « slots », chacun lié à une touche par le paquet Custom_Keybinds (catégorie « Cockpit cycles », « Cockpit cycles: slot 1 » à « slot 8 »).
Chaque slot reçoit deux commandes, touche enfoncée et touche relâchée, ce qui permet de mesurer la durée de l'appui :

| Appui | Action |
|---|---|
| relâché avant le seuil (0,5 s par défaut) | l'action courte, au relâchement |
| tenu jusqu'au seuil | l'action longue, dès le seuil atteint, sans attendre le relâchement |
| slot sans action longue | l'action courte, dès l'appui |

Une action appuie sur un bouton du cockpit (puis le relâche 0,1 s plus tard) : soit toujours le même, soit le suivant d'un cycle.
Chaque cycle retient où il en est ; un bouton appuyé par n'importe quelle action replace aussi les autres cycles qui le contiennent.
Les boutons appuyés à la souris ne sont pas vus.

Avions configurés :

| Avion | Slot | Court | Long |
|---|---|---|---|
| AH-64D | 1 | MPD gauche : FCR, puis WPN, puis TSD, puis FCR… | MPD gauche : FCR (l'appui court suivant donne WPN) |

Chaque action est écrite dans `dcs.log`, lignes `COCKPIT_CYCLES`, avec l'équipement et la commande visés ; pendant la mise au point de l'AH-64D, elle s'affiche aussi à l'écran (`show_messages`).

### Quel équipement reçoit l'appui (AH-64D)

L'Apache a deux sièges, et deux façons d'appuyer sur un bouton de MPD depuis Lua.
Le choix se fait par `TARGET`, en tête de `config/AH-64D.lua` :

| `TARGET` | Équipement | Comment | Siège |
|---|---|---|---|
| `PLT` (par défaut) | MPD gauche du pilote (`MFD_PLT_LEFT`) | comme un clic de souris (`performClickableAction`) | toujours le MPD du pilote |
| `CPG` | MPD gauche du tireur (`MFD_CPG_LEFT`) | idem | toujours le MPD du tireur |
| `INPUT` | l'équipement des touches d'ED « Left MPD Pushbutton » (`MFD_INPUT_LEFT`) | comme ces touches (`SetCommand`) | peut-être celui du siège occupé, ce qui servirait aux deux |

Reste à trancher en jeu lequel fonctionne, et pour le tireur.

### Configurer un avion

1. Ajouter l'avion à `COCKPIT_CYCLES\aircraft.lua` : un morceau de son chemin de scripts de cockpit (`AH-64D` pour `Mods\aircraft\AH-64D\Cockpit\Scripts\`) et le nom de son fichier de configuration.
2. Écrire `COCKPIT_CYCLES\config\<avion>.lua`, sur le modèle de `AH-64D.lua` : il charge les tables de l'avion (`devices.lua`, `command_defs.lua`), décrit ses boutons (`device`, `command`, `method` : `"click"` ou `"command"`, `label`) et rend ses slots.
   Les boutons se trouvent dans `Mods\aircraft\<avion>\Cockpit\Scripts\clickabledata.lua` (équipement et commande de chaque bouton cliquable) et dans `Mods\aircraft\<avion>\Input\...\default.lua` (ce qu'envoient les touches d'ED).
3. Ajouter les huit commandes des slots aux fichiers de l'avion dans [dcs-community-keybinds](https://github.com/davidp57/dcs-community-keybinds), comme pour l'AH-64D, puis reconstruire Custom_Keybinds.

Réglages d'un fichier de configuration : `long_press` (seuil de l'appui long, en secondes), `release_after` (délai avant de relâcher le bouton du cockpit), `show_messages`.

## Installer avec Open Mod Manager

| Paquet | Canal | Rôle |
|---|---|---|
| `Cockpit_Mods_Hook_v<version>.ozp` | Game files (`DCS World`) | l'accroche |
| `Cockpit_Cycles_v<version>.ozp` | Game files | les cycles |
| `Quaggles_Injector` | Game files | permet d'ajouter des commandes sans toucher aux fichiers des modules |
| `Custom_Keybinds` (version avec « Cockpit cycles ») | User files (`Saved Games\DCS`) | les commandes des slots |

Puis dans DCS : Options > Commandes > AH-64D (pilote ou tireur), catégorie « Cockpit cycles », assigner « Cockpit cycles: slot 1 ».

Le paquet de l'accroche contient une copie complète du fichier du kneeboard avec la ligne ajoutée, prise sur la version de DCS installée au moment de construire le paquet.
Avec un rideau IFR 1.x installé, qui remplace lui aussi ce fichier : désinstaller le rideau, installer l'accroche, puis le rideau 2.0.

Construire les paquets (dans `dist\`) :

```powershell
python "D:\dev\_dcs-other\dcs-cockpit-mods\tools\build_omm.py" hook 1.0.0 "C:\jeux\DCS World"
```

```powershell
python "D:\dev\_dcs-other\dcs-cockpit-mods\tools\build_omm.py" cycles 1.0.0
```

## Installation de développement

Pour modifier les mods et les essayer sans repasser par Open Mod Manager (ne pas installer les paquets en même temps) :

```powershell
& "D:\dev\_dcs-other\dcs-cockpit-mods\install.ps1"
```

```powershell
& "D:\dev\_dcs-other\dcs-cockpit-mods\install.ps1" -Uninstall
```

`-Part Hook` ou `-Part Cycles` pour n'en traiter qu'un ; `-DcsPath "D:\DCS World"` pour une autre installation de DCS.

Le script copie les fichiers et ajoute la ligne de l'accroche au fichier du kneeboard, entre `-- COCKPIT-MODS BEGIN` et `-- COCKPIT-MODS END`.
Le fichier est sauvegardé en `.cockpit-mods.bak` avant la modification, sauvegarde reprise chaque fois qu'il est trouvé sans l'accroche (après une mise à jour de DCS, par exemple).
La désinstallation le rend identique à l'original et supprime la sauvegarde ; un fichier qui n'est pas en UTF-8 valide est refusé plutôt que réécrit.
L'accroche refuse de s'installer par-dessus la ligne d'un rideau IFR 1.x : lancer d'abord `install.ps1 -Uninstall` du rideau.

Relancer le script après chaque modification, puis relancer la mission : les scripts du cockpit sont relus à chaque démarrage de mission, sans redémarrer DCS.

## Vérification hors jeu

`tests\run.ps1` exécute l'accroche et les cycles de l'AH-64D avec un Lua 5.1 ordinaire et des fonctions de DCS simulées, une fois avec `lfs` et une fois sans : chargement par l'accroche, cycle des appuis courts, appui long, relâchement des boutons.
Il demande le Lua 5.1 de ZeroBrane Studio (`-Lua` pour un autre) et les scripts de l'AH-64D d'une installation de DCS.

```powershell
& "D:\dev\_dcs-other\dcs-cockpit-mods\tests\run.ps1"
```

Il ne dit rien de ce que DCS accepte vraiment : `lfs` dans `device_init.lua`, l'équipement qui réagit à l'appui, le siège du tireur se vérifient en jeu.

## Limites

- **L'IC échoue** : des scripts de DCS sont modifiés. Utilisable en solo et sur les serveurs qui ne vérifient pas les scripts.
- **Une mise à jour ou une réparation de DCS écrase le fichier du kneeboard** : l'accroche, et avec elle tous les mods qui en dépendent, disparaît. Réinstaller son paquet (le reconstruire si la mise à jour a changé ce fichier), ou relancer `install.ps1 -Part Hook`.
- **Un cycle ne sait pas sur quelle page est le MPD** : il retient seulement son dernier appui.
