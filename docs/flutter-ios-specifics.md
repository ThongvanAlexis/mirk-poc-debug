# Flutter iOS — recettes obligatoires

Liste des fix qu'**on doit appliquer sur chaque app Flutter iOS qu'on construit**.
Le scaffold `flutter create` ne les met pas — ils ont été découverts par la
douleur sur le projet parent `GOSL-MirkFall` (2026-04-19) puis re-découverts
sur ce POC (2026-04-30). On documente ici pour ne pas avoir à les re-trouver
au prochain projet.

Ordre : du plus critique au "nice-to-know".

---

## 1. `permission_handler` — macros Podfile obligatoires

**Symptôme :** L'utilisateur tape sur le bouton "Allow location" (ou n'importe
quelle permission), la dialog iOS **ne s'affiche jamais**, et l'app retombe
sur une page Réglages générique (Données mobiles, Recherche, Apple Intelligence).
Même bug observé dans GOSL-MirkFall et dans ce POC.

**Cause racine :** `permission_handler` 12.x est compilé avec des
**preprocessor macros opt-in** côté iOS. Sans la macro `PERMISSION_LOCATION=1`,
le handler `Permission.locationWhenInUse` se compile en stub no-op qui retourne
`denied` synchronement, sans jamais appeler CoreLocation. Donc :

- la dialog système iOS ne se déclenche pas (le plugin n'a même pas commencé
  le request)
- `openAppSettings()` deep-linke vers une page Réglages incomplète parce
  qu'aucune permission n'est enregistrée pour l'app au niveau iOS

**Fix :** Committer un `ios/Podfile` à la main (le `flutter create` Windows
ne le génère pas) avec un `post_install` block qui injecte les macros dans
`GCC_PREPROCESSOR_DEFINITIONS` :

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)

    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_LOCATION=1',
        # 'PERMISSION_NOTIFICATIONS=1',  # uncomment when on l'ajoute
        # 'PERMISSION_CAMERA=1',         # ...
      ]
    end
  end
end
```

**Liste complète des macros disponibles :**
<https://pub.dev/packages/permission_handler> → section "iOS".
Chaque `Permission.foo.request()` côté Dart a une macro correspondante.

**Règle de discipline :** ajouter la macro **dans le même commit** qui ajoute
le `Permission.foo.request()` côté Dart. Sinon on a un build "vert" qui no-op
silencieusement la permission en prod.

**Vérification après fix :** rebuilder l'IPA, sideloader, taper le CTA → la
vraie dialog système iOS doit apparaître ("Allow While Using App / Don't Allow").

---

## 2. `CFBundleName` — pas d'underscore (SideStore Apple-ID API)

**Symptôme :** SideStore crashe au moment d'enregistrer l'App ID auprès
d'Apple :
```
Developer error 35: An invalid value 'mon_app' was provided for
the parameter 'appIdName'.
```

**Cause racine :** Le scaffold `flutter create --project-name mon_app`
écrit `<key>CFBundleName</key><string>mon_app</string>` dans
`ios/Runner/Info.plist`. SideStore (`isideload`) lit ce champ et le soumet
à l'API Apple Developer comme `appIdName`. Apple n'accepte que **lettres,
chiffres et espaces** dans ce champ — pas d'underscore, pas de tiret.

**Fix :** Renommer `CFBundleName` en camelCase ou en mots avec espaces.
Conserver `CFBundleDisplayName` (le nom user-visible sur l'icône) tel quel.

```diff
 <key>CFBundleDisplayName</key>
 <string>MirkFall POC</string>            <!-- icône Home Screen -->
 <key>CFBundleName</key>
-<string>mirk_poc_debug</string>          <!-- ❌ rejeté par Apple -->
+<string>MirkPocDebug</string>            <!-- ✅ camelCase, ≤ 16 chars -->
```

**Contraintes Apple sur `CFBundleName` :**
- ≤ 16 caractères (recommandation Apple, pas un hard cap)
- doit matcher `^[A-Za-z0-9 ]+$` pour passer SideStore

**Pas d'impact sur le quota SideStore :** le bundle identifier
(`com.example.appName`) n'est pas modifié, donc Apple ne crée pas un
nouveau App ID — le slot SideStore (10/semaine sur compte Apple gratuit)
n'est pas brûlé.

---

## 3. FileLogger — comment il doit marcher

Hérité verbatim du parent `GOSL-MirkFall`. Trois fichiers, deux observers,
zero télémétrie réseau.

### 3.1 Anatomie

```
lib/infrastructure/logging/
├── file_logger.dart                          # bootstrap + écriture
└── file_logger_lifecycle_observer.dart       # flush sur background
```

### 3.2 Bootstrap obligatoire

Appeler `FileLogger.bootstrap()` **avant `runApp()`** dans `main.dart`,
sinon les premiers logs (Flutter init, plugin init) sont perdus :

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FileLogger.bootstrap();       // ← AVANT runApp
  WidgetsBinding.instance.addObserver(FileLoggerLifecycleObserver());
  runApp(const MirkPocApp());
}
```

