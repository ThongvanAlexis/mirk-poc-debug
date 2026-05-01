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

### 3.5 Écritures synchrones — pourquoi `_onRecord` n'est PAS `async`

**Race condition #1 : auto-race sur `Stream.listen`.** Le hook
`Logger.root.onRecord.listen(_onRecord)` ne `await` PAS les callbacks
asynchrones. Si on écrit `_onRecord` en async avec
`await raf.writeString(line)`, deux records qui arrivent à < 1 ms d'écart
démarrent leurs writes en parallèle — et les bytes s'**interleavent** dans
le fichier. Résultat : JSONL corrompu, lignes mélangées, parsing pété.

**Fix :** `_onRecord` est synchrone, utilise `writeStringSync` + `flushSync` :

```dart
// ✅ Synchrone — pas de race possible, Stream.listen séquentialise les calls
static void _onRecord(LogRecord rec) {
  final raf = _raf;
  if (raf == null) return;
  final line = '${jsonEncode(_buildEntry(rec))}\n';
  try {
    raf.writeStringSync(line);
    raf.flushSync();    // = fsync(2) — durable disque, pas juste userspace
  } on FileSystemException catch (e) {
    developer.log('FileLogger record write failed: $e', name: 'FileLogger');
    _raf = null;        // drop silencieux des records suivants
  }
}

// ❌ Async — back-to-back records s'interleavent, JSONL corrompu
static Future<void> _onRecord(LogRecord rec) async {
  final raf = _raf;
  if (raf == null) return;
  await raf.writeString('${jsonEncode(_buildEntry(rec))}\n');  // RACE
}
```

**Pourquoi pas un `Queue` + worker async ?** Possible mais ajoute de la
latence (les events sont batched), et les logs critiques (crash imminent)
peuvent ne pas être flushés à temps. Le sync direct flush garantit que
chaque record est sur disque AVANT que `_onRecord` rende la main — donc
même un kill brutal d'iOS perd au pire le record en cours d'écriture, pas
les 200 d'avant en buffer.

**Symptôme historique de l'ancienne implémentation async :**
`StateError: StreamSink is bound` levé quand `_onRecord` ré-entrait
pendant qu'un `await sink.flush()` précédent était in-flight. Le catch
nullait le sink → ~99% des records suivants droppés silencieusement
pour le reste de la session. Bug observé sur le parent project pendant
l'install d'un asset 5.2 GB sous pression mémoire.

---

**Race condition #1bis : iOS jetsam invalide la page cache** (deuxième
bug production-fatal du parent). `IOSink.flush()` ne flush que
**userspace → kernel page cache**, pas jusqu'au flash. Sous pression
mémoire foreground (iOS jetsam, classique pendant l'install d'assets
volumineux ou un load de tiles map), iOS **invalide la page cache** et
les records écrits dans les dernières secondes **n'atteignent jamais
le flash**. L'app crashe ou est tuée → log perdu juste avant le crash,
pile au moment où il aurait été le plus utile.

**Fix :** `RandomAccessFile.flushSync()` qui est le vrai `fsync(2)`
documenté Dart (durable jusqu'au flash), pas juste un drain userspace.
Coût : ~sub-milliseconde sur flash moderne (ACCEPTABLE pour une app
diagnostic single-user).

**À retenir :** `IOSink + flush()` = piège. `RandomAccessFile +
flushSync()` = bon. **NE PAS** "moderniser" en `IOSink` parce que ça
a l'air plus idiomatique — l'API plus propre cache deux bugs prod.

---

**Race condition #2 : boucle infinie sur erreur.** Si `_onRecord` log
l'erreur via `Logger.shout(e)` au lieu de `developer.log()`, ça
déclenche un nouveau LogRecord → nouveau `_onRecord` → nouveau write
fail → nouveau `Logger.shout` → ∞.

**Fix :** sur `FileSystemException`, on utilise `dart:developer` `log()`
**directement** (visible dans Xcode console / `flutter logs`, pas dans
le pipeline `Logger`), et on **null le `_raf`** pour que les records
suivants soient silencieusement droppés au lieu de re-rentrer.

**Catch only `FileSystemException` :** l'API sync ne lève pas
`StateError` (à la différence de l'async). Catch trop large = on attrape
des bugs de programmation qu'on devrait laisser propager (CLAUDE.md
§Error handling).

### 3.6 Prune des vieux logs au boot — cap fixe

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
Voir le test Windows ci-dessous (§3.7).

**Race condition #3 (acceptée) : double-bootstrap concurrent.** Le prune
suppose qu'**une seule instance de l'app écrit dans le dossier logs** à un
moment donné. Si deux fenêtres Flutter desktop bootent en parallèle, elles
peuvent chacune compter la taille du dossier avant que l'autre n'ait
écrit, puis chacune décide de pruner les mêmes vieux fichiers → over-delete
ou compteurs incohérents.

C'est une **invariant accepté** sur mobile (iOS / Android = single
instance par design). Sur desktop, c'est OK pour une app single-window.
Si on ship un jour une variante headless ou multi-window qui peut tourner
à côté de l'UI, il faudra un **fcntl file-lock** sur le dossier au
bootstrap. Pas le cas pour V1.0.

