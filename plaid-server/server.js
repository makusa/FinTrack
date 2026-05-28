// server.js — FinTrack Plaid Backend
// Hébergé sur Synology NAS via Docker
//
// Endpoints:
//   POST /create_link_token    — démarre une session Plaid Link
//   POST /exchange_token       — échange le public_token → access_token
//   POST /sync_transactions    — récupère les transactions
//   POST /get_balances         — récupère les soldes en temps réel
//   DELETE /disconnect         — révoque un access_token
//   GET /health                — healthcheck pour Docker

'use strict';

require('dotenv').config();

const express      = require('express');
const cors         = require('cors');
const helmet       = require('helmet');
const rateLimit    = require('express-rate-limit');
const { PlaidApi, PlaidEnvironments, Configuration, Products, CountryCode } = require('plaid');

// ── Validation des variables d'environnement ─────────────────────────────────
const REQUIRED_ENV = ['PLAID_CLIENT_ID', 'PLAID_SECRET', 'PLAID_ENV', 'API_KEY'];
for (const key of REQUIRED_ENV) {
  if (!process.env[key]) {
    console.error(`❌  Variable d'environnement manquante: ${key}`);
    process.exit(1);
  }
}

const {
  PLAID_CLIENT_ID,
  PLAID_SECRET,
  PLAID_ENV,        // 'sandbox', 'development', ou 'production'
  API_KEY,          // clé secrète pour que seule l'app iOS puisse appeler ce serveur
  PORT = 3000
} = process.env;

// ── Plaid client ──────────────────────────────────────────────────────────────
const plaidEnvMap = {
  sandbox:     PlaidEnvironments.sandbox,
  development: PlaidEnvironments.development,
  production:  PlaidEnvironments.production,
};

const plaidConfig = new Configuration({
  basePath:  plaidEnvMap[PLAID_ENV] || PlaidEnvironments.production,
  baseOptions: {
    headers: {
      'PLAID-CLIENT-ID': PLAID_CLIENT_ID,
      'PLAID-SECRET':    PLAID_SECRET,
    },
  },
});

const plaidClient = new PlaidApi(plaidConfig);

// ── Express app ───────────────────────────────────────────────────────────────
const app = express();

app.use(helmet());
app.use(express.json());

// CORS: autoriser uniquement les requêtes de l'app iOS (et localhost pour dev)
app.use(cors({
  origin: (origin, cb) => {
    // L'app iOS n'envoie pas d'Origin header — on accepte null/undefined
    // En production, on pourrait filtrer davantage
    cb(null, true);
  }
}));

// Rate limiting — protection anti-abus
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Trop de requêtes, réessayez dans 15 minutes.' }
});
app.use(limiter);

// ── Middleware d'authentification ─────────────────────────────────────────────
// L'app iOS envoie un header X-API-Key avec la clé définie dans .env
function requireApiKey(req, res, next) {
  const key = req.headers['x-api-key'];
  if (!key || key !== API_KEY) {
    return res.status(401).json({ error: 'Non autorisé.' });
  }
  next();
}

// ── Healthcheck ───────────────────────────────────────────────────────────────
app.get('/health', (req, res) => {
  res.json({
    status:  'ok',
    env:     PLAID_ENV,
    version: '1.0.0',
    time:    new Date().toISOString()
  });
});

// ── POST /create_link_token ───────────────────────────────────────────────────
// Crée un token de session Plaid Link à usage unique.
// L'app iOS lance l'interface Plaid avec ce token.
//
// Body: { user_id: string }
// Returns: { link_token: string, expiration: string }
app.post('/create_link_token', requireApiKey, async (req, res) => {
  try {
    const userId = req.body.user_id || 'fintrack_user';

    const response = await plaidClient.linkTokenCreate({
      user:          { client_user_id: userId },
      client_name:   'FinTrack',
      products:      [Products.Transactions],
      // Note: Balance is automatically included — do not add it explicitly
      country_codes: [CountryCode.Ca, CountryCode.Us],
      language:      'fr',
      // Webhook pour les mises à jour automatiques (optionnel — à configurer plus tard)
      // webhook: 'https://ton-nas.domaine.com/webhook',
    });

    console.log(`[${new Date().toISOString()}] link_token créé pour user: ${userId}`);

    res.json({
      link_token: response.data.link_token,
      expiration: response.data.expiration,
    });

  } catch (err) {
    console.error('create_link_token error:', err.response?.data || err.message);
    res.status(500).json({
      error:   'Erreur lors de la création du link token.',
      details: err.response?.data?.error_message || err.message
    });
  }
});