### 3.3 Format de nom de fichier — UTC ISO-8601 *basic*

```
<app_documents_dir>/logs/20260430T211738Z_logs.txt
                        ^^^^^^^^^^^^^^^^^
                        UTC, format basic (sans tirets ni deux-points)
```

**Pourquoi pas de deux-points (`:`) ?** Windows interdit `:` dans les noms
de fichier. iOS et Android l'acceptent, mais pour rester portable cross-plat
(les tests tournent sur Windows en CI + le partage des logs vers un PC dev
doit fonctionner), on utilise le format ISO-8601 *basic* (`YYYYMMDDTHHMMSSZ`)
au lieu de la forme étendue (`YYYY-MM-DDTHH:MM:SSZ`).

**Pourquoi UTC, pas heure locale ?** Reproductibilité. Quand l'utilisateur
partage un log d'un voyage à l'étranger, on a une chance de remettre les
events dans l'ordre. La timezone locale est loggée séparément dans le
record bootstrap.

### 3.4 Format des records — JSONL avec millisecond precision

```jsonl
{"ts":"2026-04-30T21:17:38.142Z","lvl":"INFO","logger":"app.bootstrap","msg":"FileLogger bootstrap — activeFilename=20260430T211738Z_logs.txt"}
{"ts":"2026-04-30T21:17:38.247Z","lvl":"FINE","logger":"presentation.permission_gate","msg":"requestLocationWhenInUse → granted"}
```

**Ms precision** parce que les events de plugin (permission_handler,
geolocator) arrivent en bursts < 1 seconde. Sans ms, les ordres relatifs
sont ambigus.

### 3.5 Prune des vieux logs au boot — cap fixe

Au bootstrap, le logger énumère `<app_documents_dir>/logs/`, somme la taille
totale des fichiers `.txt`/`.txt.gz`, et **supprime les plus vieux** jusqu'à
ce que la somme passe sous **`kMaxLogsDirBytes` (10 MB)**.

**Pourquoi 10 MB et pas plus ?** Le partage par mail iOS impose une limite
~25 MB. On garde une marge pour le gzip + la metadata + l'attachment de
plusieurs fichiers si l'utilisateur exporte une session multi-jour. Constant
exposé dans `lib/config/constants.dart` :

```dart
const int kMaxLogsDirBytes = 10 * 1024 * 1024;   // 10 MB
```

**Le fichier actif n'est jamais supprimé** par le prune (sinon RAF cassé).
Voir le test Windows ci-dessous.

### 3.6 Test Windows — sharing-violation sur unlink-open-file

**Symptôme :** Le test "10 MB prune cap" échoue déterministiquement sur
Windows avec :
```
FileSystemException: Cannot delete file, path = '...\\active.txt'
(OS Error: The process cannot access the file because it is being used
by another process., errno = 32)
```

