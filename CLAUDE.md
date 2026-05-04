# Claude Code — Règles du projet

### Licences interdites

Les dépendances sous les licences suivantes sont **interdites**, sans exception :

- **GPL** (toutes versions : GPLv2, GPLv3, LGPL avec linking statique, etc.)
- **AGPL** (toutes versions)
- Toute licence "copyleft fort" qui tenterait d'imposer sa propre licence au projet hôte

Raison : ces licences sont incompatibles avec la GOSL et contamineraient le projet entier.

### Licences acceptées

- **MIT**
- **BSD** (2-clause, 3-clause)
- **Apache 2.0**
- **Unlicense**, **CC0**
- **ISC**, **zlib**

En cas de doute sur une licence (custom, double licence, dual-licensing avec option GPL), **ne pas ajouter la dépendance** et demander confirmation.

### Audit obligatoire

**Toute dépendance doit être auditée avant ajout.** Pas d'exception, même pour les packages "évidents" ou populaires.

Checklist d'audit pour chaque nouvelle dépendance :

1. **Licence** vérifiée sur pub.dev ET dans le repo source (parfois divergence)
2. **Télémétrie** : inspection du code source pour détecter tout appel réseau automatique, tout SDK d'analytics, tout reporting de crash non-opt-in
3. **Dépendances transitives** : vérifier la chaîne complète (`flutter pub deps`), une dépendance MIT peut tirer une dépendance GPL
4. **Maintenance** : dernière release, nombre de contributeurs, issues ouvertes critiques
5. **Plateforme** : compatible iOS ET Android (le projet est cross-platform)

Documenter chaque audit dans `DEPENDENCIES.md` à la racine avec :
- Nom du package + version
- Licence
- Raison de l'ajout
- Résultat de l'audit télémétrie (réseau out/in, SDK embarqués)
- Date de l'audit

### Télémétrie — interdiction stricte

**Aucune dépendance ne doit émettre de données vers un système externe sans action explicite de l'utilisateur pour cette transmission spécifique.**

Ceci inclut, et ne se limite pas à :

- **Analytics** : Firebase Analytics, Google Analytics, Mixpanel, Amplitude, Segment, etc.
- **Crash reporting automatique** : Firebase Crashlytics, Sentry (en mode auto), Bugsnag, Instabug
- **Performance monitoring** : Firebase Performance, New Relic, Datadog RUM
- **A/B testing** : Firebase Remote Config (côté télémétrie), Optimizely
- **SDKs publicitaires** : AdMob, Facebook Audience Network, etc.
- **Heatmaps / session replay** : Hotjar, FullStory, LogRocket
- **SDKs d'attribution** : AppsFlyer, Adjust, Branch, Kochava

Inspecter systématiquement les packages qui ajoutent ces comportements par défaut, y compris lorsqu'ils sont présentés comme "optionnels" mais activés d'office.

### Cas limites

- **Crash reporting local** (écriture fichier, pas de réseau) : **autorisé**
- **Logging local** (stdout, fichier, Logcat, OSLog) : **autorisé**
- **Appels réseau à l'initiative de l'utilisateur** (télécharger une ressource qu'il a demandée, envoyer un formulaire qu'il a rempli, etc.) : **autorisés**
- **Update checks automatiques** : **interdits** sauf si explicitement demandés par l'utilisateur à chaque vérification
- **SDKs qui "phone home" pour valider une licence / un token** : **interdits**

### Priorité aux plugins officiels Flutter

Pour les fonctionnalités natives (caméra, GPS, audio, permissions, stockage, etc.), privilégier les packages officiels de `flutter.dev` ou largement adoptés (`camera`, `geolocator`, `record`, `permission_handler`, `shared_preferences`, `path_provider`). Ils sont sous BSD-3-Clause, audités par la communauté, et sans télémétrie.

Éviter les libs communautaires obscures qui cumulent souvent : licence douteuse, maintenance faible, et parfois SDKs tiers embarqués.

## Conventions de code Flutter/Dart

### Docstring policy

- Docstring (`///`) concise pour chaque classe, fonction et méthode publique
- Docstring pour les fonctions privées quand le nom + signature n'est pas auto-explicatif
- Les docstrings disent QUOI et POURQUOI, pas les types (déjà dans la signature)
- Quand tu modifies une fonction sans docstring, ajoute-la

### Naming

- Variables et fonctions au **singulier**, jamais au pluriel (sauf listes, voir ci-dessous)
- Maps → `valueByKey` (ex: `userById`)
- Sets → suffixe `Set` (ex: `activeUserSet`)
- Lists → suffixe `s` (ex: `users`)
- Pas d'abréviations, utiliser des noms descriptifs même longs
- Dart = `camelCase` pour variables/fonctions, `PascalCase` pour types/classes

### Naming de chemins

- `xxxFilename` : chemin absolu (ex: `/home/user/data/config.json`)
- `xxxFileName` : nom de fichier sans extension (ex: `config`)
- `xxxBasename` : nom de fichier avec extension (ex: `config.json`)
- `xxxDir` : chemin d'un dossier