### 3.7 Test Windows — sharing-violation sur unlink-open-file

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

### 3.8 Lifecycle observer — flush sur background

Sans ça, les events des dernières secondes sont perdus si l'app est tuée
par iOS (memory pressure, force-quit user). Le `FileLoggerLifecycleObserver`
implémente `WidgetsBindingObserver.didChangeAppLifecycleState` et appelle
`FileLogger.instance.flush()` sur `AppLifecycleState.paused` /
`.inactive` / `.detached`.

**Enregistrer dans `main()`** (voir §3.2). Sans ça l'observer existe mais
n'est pas notifié.

### 3.9 Partage des logs (LOG-04) — `share_plus` 12.x

Pas `Share.shareXFiles(...)` (deprecated, `dart format --fatal-infos`
explose). Utiliser :

```dart
await SharePlus.instance.share(
  ShareParams(files: <XFile>[XFile(activeLogFilePath)]),
);
```

Le bouton de partage déclenche le iOS share sheet → Mail → email arrive
avec `<timestamp>_logs.txt.gz` en attachment.

### 3.10 Petits quirks à NE PAS toucher

Liste des décisions implémentation qui ont l'air gratuites mais qui
encodent un piège — ne pas les "nettoyer" sans relire cette section.

**`FileMode.writeOnlyAppend`** (pas `write`, pas `append`).
- `FileMode.write` truncate le fichier au open → si bootstrap re-tourne
  (hot-reload, test re-bootstrap, ou clearAll(rearm: true)), tous les
  records du run actuel sautent.
- `FileMode.append` ouvre en read+write+append → on lit jamais, donc
  permission read inutile. `writeOnlyAppend` est la forme exacte.

**Idempotency bootstrap : `close → cancel`, dans cet ordre.**
```dart
await _closeRafQuietly();        // 1. ferme le RAF d'abord
await _subscription?.cancel();   // 2. désabonne ENSUITE
```
L'inverse (cancel avant close) laisse une fenêtre où `_onRecord` peut
être appelé sur un RAF déjà null → on perd silencieusement le dernier
record. Suit la convention "close downstream resource first, then stop
upstream signal".

**`flush()` est intentionnellement no-op.**
```dart
static Future<void> flush() async {
  // Intentionally empty — durability is enforced per-record in _onRecord.
}
```
Chaque record fait son propre `flushSync` au write-time, donc il n'y a
**rien à flush** au call-site (share-sheet, lifecycle observer). On
garde quand même la méthode pour ne pas casser les call-sites
existants. **NE PAS supprimer** sous prétexte qu'elle a l'air inutile —
c'est un compatibility shim explicite.

**Premier record après bootstrap = cross-check sandbox UUID iOS.**
```dart
Logger('infrastructure.logging.file_logger')
    .info('FileLogger bootstrap — activeFilename=$_activeFilename');
```
Le path absolu est loggé dans le JSONL lui-même. Pourquoi : le sandbox
container UUID iOS peut **changer entre les launches** (réinstall via
SideStore, restore depuis backup, app data migration). En relisant un
vieux log, on peut comparer le path écrit au path qu'on lit pour
détecter une rotation et savoir que l'ancien `activeFilename` est devenu
invalide.

**`listLogFiles()` sort par `FileStat.modified`, PAS par filename.**
Robuste à un futur changement du format de filename. Si on switch un
jour de `YYYYMMDDTHHMMSSZ` à un autre format, le sort reste correct
parce qu'il s'appuie sur l'mtime kernel, pas sur l'ordre alphabétique
du nom.

