# DCS cockpit mods

Mods de cockpit pour DCS World, et l'accroche qui leur permet de cohabiter :

- **l'accroche partagée** (`hook/`) : charge les mods de cockpit depuis un dossier commun, pour qu'ils ne remplacent pas chacun le même fichier de DCS ;
- **les cycles de pages des MPD de l'AH-64D** (`cycles/`) : un seul bouton du HOTAS fait défiler les pages d'un MPD, et un appui long peut aller directement sur une page choisie.

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

## Les cycles de pages des MPD (AH-64D)

Chaque MPD a cinq commandes, dans Options > Commandes de l'AH-64D (pilote et tireur), catégorie « MPD page cycles ».
Toutes font défiler les pages du MPD sur un appui court, dans le même ordre sur les deux MPD : FCR, puis WPN, puis TSD, puis VID, puis A/C, puis FCR…
Ce sont toutes les pages qui ont leur propre bouton autour de l'écran, sauf COM.

Elles ne diffèrent que par l'appui long (tenu 0,5 s) : on choisit sa page d'accès direct en assignant la commande correspondante à son bouton du HOTAS, sans aucun fichier à modifier.

| Commande | Appui long |
|---|---|
| « Left MPD: next page » | aucun : la page change dès l'appui |
| « Left MPD: next page, hold FCR » | va sur FCR |
| « Left MPD: next page, hold WPN » / « TSD » / « VID » | va sur cette page |

Même chose pour « Right MPD: … ».
Avec un appui long, l'appui court ne part qu'au relâchement, puisque le mod doit attendre de savoir si le bouton est tenu ; sans appui long, la page change dès l'appui.

Les cinq commandes d'un MPD partagent la même position dans le cycle, et un appui long y replace le cycle : après « hold TSD », l'appui court suivant donne VID.
Le mod ne voit pas les boutons appuyés à la souris ni les pages changées autrement : il ne retient que son propre dernier appui.

Chaque appui est écrit dans `dcs.log`, lignes `COCKPIT_CYCLES`, avec l'équipement et la commande visés ; pendant la mise au point, il s'affiche aussi à l'écran (`show_messages` dans `config/AH-64D.lua`).

### Quel équipement reçoit l'appui

L'Apache a deux sièges, et deux façons d'appuyer sur un bouton de MPD depuis Lua.
Le choix se fait par `TARGET`, en tête de `COCKPIT_CYCLES\config\AH-64D.lua` :

| `TARGET` | Équipement | Comment | Siège |
|---|---|---|---|
| `PLT` (par défaut) | MPD du pilote (`MFD_PLT_LEFT`, `MFD_PLT_RIGHT`) | comme un clic de souris (`performClickableAction`) | toujours les MPD du pilote |
| `CPG` | MPD du tireur (`MFD_CPG_LEFT`, `MFD_CPG_RIGHT`) | idem | toujours les MPD du tireur |
| `INPUT` | l'équipement des touches d'ED « Left/Right MPD Pushbutton » (`MFD_INPUT_LEFT`, `MFD_INPUT_RIGHT`) | comme ces touches (`SetCommand`) | peut-être celui du siège occupé, ce qui servirait aux deux |

Reste à trancher en jeu lequel fonctionne, et pour le tireur.

### Comment c'est fait

Le mod est un équipement Lua (`avLuaDevice`, numéro 251) qui reçoit des « slots » : 16 au plus, chacun avec une commande touche enfoncée (3000 + n) et une commande touche relâchée (3100 + n), ce qui permet de mesurer la durée de l'appui.
`config/AH-64D.lua` donne à chaque slot une action courte et une action longue : appuyer sur le bouton suivant d'un cycle, ou toujours sur le même bouton (puis le relâcher 0,1 s plus tard).
Les slots 1 à 5 sont le MPD gauche, 8 à 12 le MPD droit, dans l'ordre des commandes ajoutées à dcs-community-keybinds.
Ces numéros ne doivent jamais changer : DCS enregistre les assignations des pilotes sous le numéro de la commande, et une renumérotation les ferait pointer ailleurs sans prévenir.
Les slots 6, 7, 13 et 14 (appuis longs COM et A/C, retirés) restent libres pour cette raison.

Le mécanisme ne dépend pas de l'Apache.
Pour un autre avion (un F-16, par exemple), on ajouterait une ligne à `COCKPIT_CYCLES\aircraft.lua`, un `config\<avion>.lua` sur le modèle de celui de l'Apache (boutons trouvés dans `Mods\aircraft\<avion>\Cockpit\Scripts\clickabledata.lua`), et ses commandes dans dcs-community-keybinds.

Réglages du fichier de configuration : `long_press` (seuil de l'appui long, en secondes), `release_after` (délai avant de relâcher le bouton du cockpit), `show_messages`.

## Installer avec Open Mod Manager

| Paquet | Canal | Rôle |
|---|---|---|
| `Cockpit_Mods_Hook_v<version>.ozp` | Game files (`DCS World`) | l'accroche |
| `Apache_MPD_Cycles_v<version>.ozp` | Game files | les cycles de pages des MPD |
| `Quaggles_Injector` | Game files | permet d'ajouter des commandes sans toucher aux fichiers des modules |
| `Custom_Keybinds` (version avec « MPD page cycles ») | User files (`Saved Games\DCS`) | les commandes des MPD |

Puis dans DCS : Options > Commandes > AH-64D (pilote ou tireur), catégorie « MPD page cycles », assigner une commande « Left MPD: … » et une « Right MPD: … ».

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
Sans cette sauvegarde, l'accroche vient sans doute du paquet Open Mod Manager : la désinstallation refuse d'y toucher, sauf avec `-Force`.
`-Part Cycles` refuse de s'installer si l'accroche manque, chargeur ou ligne du kneeboard (une mise à jour de DCS retire la ligne et laisse le chargeur).
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
- **Le mod ne sait pas sur quelle page est le MPD** : il retient seulement son dernier appui. Après un changement de page à la souris, l'appui suivant peut donner une page inattendue ; le cycle se recale au tour suivant.
