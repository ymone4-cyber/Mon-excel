Moné Excel · plateforme Next.js

V2 Next.js 14 pour Moné Excel : accueil animé, Formulothèque Excel 365, demande de déverrouillage Wave vérifiable et espace propriétaire Supabase.

## Démarrer

1. Installer Node.js 20+ puis lancer `npm install`.
2. Copier `.env.example` vers `.env.local` et renseigner l’URL et la clé publique publishable de Supabase. Le tarif convenu est de **5 000 FCFA** et se règle avec `NEXT_PUBLIC_PREMIUM_PRICE_XOF`.
3. Dans Supabase, autoriser `public` dans **Project Settings → API → Exposed schemas** pour que `supabase-js` puisse joindre les tables. Les GRANT de la migration restent limités à `authenticated` et RLS contrôle chaque ligne.
4. Exécuter `supabase/migrations/0001_mone_excel.sql` dans le SQL Editor Supabase. Elle crée les profils, demandes Wave, tentatives et scores avec RLS.
5. Après création du compte propriétaire, appliquer la commande de promotion indiquée dans la migration. Le rôle `owner` est attribué manuellement, jamais depuis le formulaire d’inscription.
6. Lancer `npm run dev` puis ouvrir `http://localhost:3000`.

## Connexion Supabase pour Codex

Le fichier `.mcp.json` cible uniquement le projet Moné Excel et limite les outils aux opérations de base de données et à la documentation. Autorise la connexion OAuth Supabase dans Codex après rechargement du projet si la fenêtre de connexion ne s’ouvre pas automatiquement. Aucun jeton ni mot de passe n’est stocké dans le dépôt.

## Accès et paiements

- Les membres commencent avec un accès gratuit à 8 formules. L’accès complet dépend de `profiles.access_tier = 'premium'`.
- L’apprenant envoie le transfert Wave au numéro fourni, saisit la référence de transaction et reçoit un statut « en attente ». La saisie d’une référence ne déverrouille jamais le contenu.
- Un propriétaire vérifie le transfert puis valide la demande dans `/owner`. La fonction SQL contrôle à nouveau le rôle `owner` avant d’élever le compte.
- Pour activer le premier compte propriétaire, remplace `<AUTH_USER_UUID>` par l’UUID Supabase du propriétaire et exécute la commande SQL indiquée dans la migration. Ne place jamais une clé `service_role` dans le navigateur.
- `/owner` est la version personnelle où la suite et les 50 formules sont déverrouillées. L’autorisation est lue depuis Supabase côté serveur.
- Les tentatives et leurs scores sont enregistrés en lignes append-only par utilisateur. Les résultats restent des données d’entraînement personnelles ; ils ne constituent pas une preuve officielle de réussite à Certiport.
- Dans les réglages Supabase Auth, active la confirmation d’adresse e-mail et configure la politique de mot de passe pour imposer la même validation forte que le formulaire.

## Paiement Wave

Le prototype utilise le transfert Wave vers le numéro communiqué et une validation manuelle par référence. Il n’annonce pas un paiement automatiquement vérifié. Pour passer plus tard au Checkout API, il faut un compte Wave Business et garder les clés API exclusivement côté serveur ; les clés ne doivent jamais apparaître dans le JavaScript client.

## Formulothèque

Le mini-moteur calcule RECHERCHEX/XLOOKUP, EQUIVX/XMATCH, EQUIV, FILTRE/FILTER, TRIER/SORT, UNIQUE, SEQUENCE, FRACTIONNER.TEXTE/TEXTSPLIT, ASSEMB.V/VSTACK, SOMME/SUM, MOYENNE/AVERAGE, MAX, MIN, LET avec expressions simples et LAMBDA appliquée à une valeur. Les autres formules affichent leur syntaxe et exemple sans prétendre les calculer dans ce mini moteur.
