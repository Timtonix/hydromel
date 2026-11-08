# Hydromel Merhzinsa — Prévente de la Coopérative

Application web **Elixir / Phoenix (LiveView)** pour la réservation de bouteilles d'hydromel (**33cl** et **75cl**) de la coopérative **Merhzinsa**.

## Fonctionnalités

- **Espace Public (`/`)** :
  - Choix des quantités de bouteilles **33cl** et **75cl** avec calcul automatique du montant total en direct.
  - Saisie du prénom, nom, adresse e-mail, choix du mode de règlement hors-ligne (**Wero**, **PayPal**, **Espèces**) et commentaire optionnel sur les modalités de retrait.
  - Envoi automatique d'un **e-mail récapitulatif** (HTML + Texte) avec la référence unique de commande (`MERH-XXXXXX`) et les consignes de paiement.
- **Espace Coopérative (`/coop`)** :
  - Accès sécurisé par mot de passe partagé (`COOP_PASSWORD`, par défaut `merhzinsa` en local).
  - **Tableau de bord en temps réel** : nombre de commandes actives, bouteilles 33cl/75cl réservées, stocks restants, volume total en litres, chiffre d'affaires encaissé vs attendu.
  - **Gestion des commandes** : recherche instantanée, filtres (`À encaisser`, `Payées`, `À récupérer`, `Récupérées`, `Annulées`), bascule en 1 clic du statut de paiement et de retrait, et **Export CSV**.
  - **Configuration dynamique** : modification à chaud des prix (33cl / 75cl), des stocks disponibles, du lien PayPal, des instructions Wero / Cash et de l'ouverture de la prévente.

---

## 1. Prérequis et installation de PostgreSQL en local (Ubuntu / Debian)

Si PostgreSQL n'est pas encore installé sur votre machine de développement :

```bash
sudo apt update
sudo apt install -y postgresql postgresql-contrib
sudo systemctl enable --now postgresql

# Définir le mot de passe 'postgres' pour l'utilisateur local par défaut de Phoenix :
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"
```

## 2. Lancement en développement

```bash
mix setup
mix phx.server
```

- **Site public de réservation** : [http://localhost:4000](http://localhost:4000)
- **Espace coopérative** : [http://localhost:4000/coop](http://localhost:4000/coop) (mot de passe par défaut en dev : `merhzinsa`)
- **Boîte mail de prévisualisation (`Swoosh`)** : [http://localhost:4000/dev/mailbox](http://localhost:4000/dev/mailbox)

---

## 3. Déploiement sur votre VPS avec Dokploy

Le projet inclut un `Dockerfile` multi-stage optimisé ainsi que le script `rel/overlays/bin/server` qui exécute automatiquement les migrations Ecto (`./migrate`) à chaque démarrage du conteneur.

1. Dans **Dokploy**, créez une base de données **PostgreSQL** et copiez son `Internal Connection URL`.
2. Créez une application de type **Dockerfile** pointant sur ce dépôt Git (port exposé : `4000`, healthcheck : `/up`).
3. Configurez les variables d'environnement dans Dokploy (voir `.env.example`) :
   - `DATABASE_URL` : l'URL PostgreSQL interne de Dokploy (`ecto://...`)
   - `SECRET_KEY_BASE` : générée avec `mix phx.gen.secret`
   - `PHX_HOST` : votre nom de domaine (ex: `hydromel.merhzinsa.fr`)
   - `COOP_PASSWORD` : le mot de passe choisi pour l'espace `/coop`
   - `MAILER_FROM_EMAIL` & `MAILER_FROM_NAME`
   - `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS` (ou `BREVO_API_KEY`) pour l'envoi des e-mails récapitulatifs.
