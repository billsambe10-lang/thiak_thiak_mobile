# Base de données Supabase

L'application utilise Supabase (PostgreSQL et Auth par SMS) lorsque les deux
variables de compilation `SUPABASE_URL` et `SUPABASE_PUBLISHABLE_KEY` sont
fournies.
Sans elles, l'application reste en mode démo : les courses sont en mémoire et
les demandes motard ne sont pas enregistrées.

## Initialisation

1. Créez un projet sur [Supabase](https://supabase.com/).
2. Dans **SQL Editor**, exécutez le fichier
   `supabase/migrations/20261026000000_initial_schema.sql`.
3. Exécutez ensuite
   `supabase/migrations/20261030000000_motorist_workspace.sql`.
4. Dans **Authentication > Providers**, activez Phone et configurez un
   fournisseur SMS. Pour les tests, configurez également les numéros de test
   SMS Supabase.
5. Lancez l'application en passant l'URL du projet et sa clé publique anon :

   ```powershell
   flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
   ```

La clé publishable peut être incluse dans une application mobile car les
droits sont limités par les politiques RLS. Ne mettez jamais une clé `service_role`
dans l'application.

## Tables et accès

- `profiles` : profil associé automatiquement à chaque utilisateur Auth,
  avec le rôle `client`, `motard` ou `admin`.
- `courses` : commandes moto et livraisons, avec leur statut, tarif, coordonnées
  et distance éventuelle.
- `motorist_applications` : demandes d'inscription et leur statut de traitement.
- `motorist_presence` : disponibilité et dernière position partagée des motards.
- `motorist_course_offers` : offres de courses, diffusées par Supabase Realtime.

## Google Maps (Android et iOS)

Activez **Maps SDK for Android** et **Maps SDK for iOS** dans Google Cloud
Platform et configurez la facturation. Créez une clé distincte pour chaque
plateforme, avec restriction d'application : identifiant Android
`com.example.thiak_thiak_mobile` et empreinte SHA-1 pour Android, identifiant de
bundle `com.example.thiakThiakMobile` pour iOS. Limitez aussi chaque clé à
l'API Maps SDK correspondante.

- Android : ajoutez `googleMapsAndroidApiKey=VOTRE_CLE_ANDROID` dans
  `android/local.properties` (fichier local non versionné), ou fournissez la
  variable d'environnement `GOOGLE_MAPS_ANDROID_API_KEY`.
- iOS : copiez
  `ios/Flutter/GoogleMaps.xcconfig.example` vers
  `ios/Flutter/GoogleMaps.xcconfig`, puis remplacez la valeur par votre clé
  iOS. Ce fichier est ignoré par Git.

Ces clés SDK sont intégrées à l'application compilée : leur protection repose
sur les restrictions d'application et d'API, pas sur leur confidentialité.
Une éventuelle clé pour Google Routes/Traffic doit être distincte, stockée
uniquement côté serveur, et ne doit jamais être ajoutée à l'application.

## Espace motard

L'espace motard est accessible uniquement si le compte a le rôle `motard` et
une demande d'inscription `approved`. Après validation de la demande, un
administrateur doit aussi attribuer le rôle depuis le SQL Editor :

```sql
update public.profiles
set role = 'motard'
where phone = '+221771234567';
```

Le tableau permet au motard approuvé d'activer sa disponibilité, de partager sa
position pendant que l'écran est ouvert (et le marque indisponible à sa fermeture)
et de répondre aux offres reçues. La
création des offres par le système d'attribution automatique (IA/Google Routes)
et les notifications push nécessitent encore un service serveur et leur
configuration ; la migration fournit le schéma et l'accès temps réel, mais
n'active pas à elle seule un agent de dispatch.

Les clients ne peuvent lire que leurs propres courses. Les motards approuvés ne
peuvent lire que leurs offres et les courses associées. L'accès administrateur
est protégé par RLS ; après avoir créé un compte admin, attribuez son rôle depuis
le SQL Editor de Supabase (jamais depuis l'application cliente) :

```sql
update public.profiles
set role = 'admin'
where phone = '+221771234567';
```

Les comptes d'administration actuellement enregistrés localement par
l'application ne sont pas migrés automatiquement. Les rôles et règles d'accès
admin de la base sont préparés, mais la gestion des courses et des demandes
depuis l'interface admin existante reste à raccorder. La création d'un projet
Supabase et l'exécution du SQL restent à faire depuis votre compte ; les
identifiants du projet ne sont pas présents dans le dépôt.
