-- Liste d'attente de la bêta TestFlight.
--
-- Choix de rétention : on conserve le minimum permettant de prouver le
-- consentement au sens de la LCAP — quand, dans quelle langue, et quel texte
-- de consentement était affiché à ce moment-là. L'adresse IP n'est pas
-- conservée : elle constituerait une preuve plus forte, mais c'est un
-- renseignement personnel supplémentaire, et le pays fourni par Cloudflare
-- suffit à situer la demande.

CREATE TABLE IF NOT EXISTS inscriptions (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  courriel       TEXT    NOT NULL UNIQUE,
  langue         TEXT    NOT NULL,              -- fr | en
  pays           TEXT,                          -- code pays fourni par Cloudflare
  consentement   TEXT    NOT NULL,              -- version du texte affiché
  cree_le        TEXT    NOT NULL,              -- ISO 8601 UTC
  desabonne_le   TEXT                           -- rempli si retrait demandé
);

CREATE INDEX IF NOT EXISTS idx_inscriptions_cree_le ON inscriptions (cree_le);