**Catch only `FileSystemException`** (pas `Exception` ni `Object`).
L'API sync ne lève pas `StateError` (à la différence de l'async). Catch
trop large = on attrape des bugs de programmation qu'on devrait laisser
propager (CLAUDE.md §Error handling : "Bugs de programmation → laisser
propager jusqu'au handler top-level").

**Lifecycle observer : `super.didChangeAppLifecycleState(state)`
**en premier**, et flush en `unawaited()`.**
```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);   // 1. convention Flutter
  if (state == AppLifecycleState.resumed) return;
  unawaited(_flushCallback());               // 2. fire-and-forget
}
```
- `super.didChange...` first : convention Flutter (mixin chains).
- `resumed` → pas de flush (le buffer a été drainé sur la transition
  out-of-resumed précédente — re-flush serait un syscall no-op).
- `unawaited()` : `didChangeAppLifecycleState` est sync, on ne peut
  pas await. Le flush est best-effort : si l'OS kill avant que le
  fsync rende la main, on a au moins écrit ce qu'on avait à cet
  instant T.

### 3.11 Verbose logging toggle (debug menu)

Deux mécanismes pour activer le niveau `Level.ALL` (au lieu de
`Level.INFO` par défaut) :

1. **`--dart-define=DEBUG=true`** au build — verbose forcé pour ce
   build, non-runtime-toggleable.
2. **`SharedPreferences` flag `debug_logging_enabled`** — toggleable
   à runtime via un menu debug dans l'app, persiste entre les launches.

Au bootstrap, le niveau racine est calculé comme :
```dart
const debugDefine = bool.fromEnvironment('DEBUG');
final verboseFromPrefs = prefs.getBool(kDebugLoggingPrefsKey) ?? false;
Logger.root.level = (debugDefine || verboseFromPrefs) ? Level.ALL : Level.INFO;
```

**API recommandée :** `FileLogger.writeVerbosePref(bool value)` plutôt
que `FileLogger.toggleVerbosePref()`. Le premier est un write explicite
(idempotent, aligne le fichier persisté avec l'état du widget). Le
second fait un read-modify-write XOR — si l'utilisateur tape deux fois
vite sur le toggle, on peut avoir une race read-modify-write. À garder
seulement pour les call-sites qui n'ont pas l'état désiré sous la main.

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

## 5. Permission location 2-étapes (background tracking)

**Quand l'utiliser :** dès que l'app a besoin du GPS quand l'écran est
éteint ou l'app en background (tracking long, fog-of-war, fitness, suivi
GPS continu). Notre POC Phase 1 N'EN A PAS BESOIN — elle reste
foreground-only et utilise la chaîne 1-étape (`whenInUse` only). Le
parent project `GOSL-MirkFall` utilise la chaîne 2-étapes pour révéler
le fog pendant que le téléphone est dans la poche.

### 5.1 Comportement iOS — pourquoi 2 prompts

Sur iOS, la première `Permission.locationWhenInUse.request()` affiche le
prompt système classique :

```
"App" Would Like to Use Your Location
[ Allow Once ]  [ Allow While Using App ]  [ Don't Allow ]
```

Si l'utilisateur tape **"Allow While Using App"**, on a `whenInUse =
granted`. À CE MOMENT, appeler `Permission.locationAlways.request()`
déclenche un **deuxième prompt** :

```
Allow "App" to also use your location even when you are not
using the app?
[ Keep Only While Using ]  [ Change to Always Allow ]
```

iOS impose qu'on ne puisse PAS demander `locationAlways` directement
dès le départ — il faut passer par `whenInUse` d'abord, sinon le 2e
prompt ne s'affiche jamais (Apple's "trickle-up consent").

### 5.2 Comportement Android — invariant ordre

**Android 10+ (API 29+) :** appeler `Permission.locationAlways.request()`
SANS avoir d'abord obtenu `Permission.locationWhenInUse.request()` est
**silencieusement ignoré**. L'OS retourne `denied` sans afficher de
prompt. Donc même si on ne ciblait que Android, l'ordre `whenInUse →
always` reste obligatoire.

**Android 13+ (API 33+) :** ajouter `Permission.notification` EN
PREMIER. `POST_NOTIFICATIONS` est requis runtime pour TOUTE notification
postée par l'app, y compris la notification persistante du foreground
service de geolocator. Sans la perm, le service tourne mais
l'utilisateur ne voit aucun indicator.

**Android 14+ (SDK 34+) :** déclarer `FOREGROUND_SERVICE_LOCATION` dans
le manifest. Sans ça, le foreground service de geolocator échoue
silencieusement à démarrer, le flow location n'émet rien.

### 5.3 Pattern Dart — chaîne séquentielle (du parent)

```dart
// lib/application/permissions/location_permission_flow.dart (parent)
Future<LocationPermissionOutcome> requestLocationAlways() async {
  // 1. Notification d'abord (Android 13+) — best-effort, denial ne
  //    bloque PAS le flow (la session GPS marche, juste pas
  //    d'indicator persistant). iOS = no-op, résolu instantanément
  //    à `granted`.
  try {
    await Permission.notification.request();
  } catch (e, st) {
    _log.fine('notification_request_failed', e, st);
  }

  // 2. whenInUse — REQUIS avant Always sur Android 10+ ET sur iOS
  //    (sinon le 2e prompt ne se déclenche pas).
  final whenInUse = await Permission.locationWhenInUse.request();
  if (whenInUse.isPermanentlyDenied) {
    return LocationPermissionOutcome.permanentlyDenied;
  }
  if (!whenInUse.isGranted) {
    return LocationPermissionOutcome.denied;
  }

  // 3. locationAlways — sur iOS déclenche le 2e prompt
  //    "Change to Always Allow". Sur Android, déclenche le prompt
  //    "Allow all the time".
  final always = await Permission.locationAlways.request();
  if (always.isGranted) {
    return LocationPermissionOutcome.granted;
  }
  if (always.isPermanentlyDenied) {
    return LocationPermissionOutcome.permanentlyDenied;
  }
  // L'utilisateur a accepté whenInUse mais décliné Always — l'app
  // peut quand même tracker en foreground, mais doit warn que les
  // sessions longues ne survivront pas à l'écran qui s'éteint.
  return LocationPermissionOutcome.whileInUseOnly;
}
```

### 5.4 Outcome enum (4 états distincts)

```dart
enum LocationPermissionOutcome {
  granted,           // Always — full background tracking OK
  whileInUseOnly,    // whenInUse OK mais Always refusé — warn long sessions
  denied,            // re-request OK (pas encore en don't-ask-again)
  permanentlyDenied, // deep-link `openAppSettings()` requis
}
```

### 5.5 Dépendances Info.plist + Podfile

```xml
<!-- ios/Runner/Info.plist -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>... pourquoi on a besoin du GPS foreground (visible 1er prompt) ...</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>... pourquoi on a besoin du GPS background (visible 2e prompt) ...</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>   <!-- iOS background location updates -->
  <string>fetch</string>       <!-- significant-change wake hook (watchdog) -->
</array>
```

```ruby
# ios/Podfile post_install
config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
  '$(inherited)',
  'PERMISSION_LOCATION=1',         # couvre whenInUse ET locationAlways
  'PERMISSION_NOTIFICATIONS=1',    # POST_NOTIFICATIONS Android 13+
]
```

**Note macros :** une SEULE macro `PERMISSION_LOCATION=1` couvre les
deux permissions iOS (`locationWhenInUse` + `locationAlways`). Pas
besoin d'une macro distincte pour `Always`.

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

### 5.6 UI — écran denied + auto-resume hook

Sur `permanentlyDenied` → pousser un écran `/permissions/denied` avec
un bouton "Ouvrir les paramètres" qui appelle
`openAppSettings()` (top-level fonction de `permission_handler`).

L'écran denied implémente `WidgetsBindingObserver` et re-check
`Permission.locationWhenInUse.status` à chaque
`AppLifecycleState.resumed` (lecture-seule, ne déclenche pas de
prompt) :

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state != AppLifecycleState.resumed) return;
  unawaited(_recheckPermissionAndMaybePop());
}

Future<void> _recheckPermissionAndMaybePop() async {
  final status = await Permission.locationWhenInUse.status;
  if (!status.isGranted) return;
  if (context.canPop()) context.pop(true);
  else context.go('/');
}
```

