/**
 * Fin:Track — landing page.
 *
 * Les fichiers statiques de public/ sont servis par la couche d'assets de
 * Cloudflare sans passer par ce script. Le Worker ne traite donc que les
 * routes /api/*.
 *
 *   POST /api/inscription   inscription à la bêta
 *   GET  /api/inscriptions  export CSV, protégé par un jeton
 *
 * Le jeton d'export est un secret Wrangler, jamais dans le dépôt :
 *   npx wrangler secret put ADMIN_TOKEN
 */

/** Version du texte de consentement affiché sur la page, conservée avec
 *  chaque inscription pour pouvoir prouver plus tard ce qui a été promis. */
const CONSENTEMENT = "beta-testflight-2026-09";

const MAX_CORPS = 1024; // octets ; une inscription légitime en fait ~60

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/inscription") {
      if (request.method !== "POST") return refus(405, "methode");
      return inscrire(request, env);
    }

    if (url.pathname === "/api/inscriptions") {
      if (request.method !== "GET") return refus(405, "methode");
      return exporter(request, env);
    }

    // Tout le reste : laisser la couche d'assets répondre (404 incluse).
    return env.ASSETS.fetch(request);
  },
};

// ── Inscription ────────────────────────────────────────────────────────────

async function inscrire(request, env) {
  const brut = await request.text();
  if (brut.length > MAX_CORPS) return refus(413, "corps");

  let corps;
  try {
    corps = JSON.parse(brut);
  } catch {
    return refus(400, "format");
  }

  // Piège à robots : champ invisible pour un humain. S'il est rempli, on
  // répond comme si tout s'était bien passé, sans rien enregistrer.
  if (typeof corps.entreprise === "string" && corps.entreprise.trim() !== "") {
    return json({ ok: true, deja: false });
  }

  const courriel = normaliserCourriel(corps.courriel);
  if (!courriel) return refus(422, "courriel");

  const langue = corps.langue === "en" ? "en" : "fr";
  const pays = request.headers.get("CF-IPCountry") || null;
  const maintenant = new Date().toISOString();

  try {
    const resultat = await env.DB.prepare(
      `INSERT INTO inscriptions (courriel, langue, pays, consentement, cree_le)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT (courriel) DO NOTHING`
    )
      .bind(courriel, langue, pays, CONSENTEMENT, maintenant)
      .run();

    const nouvelle = (resultat.meta?.changes ?? 0) > 0;
    return json({ ok: true, deja: !nouvelle });
  } catch (erreur) {
    console.error("inscription", erreur);
    return refus(500, "serveur");
  }
}

/** Valide et normalise une adresse. Retourne null si elle est inutilisable. */
function normaliserCourriel(valeur) {
  if (typeof valeur !== "string") return null;
  const courriel = valeur.trim().toLowerCase();
  if (courriel.length < 6 || courriel.length > 254) return null;
  // Volontairement permissif : refuser une adresse valide est pire que
  // d'en accepter une qui rebondira à l'envoi.
  if (!/^[^\s@]+@[^\s@.]+\.[^\s@]{2,}$/.test(courriel)) return null;
  return courriel;
}

// ── Export ─────────────────────────────────────────────────────────────────

async function exporter(request, env) {
  const attendu = env.ADMIN_TOKEN;
  const fourni = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!attendu || !egalitéConstante(fourni, attendu)) return refus(401, "jeton");

  const { results } = await env.DB.prepare(
    `SELECT courriel, langue, pays, consentement, cree_le, desabonne_le
       FROM inscriptions
      WHERE desabonne_le IS NULL
      ORDER BY cree_le`
  ).all();

  const entetes = "courriel,langue,pays,consentement,cree_le";
  const lignes = results.map((r) =>
    [r.courriel, r.langue, r.pays ?? "", r.consentement, r.cree_le]
      .map((c) => `"${String(c).replace(/"/g, '""')}"`)
      .join(",")
  );

  return new Response([entetes, ...lignes].join("\n"), {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": 'attachment; filename="fintrack-beta.csv"',
      "Cache-Control": "no-store",
    },
  });
}

/** Comparaison à temps constant, pour ne pas laisser deviner le jeton. */
function egalitéConstante(a, b) {
  if (a.length !== b.length) return false;
  let ecart = 0;
  for (let i = 0; i < a.length; i++) ecart |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return ecart === 0;
}

// ── Réponses ───────────────────────────────────────────────────────────────

function json(donnees, statut = 200) {
  return new Response(JSON.stringify(donnees), {
    status: statut,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function refus(statut, raison) {
  return json({ ok: false, raison }, statut);
}
