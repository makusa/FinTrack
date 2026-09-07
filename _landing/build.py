#!/usr/bin/env python3
"""
Génère les deux pages servies à partir d'un gabarit unique.

    page/index.src.html   gabarit, texte français en clair
    page/en.json          traductions anglaises, une clé par élément

    →  public/index.html      français, à la racine
       public/en/index.html   anglais, sous /en/

Le texte anglais est appliqué ici, au build, et non dans le navigateur :
un moteur de recherche a besoin d'une adresse par langue pour indexer les
deux, et de balises hreflang qui les relient. Un basculement en JavaScript
sur une seule URL ne rend indexable que la langue par défaut.

    python3 build.py
"""

import json, os, pathlib, re
import lxml.html

RACINE = pathlib.Path(__file__).parent
SITE = "https://fintrack.bmsk.ca"

LANGUES = {
    "fr": {
        "lang": "fr-CA", "url": f"{SITE}/", "dossier_images": "/img/",
        "og_locale": "fr_CA", "og_alt": "en_CA", "og_image": f"{SITE}/og-fr.jpg",
        "sortie": "public/index.html",
        "og_desc": "Droits de cotisation CELI et CELIAPP, hypothèque à capitalisation "
                   "semestrielle, marges de crédit au taux journalier. Sur votre iPhone.",
        "ld_desc": "Application de finances personnelles pour le Canada : suivi des droits "
                   "de cotisation CELI, CELIAPP et REER, amortissement hypothécaire à "
                   "capitalisation semestrielle, marges de crédit au taux journalier.",
    },
    "en": {
        "lang": "en-CA", "url": f"{SITE}/en/", "dossier_images": "/img-en/",
        "og_locale": "en_CA", "og_alt": "fr_CA", "og_image": f"{SITE}/og-en.jpg",
        "sortie": "public/en/index.html",
        "og_desc": "TFSA and FHSA contribution room, semi-annual mortgage compounding, "
                   "credit lines at the daily rate. On your iPhone.",
        "ld_desc": "Personal finance app for Canada: TFSA, FHSA and RRSP contribution room "
                   "tracking, semi-annual mortgage amortization, credit lines with daily "
                   "interest.",
    },
}


def poser_html(element, html):
    """Remplace le contenu d'un élément par un fragment HTML."""
    frag = lxml.html.fragment_fromstring(html, create_parent="conteneur")
    for enfant in list(element):
        element.remove(enfant)
    element.text = frag.text
    for enfant in frag:
        element.append(enfant)


def donnees_structurees(code, cfg, titre):
    """JSON-LD : dit aux moteurs que la page décrit une application, pas un article."""
    return json.dumps({
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": "Fin:Track",
        "applicationCategory": "FinanceApplication",
        "operatingSystem": "iOS 17+",
        "inLanguage": ["fr-CA", "en-CA", "es", "pt"],
        "url": cfg["url"],
        "description": cfg["ld_desc"],
        "offers": [
            {"@type": "Offer", "name": "Courant", "price": "0",     "priceCurrency": "CAD"},
            {"@type": "Offer", "name": "Pro",     "price": "24.99", "priceCurrency": "CAD"},
            {"@type": "Offer", "name": "Max",     "price": "3.99",  "priceCurrency": "CAD"},
        ],
        "author": {"@type": "Organization", "name": "bmsk", "url": "https://bmsk.ca"},
    }, ensure_ascii=False, indent=2)


def rendre(code, gabarit, en):
    cfg = LANGUES[code]
    doc = lxml.html.fromstring(gabarit)
    doc.set("lang", cfg["lang"])

    if code == "en":
        for el in doc.xpath("//*[@data-t]"):
            if el.get("data-t") in en:
                poser_html(el, en[el.get("data-t")])
        for attribut, cle in (("alt", "data-alt"), ("placeholder", "data-ph"),
                              ("aria-label", "data-aria")):
            for el in doc.xpath(f"//*[@{cle}]"):
                if el.get(cle) in en:
                    el.set(attribut, en[el.get(cle)])
        doc.xpath("//title")[0].text = en["_title"]
        doc.xpath("//meta[@id='metaDesc']")[0].set("content", en["_desc"])

    titre = doc.xpath("//title")[0].text

    # Jeu de captures correspondant à la langue de l'interface montrée
    for img in doc.xpath("//img[@data-shot]"):
        img.set("src", cfg["dossier_images"] + img.get("data-shot") + ".webp")

    # Sélecteur : la langue courante est marquée, l'autre est un lien à suivre
    doc.xpath(f"//*[@id='lien{code.upper()}']")[0].set("aria-current", "page")

    html = lxml.html.tostring(doc, encoding="unicode", doctype="<!DOCTYPE html>")

    tete = f"""<link rel="canonical" href="{cfg['url']}">
<link rel="alternate" hreflang="fr-CA" href="{SITE}/">
<link rel="alternate" hreflang="en-CA" href="{SITE}/en/">
<link rel="alternate" hreflang="x-default" href="{SITE}/">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png">
<link rel="icon" type="image/png" sizes="16x16" href="/favicon-16.png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Fin:Track">
<meta property="og:title" content="{titre}">
<meta property="og:description" content="{cfg['og_desc']}">
<meta property="og:url" content="{cfg['url']}">
<meta property="og:image" content="{cfg['og_image']}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:locale" content="{cfg['og_locale']}">
<meta property="og:locale:alternate" content="{cfg['og_alt']}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{titre}">
<meta name="twitter:description" content="{cfg['og_desc']}">
<meta name="twitter:image" content="{cfg['og_image']}">"""

    html = html.replace(
        "<!DOCTYPE html>",
        "<!DOCTYPE html>\n<!-- Fichier généré par _landing/build.py — ne pas éditer ici.\n"
        "     Source du contenu : page/index.src.html et page/en.json.\n"
        "     Régénérer avec : python3 build.py -->", 1)
    html = html.replace("<!--TETE-->", tete)
    html = html.replace(
        "<!--DONNEES-STRUCTUREES-->",
        '<script type="application/ld+json">\n%s\n</script>'
        % donnees_structurees(code, cfg, titre),
    )

    chemin = RACINE / cfg["sortie"]
    chemin.parent.mkdir(parents=True, exist_ok=True)
    chemin.write_text(html, encoding="utf-8")
    return chemin, len(html)


def main():
    gabarit = (RACINE / "page/index.src.html").read_text(encoding="utf-8")
    en = json.loads((RACINE / "page/en.json").read_text(encoding="utf-8"))

    for code in LANGUES:
        chemin, taille = rendre(code, gabarit, en)
        print(f"  {chemin.relative_to(RACINE)}  {taille // 1024} Ko")

    (RACINE / "public/robots.txt").write_text(
        f"User-agent: *\nAllow: /\nDisallow: /api/\n\nSitemap: {SITE}/sitemap.xml\n",
        encoding="utf-8")

    (RACINE / "public/sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n'
        '        xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'
        + "".join(
            f'  <url>\n    <loc>{c["url"]}</loc>\n'
            f'    <xhtml:link rel="alternate" hreflang="fr-CA" href="{SITE}/"/>\n'
            f'    <xhtml:link rel="alternate" hreflang="en-CA" href="{SITE}/en/"/>\n'
            f'    <xhtml:link rel="alternate" hreflang="x-default" href="{SITE}/"/>\n'
            f'  </url>\n' for c in LANGUES.values())
        + "</urlset>\n", encoding="utf-8")

    print("  public/robots.txt, public/sitemap.xml")


if __name__ == "__main__":
    main()