Effet UX : l'utilisateur tape "Open Settings" → toggle Location ON
dans iOS Settings → tape Back → l'app **auto-naviguer vers /map** sans
qu'il ait à re-taper le bouton CTA. Zéro friction.

### 5.7 Pièges iOS spécifiques au background tracking

**"Ask Next Time Or When I Share" (provisional grant) = traiter comme
denied.** iOS propose ce 3e bouton ("Allow Once" sur l'UI iOS récente)
qui donne un grant ÉPHÉMÈRE — il expire à la fin de la session. Ne PAS
s'appuyer dessus pour démarrer un tracking long. Le pattern
recommandé : `if (status.isGranted && !status.isLimited)` ou similaire.

**`AppleSettings` geolocator config — sinon iOS suspend après quelques minutes :**
```dart
const settings = AppleSettings(
  accuracy: LocationAccuracy.best,
  activityType: ActivityType.fitness,
  pauseLocationUpdatesAutomatically: false,   // sinon pause silencieuse
  showBackgroundLocationIndicator: true,       // iOS 14+ blue bar / Dynamic Island
  allowBackgroundLocationUpdates: true,        // CRITIQUE
);
```

**À NE JAMAIS combiner :** `startUpdatingLocation` continu avec
`startMonitoringSignificantLocationChanges` en mode
`LocationAccuracy.low`. iOS 16.4+ suspend l'app dans cette config
(Apple forums thread #726945).

**Background App Refresh OFF = silent kill.** Si l'utilisateur a
désactivé BAR globalement ou pour l'app spécifiquement, iOS ne peut
pas re-launcher l'app pour un event location en background. Surfacer
l'état de BAR à session-start via method channel et warner.

**Sandbox UUID rotation :** voir §3.10 — le path absolu du log change
entre les launches après réinstall via SideStore. Logger le path actif
au bootstrap pour permettre un cross-check à read-time.

---

## TL;DR — checklist nouveau projet Flutter iOS

À copier-coller au début d'un nouveau projet **avant la première sideload** :

- [ ] `ios/Podfile` committé avec `PERMISSION_*` macros pour chaque
      `Permission.foo.request()` qu'on appelle (§1)
- [ ] `Info.plist`: `CFBundleName` en camelCase ou avec espaces, **pas**
      d'underscore (§2)
- [ ] `FileLogger.bootstrap()` appelé avant `runApp()` dans `main.dart` (§3.2)
- [ ] `FileLoggerLifecycleObserver` enregistré via `addObserver` (§3.8)
- [ ] `kMaxLogsDirBytes` dans `lib/config/constants.dart` (§3.6)
- [ ] `_onRecord` synchrone (`writeStringSync` + `flushSync`) — JAMAIS async (§3.5)
- [ ] `RandomAccessFile` ouvert en `FileMode.writeOnlyAppend` (§3.10)
- [ ] Catch only `FileSystemException` dans `_onRecord` + null le `_raf` sur erreur (§3.5)
- [ ] Sur erreur : log via `dart:developer` `log()`, **pas** via `Logger.shout` (§3.5)
- [ ] CI workflow : `dart format lib/l10n/` **avant** le check
      `--set-exit-if-changed` (§4.1)
- [ ] Imports l10n: `package:<project>/l10n/...`, pas `flutter_gen` (§4.1)
- [ ] `PrivacyInfo.xcprivacy` à jour avec les Required-Reason API codes (§4.3)

**Si l'app a besoin de GPS background** (ajout au-dessus) :
- [ ] `Info.plist` : `NSLocationAlwaysAndWhenInUseUsageDescription` +
      `UIBackgroundModes: [location, fetch]` (§5.5)
- [ ] Chaîne `notification → whenInUse → always` dans cet ordre
      (silently-ignored sinon sur Android 10+) (§5.3)
- [ ] `AppleSettings(allowBackgroundLocationUpdates: true,
      pauseLocationUpdatesAutomatically: false, ...)` côté geolocator (§5.7)
- [ ] `AndroidManifest` : `ACCESS_BACKGROUND_LOCATION` +
      `FOREGROUND_SERVICE_LOCATION` (Android 14+) +
      `POST_NOTIFICATIONS` (§5.5)
- [ ] Écran `/permissions/denied` avec auto-resume hook
      `WidgetsBindingObserver.didChangeAppLifecycleState` (§5.6)