**Cause :** POSIX permet `unlink()` sur un fichier ouvert (le fichier
disparaît du namespace mais le RAF reste valide jusqu'au close). Windows
verrouille le handle — `Directory.delete(recursive: true)` plante quand
le RAF actif est dans le scope.

**Fix :** Au lieu d'un `delete(recursive: true)` blunt, itérer
manuellement et **skip le fichier actif** :

```dart
// ✅ Windows-portable : skip le RAF ouvert, le bootstrap suivant le fermera
await for (final entry in logsDir.list()) {
  if (entry is File && entry.path != activeFilename) {
    try {
      await entry.delete();
    } on FileSystemException {
      // RAF actif d'un autre run ; idempotent au prochain bootstrap
    }
  }
}
```

```dart
// ❌ Casse sur Windows
await logsDir.delete(recursive: true);
```

### 3.7 Lifecycle observer — flush sur background

Sans ça, les events des dernières secondes sont perdus si l'app est tuée
par iOS (memory pressure, force-quit user). Le `FileLoggerLifecycleObserver`
implémente `WidgetsBindingObserver.didChangeAppLifecycleState` et appelle
`FileLogger.instance.flush()` sur `AppLifecycleState.paused` /
`.inactive` / `.detached`.

**Enregistrer dans `main()`** (voir §3.2). Sans ça l'observer existe mais
n'est pas notifié.

### 3.8 Partage des logs (LOG-04) — `share_plus` 12.x

Pas `Share.shareXFiles(...)` (deprecated, `dart format --fatal-infos`
explose). Utiliser :

```dart
await SharePlus.instance.share(
  ShareParams(files: <XFile>[XFile(activeLogFilePath)]),
);
```

Le bouton de partage déclenche le iOS share sheet → Mail → email arrive
avec `<timestamp>_logs.txt.gz` en attachment.

---

## 4. Gotchas iOS / Flutter divers

### 4.1 `gen-l10n` casse `dart format --set-exit-if-changed` en CI

**Symptôme :** Le job CI `dart format --line-length 160 --set-exit-if-changed .`
échoue après `flutter pub get`. Diff sur `lib/l10n/app_localizations*.dart`.

**Cause racine :** Flutter 3.41 a retiré `synthetic-package: true` de
`l10n.yaml`. La codegen génère maintenant les fichiers dans `lib/l10n/`
(visibles, gitignorés mais présents dans l'arbo CI). Le générateur Flutter
n'utilise pas `--line-length 160` — il sort en 80 cols par défaut.

**Fix CI :** Ajouter un step **avant** le check format qui formate les
fichiers codegen :

```yaml
- name: Pre-format gen-l10n codegen
  run: dart format --line-length 160 lib/l10n/

- name: Verify dart format
  run: dart format --line-length 160 --set-exit-if-changed .
```

**Import path après synthetic-package removal :**
```dart
// ❌ Flutter 3.40 et antérieurs
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// ✅ Flutter 3.41+
import 'package:<project_name>/l10n/app_localizations.dart';
```

### 4.2 `CFBundleName` ≠ `CFBundleDisplayName`

| Clé                       | Rôle                              | Visible où                                  |
| ------------------------- | --------------------------------- | ------------------------------------------- |
| `CFBundleDisplayName`     | Nom sous l'icône Home Screen      | Springboard, App Switcher                   |
| `CFBundleName`            | Nom court interne (≤ 16 chars)    | About panels, SideStore `appIdName` Apple   |

Quand on a une marque comme "MirkFall POC" :
- `CFBundleDisplayName = MirkFall POC` (visible utilisateur)
- `CFBundleName = MirkPocDebug` (interne, sans espace ni underscore)

### 4.3 Required-Reason API codes (Apple privacy manifest)

`PrivacyInfo.xcprivacy` doit déclarer chaque API "Required Reason"
qu'on utilise. Pour la POC :
- `C617.1` → `FileTimestamp` (FileLogger lit `File.stat().modified`)
- `CA92.1` → `UserDefaults` (utilisé par Flutter framework lui-même)

**À re-vérifier avant chaque submission TestFlight** — Apple met à jour
la liste des API codes périodiquement. Source authoritative :
<https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api>

### 4.4 SideStore — quota App ID 10/semaine

Compte Apple gratuit : **10 App IDs distincts par fenêtre roulante de
7 jours**. Chaque bundle identifier unique sideloadé brûle un slot.
Conséquence pratique :

- **Locker le bundle id le plus tôt possible** (Phase 1) — changer après
  la première sideload brûle un slot supplémentaire pour rien
- **Disable App Limit toggle dans SideStore Settings** permet d'avoir
  > 3 apps simultanées mais ne change PAS le quota Apple
- Erreur 35 (CFBundleName underscore) **n'est pas comptée** — Apple
  rejette avant de créer l'App ID

---

## TL;DR — checklist nouveau projet Flutter iOS

À copier-coller au début d'un nouveau projet **avant la première sideload** :

- [ ] `ios/Podfile` committé avec `PERMISSION_*` macros pour chaque
      `Permission.foo.request()` qu'on appelle (§1)
- [ ] `Info.plist`: `CFBundleName` en camelCase ou avec espaces, **pas**
      d'underscore (§2)
- [ ] `FileLogger.bootstrap()` appelé avant `runApp()` dans `main.dart` (§3.2)
- [ ] `FileLoggerLifecycleObserver` enregistré via `addObserver` (§3.7)
- [ ] `kMaxLogsDirBytes` dans `lib/config/constants.dart` (§3.5)
- [ ] CI workflow : `dart format lib/l10n/` **avant** le check
      `--set-exit-if-changed` (§4.1)
- [ ] Imports l10n: `package:<project>/l10n/...`, pas `flutter_gen` (§4.1)
- [ ] `PrivacyInfo.xcprivacy` à jour avec les Required-Reason API codes (§4.3)