Toujours utiliser `p.join()` du package `path`, jamais de concaténation manuelle avec `/` ou `\`.

### Structure

- Modulaire, maintenable, faible couplage
- Fonctions et classes bien nommées (même longues) pour séparer les responsabilités
- Séparer strictement code applicatif (UI, widgets, navigation) et code métier (logique business, modèles, services)
- Découpler ce qui peut l'être, faire des abstractions. Exemple : si on utilise une lib tierce pour du rendu PDF, exposer une interface métier qu'on peut réimplémenter sans toucher au reste de l'app

### Error handling

Jamais d'erreur complètement silencieuse (pas de catch vide)

Distinguer trois niveaux :

 - Bugs de programmation (null inattendu, invariant violé) : laisser propager jusqu'au handler top-level qui dump la stacktrace
 - Erreurs externes attendues (réseau, I/O, parsing) : catch, log, feedback UI approprié, ne pas crasher
 - Erreurs non-critiques en périphérie : catch + log dans le fichier de logs, pas de feedback UI

Le handler top-level (runZonedGuarded + FlutterError.onError) reste en place comme filet de sécurité pour ce qui passe à travers

### Async / BuildContext

- Toujours `async`/`await`, pas de `.then()` sauf justification claire
- Après tout `await` dans un widget, vérifier `if (!context.mounted) return;` avant d'utiliser le `BuildContext`
- Jamais passer un `BuildContext` à travers une frontière async sans ce check

### Longueur de ligne

- 160 caractères max, pas de retour à la ligne avant 160 chars
- `dart format` avec la config adaptée (par défaut 80 en Dart, à override)

### is-checks et polymorphisme

- Éviter les chaînes de `is TypeA` / `is TypeB`, ça indique généralement un besoin de polymorphisme (classes abstraites, sealed classes, pattern matching sur des sealed types)
- Parfois justifié, évaluer au cas par cas

### Magic numbers

- Aucun number magique. Stocker dans une variable nommée (locale si usage unique, constante partagée sinon)
- Pour les constantes partagées, fichier dédié : `lib/config/constants.dart`
- Pour les index de liste : même si local, extraire en variable nommée qui décrit ce que l'index représente

### Workarounds

- Tout workaround ou hack doit avoir un commentaire au-dessus expliquant pourquoi il est là et ce qu'il fait

### Type hints

- **Obligatoires partout**. Config `analysis_options.yaml` en mode strict :
  - `strict-casts: true`
  - `strict-inference: true`
  - `strict-raw-types: true`
- Jamais de `dynamic` sans justification explicite dans un commentaire
- Préférer `Object?` à `dynamic` quand on veut vraiment un type inconnu
- Null safety stricte, pas de `!` sans assertion préalable ou check de null

### Dependency Injection

- Services externes injectés via constructeur (pas de singletons globaux cachés)
- Rend les tests unitaires triviaux (mock injection)
- Pour l'état applicatif : un seul système de state management sur tout le projet (à choisir en début de projet et à documenter)

### Logging

- Logger configurable, avec un flag de build (`--dart-define=DEBUG=true`) et un menu debug dans l'app si build sans le flag pour que le user puisse l'activer
- Logs dans `<app_documents_dir>/logs/yyyymmdd_hhmm.ss_logs.txt`
- En mode `--debug`, logger chaque appel de fonction/méthode des couches métier, les infos importantes, et timer les opérations coûteuses
- En production, logger uniquement les erreurs et les events métier importants
- Utiliser `dart:developer` `log()` ou le package `logging`, pas `print()`

### Idempotence

- Quand c'est possible, rendre les opérations idempotentes

### Timeouts

- Timeout obligatoire sur tous les appels externes (HTTP, DB, plugins natifs qui peuvent pendre)
- Valeurs dans `lib/config/constants.dart`, pas hardcodées dans le code d'appel

### Ordre des collections externes

- Ne jamais compter sur l'ordre des résultats retournés par une lib tierce, même si elle semble stable
- Si l'ordre importe, trier explicitement

### Mutation de collection

- Ne jamais muter une collection pendant son itération
- Collecter les modifications dans une liste séparée, appliquer après la boucle

### Secrets

- Via `--dart-define=KEY=value` au build, ou via un fichier `.env` (gitignored) avec `flutter_dotenv`
- Jamais de secret en dur dans le code
- Choisir les noms de variables d'env et me les demander pour les remplir

### Pin des versions

- Toutes les dépendances `pubspec.yaml` doivent être **strictement pinned** (ex: `http: 1.2.0`, pas `http: ^1.2.0`)
- Le `^` autorise les mises à jour minor, ce qui peut introduire des changements non audités
- `flutter pub get` doit être reproductible
- `pubspec.lock` committé dans le repo

### Early returns

- Privilégier early return aux IF imbriqués
- Guard clauses en début de fonction

### Navigation GoRouter

- Par défaut, utiliser `context.push()` pour toute navigation vers un écran depuis lequel l'utilisateur doit pouvoir revenir en arrière (détail de session, écran de paramètres, sous-écran depuis un menu, etc.)
- `context.go()` **remplace la pile de navigation** : le bouton back du système ferme l'app au lieu de revenir à l'écran précédent. Ne l'utiliser que pour une transition qui doit réinitialiser la pile volontairement (ex: logout, fin d'un tunnel de permission, retour forcé à la racine après action terminale)
- Règle rapide : si le mot "retour" a du sens dans l'UX → `push`. Si c'est un reset complet de navigation → `go`

### Structure de fichiers

- Pas de logique exécutable dans les `library` files ou fichiers d'export
- `lib/main.dart` contient uniquement le bootstrap + `runApp()`
- Pas d'effets de bord à l'import (pas de code au top-level d'un fichier en dehors des déclarations)

### Wrappers et delegation

- Pas de delegation wrappers qui se contentent de proxy des appels. Si 80%+ des méthodes de B sont `_a.sameMethod(sameArgs)`, c'est de l'architecture bidon. Faire conformer A à l'interface directement
- Wrapper uniquement si logique ajoutée (transformation, cache, error handling)
- Toujours champs publics par défaut. Passer à getter/setter uniquement le jour où tu ajoutes réellement de la logique. Pas de getter/setter cargo cult prophylactique.

### DTO

- Ne crée un objet de transport que s'il porte une sémantique distincte de l'entité : sous-ensemble, agrégation, projection, frontière avec une source externe non maîtrisée
- Un objet qui réplique 1:1 une entité n'est pas un DTO, c'est un doublon → utiliser l'entité directement
- Si un vrai DTO est justifié, documenter explicitement pourquoi dans une docstring

### Commentaires

- Expliquent le **pourquoi**, pas le **quoi**
- Pas de commentaire qui narre une ligne évidente (`// save to database` au-dessus de `db.save(entity)` est inutile)
- Commentaires utiles : expliquer un choix non évident, un hack, une contrainte externe, une subtilité de la lib utilisée
- si tu as besoin de commenter un bloc de code pour que ça soit lisible c'est que ce bloc de code aurait du etre dans une fonction privé nommée