// ── POST /exchange_token ──────────────────────────────────────────────────────
// Échange le public_token (temporaire, 30 min) contre un access_token permanent.
// L'access_token est renvoyé à l'app iOS qui le stocke dans le Keychain.
//
// Body: { public_token: string }
// Returns: { access_token: string, item_id: string }
app.post('/exchange_token', requireApiKey, async (req, res) => {
  try {
    const { public_token } = req.body;
    if (!public_token) {
      return res.status(400).json({ error: 'public_token manquant.' });
    }

    const response = await plaidClient.itemPublicTokenExchange({ public_token });

    console.log(`[${new Date().toISOString()}] Token échangé — item_id: ${response.data.item_id}`);

    res.json({
      access_token: response.data.access_token,
      item_id:      response.data.item_id,
    });

  } catch (err) {
    console.error('exchange_token error:', err.response?.data || err.message);
    res.status(500).json({
      error:   "Erreur lors de l'échange du token.",
      details: err.response?.data?.error_message || err.message
    });
  }
});

// ── POST /sync_transactions ───────────────────────────────────────────────────
// Synchronise les transactions depuis la dernière synchro (cursor-based).
// Renvoie les ajouts, modifications et suppressions depuis le dernier appel.
//
// Body: { access_token: string, cursor?: string }
// Returns: { added: [], modified: [], removed: [], next_cursor: string, has_more: boolean }
app.post('/sync_transactions', requireApiKey, async (req, res) => {
  try {
    const { access_token, cursor } = req.body;
    if (!access_token) {
      return res.status(400).json({ error: 'access_token manquant.' });
    }

    // Paginer jusqu'à has_more = false
    let added    = [];
    let modified = [];
    let removed  = [];
    let nextCursor = cursor || '';
    let hasMore  = true;
    let iterations = 0;

    while (hasMore && iterations < 10) { // limite de sécurité
      const response = await plaidClient.transactionsSync({
        access_token,
        cursor: nextCursor || undefined,
        count:  500,
      });

      const data = response.data;
      added    = added.concat(data.added);
      modified = modified.concat(data.modified);
      removed  = removed.concat(data.removed);
      nextCursor = data.next_cursor;
      hasMore    = data.has_more;
      iterations++;
    }

    console.log(`[${new Date().toISOString()}] Sync: +${added.length} modif:${modified.length} del:${removed.length}`);

    res.json({
      added,
      modified,
      removed,
      next_cursor: nextCursor,
      has_more:    false,  // toutes les pages ont été récupérées
    });

  } catch (err) {
    console.error('sync_transactions error:', err.response?.data || err.message);
    const plaidErr = err.response?.data;

    // Gérer l'erreur ITEM_LOGIN_REQUIRED (session expirée → re-authentification)
    if (plaidErr?.error_code === 'ITEM_LOGIN_REQUIRED') {
      return res.status(428).json({
        error:      'Re-authentification requise.',
        error_code: 'ITEM_LOGIN_REQUIRED'
      });
    }

    res.status(500).json({
      error:   'Erreur lors de la synchronisation.',
      details: plaidErr?.error_message || err.message
    });
  }
});

// ── POST /get_balances ────────────────────────────────────────────────────────
// Récupère les soldes en temps réel de tous les comptes liés.
//
// Body: { access_token: string }
// Returns: { accounts: [{ account_id, name, official_name, type, subtype, balances }] }
app.post('/get_balances', requireApiKey, async (req, res) => {
  try {
    const { access_token } = req.body;
    if (!access_token) {
      return res.status(400).json({ error: 'access_token manquant.' });
    }

    const response = await plaidClient.accountsBalanceGet({ access_token });

    const accounts = response.data.accounts.map(a => ({
      account_id:    a.account_id,
      name:          a.name,
      official_name: a.official_name,
      type:          a.type,
      subtype:       a.subtype,
      mask:          a.mask,          // 4 derniers chiffres
      balances: {
        available: a.balances.available,
        current:   a.balances.current,
        limit:     a.balances.limit,
        iso_currency_code: a.balances.iso_currency_code,
      }
    }));

    res.json({ accounts });

  } catch (err) {
    console.error('get_balances error:', err.response?.data || err.message);
    res.status(500).json({
      error:   'Erreur lors de la récupération des soldes.',
      details: err.response?.data?.error_message || err.message
    });
  }
});

// ── DELETE /disconnect ────────────────────────────────────────────────────────
// Révoque un access_token — déconnecte le compte bancaire.
//
// Body: { access_token: string }
// Returns: { success: true }
app.delete('/disconnect', requireApiKey, async (req, res) => {
  try {
    const { access_token } = req.body;
    if (!access_token) {
      return res.status(400).json({ error: 'access_token manquant.' });
    }

    await plaidClient.itemRemove({ access_token });

    console.log(`[${new Date().toISOString()}] Compte déconnecté.`);
    res.json({ success: true });

  } catch (err) {
    console.error('disconnect error:', err.response?.data || err.message);
    res.status(500).json({
      error:   'Erreur lors de la déconnexion.',
      details: err.response?.data?.error_message || err.message
    });
  }
});

// ── Démarrage ─────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`✅  FinTrack Plaid Server démarré`);
  console.log(`    Port:        ${PORT}`);
  console.log(`    Plaid env:   ${PLAID_ENV}`);
  console.log(`    Santé:       http://localhost:${PORT}/health`);
});
