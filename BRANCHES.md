# Stratégie de branches — FinTrack

## Vue d'ensemble

```
main ────────────────────────────────────────► Production (stable, version payante)
  │
  └── develop ─────────────────────────────► Intégration (nouvelles fonctionnalités)
        │
        ├── feature/nom-feature-1 ──────────► Feature en cours
        ├── feature/nom-feature-2
        └── fix/nom-bug

free ────────────────────────────────────────► Version gratuite (figée)
```

---

## Branches

### `main` — Production
- **Contenu** : version stable, toutes les fonctionnalités premium
- **Protégée** : merge uniquement depuis `develop` via Pull Request
- **Déployée sur** : App Store (futur), TestFlight
- **Qui merge** : Régis uniquement, après validation complète

### `develop` — Développement
- **Contenu** : dernière version stable + nouvelles fonctionnalités intégrées
- **Source** : créée depuis `main`
- **Fusionne vers** : `main` quand une version est prête
- **Usage** : base de toutes les branches `feature/*`

### `feature/*` — Fonctionnalités
- **Nommage** : `feature/nom-court-descriptif` (ex: `feature/csv-import`)
- **Durée de vie** : le temps de développer la feature, puis supprimée après merge
- **Créée depuis** : `develop`
- **Fusionne vers** : `develop`

### `fix/*` — Correctifs
- **Nommage** : `fix/description-du-bug` (ex: `fix/notification-section`)
- **Créée depuis** : `main` si bug critique en prod, sinon `develop`
- **Fusionne vers** : `main` ET `develop` si hotfix prod

### `free` — Version gratuite (figée)
- **Contenu** : snapshot de l'app sans les features premium
- **État** : figée, pas de développement actif
- **Usage futur** : si on veut publier une version freemium

---

## Workflow quotidien

```bash
# 1. Démarrer une nouvelle feature
git checkout develop
git pull origin develop
git checkout -b feature/ma-nouvelle-feature

# 2. Développer, commiter
git add -A
git commit -m "feat: description"

# 3. Merger dans develop
git checkout develop
git merge feature/ma-nouvelle-feature
git push origin develop

# 4. Supprimer la branche feature
git branch -d feature/ma-nouvelle-feature
git push origin --delete feature/ma-nouvelle-feature

# 5. Quand develop est stable → merger dans main
git checkout main
git merge develop
git push origin main
```

## Conventions de commit

```
feat:     nouvelle fonctionnalité
fix:      correctif de bug
refactor: refactoring sans changement de comportement
chore:    maintenance, dépendances, config
docs:     documentation uniquement
```

---

## Features en cours (sur develop)

| Feature | Statut | Branche |
|---------|--------|---------|
| Budgets par catégorie | ✅ Mergé | — |
| Taux de change temps réel | ✅ Mergé | — |
| Virements entre comptes | ✅ Mergé | — |
| Dashboard personnalisable | ✅ Mergé | — |
| Connexion Plaid bancaire | ✅ Mergé | — |
| EntitlementManager StoreKit 2 | ✅ Mergé | — |

## Features à venir

| Feature | Priorité |
|---------|----------|
| Import CSV/OFX | Haute |
| WidgetKit écran d'accueil | Bloqué (Developer Program) |
| CloudKit sync | Bloqué (Developer Program) |
| Mode foyer multi-utilisateurs | Moyenne |
| Commandes vocales (Speech + Claude) | Basse |


## Tiers de fonctionnalités

| Fonctionnalité | 🆓 Gratuit | 🔒 Pro ($19,99) | 💳 Plaid ($3,99/mois) |
|----------------|:----------:|:---------------:|:---------------------:|
| Comptes illimités (manuel) | ✅ | ✅ | ✅ |
| Transactions manuelles | ✅ | ✅ | ✅ |
| Dashboard basique | ✅ | ✅ | ✅ |
| Dashboard personnalisable | ❌ | ✅ | ✅ |
| Budgets | ❌ | ✅ | ✅ |
| Prêts & marges | ❌ | ✅ | ✅ |
| Projets d'épargne | ❌ | ✅ | ✅ |
| Récurrences | ❌ | ✅ | ✅ |
| Virements | ❌ | ✅ | ✅ |
| Analytiques & graphiques | ❌ | ✅ | ✅ |
| Taux de change live | ❌ | ✅ | ✅ |
| Export CSV | ❌ | ✅ | ✅ |
| Sync bancaire Plaid | ❌ | ❌ | ✅ |

StoreKit 2 product IDs:
- `ca.regis.fintrack.pro` — Non-consumable, $19,99 CAD
- `ca.regis.fintrack.plaid_monthly` — Auto-renewable, $3,99 CAD/mois