## Conventions Flutter-spécifiques

### Widgets

- `const` constructors partout où possible (performance, rebuild optimization)
- Préférer `StatelessWidget` par défaut, `StatefulWidget` uniquement si état local vraiment nécessaire
- Pas de logique métier dans `build()` : le `build()` décrit l'UI, point
- Extraire les sous-widgets dès qu'un `build()` dépasse ~50 lignes, ou dès qu'une partie est réutilisable
- Pas de `setState()` dans les méthodes async sans check `mounted` préalable

### State management

- **Un seul système** pour tout le projet (à choisir et documenter dès le début)
- Ne pas mélanger `Provider` + `Riverpod` + `Bloc` dans le même projet
- `setState` reste OK pour de l'état strictement local et éphémère (toggle d'un widget)

### Plateformes

- Tester systématiquement sur Android (dev principal) et sur desktop Windows (`flutter run -d windows`) pour la logique
- Build iOS déclenché automatiquement en CI à chaque push sur la branche principale (surveillance de la compilation)
- Test iOS réel sur device (sideload) par paliers, pas par feature individuelle, typiquement :

 - En fin de chantier cohérent (groupe de features liées)
 - Avant chaque refactoring important (checkpoint connu comme fonctionnel)
 - Systématiquement quand on touche aux APIs natives (caméra, GPS, audio, permissions, système de fichiers) — mais pas forcément dans la foulée, ça peut attendre la prochaine session de test iOS


- Le coût d'un test iOS (temps CI + download artifact + sideload) justifie de les grouper

### Configuration `Info.plist` (iOS)

Même si le développement se fait principalement sous Windows (Android + desktop), maintenir `Info.plist` à jour au fur et à mesure pour les permissions iOS :

- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSLocationWhenInUseUsageDescription` / `NSLocationAlwaysAndWhenInUseUsageDescription`
- Autres selon les features ajoutées

Ne pas découvrir les requirements iOS à la fin du projet.

## Git & CI

- `gh` CLI est installé et authentifié sur cette machine
- Solo dev : une seule personne travaille sur ce repo
- Une seule branche : `main` (pas de feature branches, pas de PRs internes)
- Claude est autorisé à **pusher directement sur `main`** quand approprié (commits atomiques, tests verts localement)
- Claude est autorisé à consulter l'état des GitHub Actions via `gh` (`gh run list`, `gh run view`, `gh run watch`, logs des jobs) pour itérer pendant les phases sans attendre un retour manuel
- Pas de force-push sur `main` sans demande explicite

## Bug investigation workflow

Quand on travaille sur des bugs, utiliser un **subagent dédié par bug** pour préserver le contexte de la conversation principale. Le subagent lit les logs, les fichiers sources, diagnostique, et propose un fix. L'orchestrateur résume le résultat et commite. Ça évite de polluer le contexte principal avec des centaines de lignes de logs et de code.

# MIRL solution

la solution doit etre shader agnostic puisque dans l'application reelle plusieur shader different seront utilisé
