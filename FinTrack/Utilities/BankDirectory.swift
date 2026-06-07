//
//  BankDirectory.swift
//  FinTrack
//
//  Curated list of banks across Canada, USA, UK, Europe, and Africa.
//  Logos are fetched at runtime from logo.clearbit.com/{domain}.
//

import Foundation

// MARK: - Data types

struct BankInfo: Identifiable, Hashable {
    let id: String          // stable: domain or slug
    let name: String        // primary display name
    let aliases: [String]   // abbreviations + alternate names searched but not displayed
    let domain: String?     // used for logo URL; nil = no logo
    let countryCode: String // ISO 3166-1 alpha-2
}

// MARK: - Directory

enum BankDirectory {

    // MARK: Logo URL

    static func logoURL(for domain: String?) -> URL? {
        guard let d = domain, !d.isEmpty else { return nil }
        return URL(string: "https://logo.clearbit.com/\(d)")
    }

    /// Find the domain for a given institution name (exact or best match).
    static func domain(for name: String) -> String? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return exactMatch(name)?.domain
    }

    static func exactMatch(_ name: String) -> BankInfo? {
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        return all.first {
            $0.name.lowercased() == q ||
            $0.aliases.map { $0.lowercased() }.contains(q)
        }
    }

    // MARK: Search

    /// Returns up to `limit` results ranked by relevance.
    static func search(_ query: String, limit: Int = 12) -> [BankInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }

        var exact:    [BankInfo] = []
        var starts:   [BankInfo] = []
        var contains: [BankInfo] = []

        for bank in all {
            let fields = ([bank.name] + bank.aliases).map { $0.lowercased() }
            if fields.contains(q) {
                exact.append(bank)
            } else if fields.contains(where: { $0.hasPrefix(q) }) {
                starts.append(bank)
            } else if fields.contains(where: { $0.contains(q) }) {
                contains.append(bank)
            }
        }

        let ranked = (exact + starts + contains)
        return Array(ranked.prefix(limit))
    }


    // MARK: - Tier filtering

    /// Countries shown in the institution picker for the free tier.
    static let freeTierCountries: Set<String> = ["CA", "US"]

    /// Filtered bank list: free tier = CA+US only, pro tier = all.
    static func search(_ query: String, hasPro: Bool, limit: Int = 12) -> [BankInfo] {
        let filtered = hasPro ? all : all.filter { freeTierCountries.contains($0.countryCode) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }

        var exact:    [BankInfo] = []
        var starts:   [BankInfo] = []
        var contains: [BankInfo] = []

        for bank in filtered {
            let fields = ([bank.name] + bank.aliases).map { $0.lowercased() }
            if fields.contains(q)                               { exact.append(bank) }
            else if fields.contains(where: { $0.hasPrefix(q) }){ starts.append(bank) }
            else if fields.contains(where: { $0.contains(q) }) { contains.append(bank) }
        }
        return Array((exact + starts + contains).prefix(limit))
    }

    /// Countries to display in grouped picker, filtered by tier.
    static func availableCountries(hasPro: Bool) -> [String] {
        let allowed: Set<String> = hasPro ? Set(all.map { $0.countryCode }) : freeTierCountries
        let preferred = hasPro
            ? ["CA", "US", "GB", "FR", "DE", "ES", "PT", "NL", "BE", "CH", "AF", "INT"]
            : ["CA", "US"]
        return preferred.filter { allowed.contains($0) && !banks(for: $0).isEmpty }
    }

    /// Banks for a country, respecting tier.
    static func banks(for countryCode: String, hasPro: Bool = true) -> [BankInfo] {
        guard hasPro || freeTierCountries.contains(countryCode) else { return [] }
        return all.filter { $0.countryCode == countryCode }.sorted { $0.name < $1.name }
    }

    // MARK: Grouped by country

    static var countries: [String] {
        // Preferred display order
        let preferred = ["CA", "US", "GB", "FR", "DE", "ES", "PT", "NL", "BE", "CH", "AF"]
        let inList = Set(all.map { $0.countryCode })
        let rest = inList.subtracting(preferred).sorted()
        return preferred.filter { inList.contains($0) } + rest
    }

    static func banks(for countryCode: String) -> [BankInfo] {
        all.filter { $0.countryCode == countryCode }.sorted { $0.name < $1.name }
    }

    static func flag(for countryCode: String) -> String {
        countryCode.unicodeScalars
            .compactMap { Unicode.Scalar(127397 + $0.value) }
            .map { String($0) }
            .joined()
    }

    static func countryName(for code: String) -> String {
        countryNames[code] ?? code
    }

    private static let countryNames: [String: String] = [
        "CA": "Canada",
        "US": "États-Unis / USA",
        "GB": "Royaume-Uni / UK",
        "FR": "France",
        "DE": "Allemagne",
        "ES": "Espagne",
        "PT": "Portugal",
        "NL": "Pays-Bas",
        "BE": "Belgique",
        "CH": "Suisse",
        "AF": "Afrique",
        "INT": "International / Digital",
    ]

    // MARK: - Bank list

    static let all: [BankInfo] = canada + usa + uk + france + germany + spain
        + portugal + netherlands + belgium + switzerland + africa + international

    // ─── Canada ──────────────────────────────────────────────────────────────
    static let canada: [BankInfo] = [
        BankInfo(id: "rbc.com",             name: "Banque Royale du Canada (RBC)",   aliases: ["rbc", "royal bank", "bnc rbc"],                    domain: "rbc.com",             countryCode: "CA"),
        BankInfo(id: "td.com",              name: "Banque TD",                        aliases: ["td", "td bank", "toronto dominion"],               domain: "td.com",              countryCode: "CA"),
        BankInfo(id: "scotiabank.com",      name: "Banque Scotia",                    aliases: ["scotia", "scotiabank", "nova scotia"],             domain: "scotiabank.com",      countryCode: "CA"),
        BankInfo(id: "bmo.com",             name: "Banque de Montréal (BMO)",         aliases: ["bmo", "bank of montreal"],                        domain: "bmo.com",             countryCode: "CA"),
        BankInfo(id: "cibc.com",            name: "CIBC",                             aliases: ["cibc", "banque imperiale"],                       domain: "cibc.com",            countryCode: "CA"),
        BankInfo(id: "nbc.ca",              name: "Banque Nationale du Canada",       aliases: ["bnc", "nbc", "banque nationale", "national bank"], domain: "nbc.ca",              countryCode: "CA"),
        BankInfo(id: "desjardins.com",      name: "Desjardins",                       aliases: ["desjardins", "caisse populaire", "caisse"],        domain: "desjardins.com",      countryCode: "CA"),
        BankInfo(id: "hsbc.ca",             name: "HSBC Canada",                      aliases: ["hsbc canada"],                                    domain: "hsbc.ca",             countryCode: "CA"),
        BankInfo(id: "tangerine.ca",        name: "Tangerine",                        aliases: ["tangerine", "ing direct canada"],                  domain: "tangerine.ca",        countryCode: "CA"),
        BankInfo(id: "eqbank.ca",           name: "EQ Bank",                          aliases: ["eq bank", "equitable bank"],                      domain: "eqbank.ca",           countryCode: "CA"),
        BankInfo(id: "laurentianbank.ca",   name: "Banque Laurentienne",              aliases: ["laurentienne", "blc", "laurentian bank"],          domain: "laurentianbank.ca",   countryCode: "CA"),
        BankInfo(id: "atb.com",             name: "ATB Financial",                    aliases: ["atb"],                                            domain: "atb.com",             countryCode: "CA"),
        BankInfo(id: "simplii.com",         name: "Simplii Financial",                aliases: ["simplii"],                                        domain: "simplii.com",         countryCode: "CA"),
        BankInfo(id: "manulifebank.ca",     name: "Banque Manuvie",                   aliases: ["manuvie", "manulife bank"],                        domain: "manulifebank.ca",     countryCode: "CA"),
        BankInfo(id: "wealthsimple.com",    name: "Wealthsimple",                     aliases: ["wealthsimple"],                                   domain: "wealthsimple.com",    countryCode: "CA"),
        BankInfo(id: "motusbank.ca",        name: "motusbank",                        aliases: ["motus"],                                          domain: "motusbank.ca",        countryCode: "CA"),
        BankInfo(id: "pcfinancial.ca",      name: "PC Financial",                     aliases: ["pc financial", "president's choice"],              domain: "pcfinancial.ca",      countryCode: "CA"),
        BankInfo(id: "koho.ca",             name: "KOHO",                             aliases: ["koho"],                                           domain: "koho.ca",             countryCode: "CA"),
        BankInfo(id: "nesto.ca",            name: "nesto",                            aliases: ["nesto"],                                          domain: "nesto.ca",            countryCode: "CA"),
        BankInfo(id: "meridiancu.ca",       name: "Meridian Credit Union",            aliases: ["meridian"],                                       domain: "meridiancu.ca",       countryCode: "CA"),
        BankInfo(id: "cambridgesavings.com",name: "Cambridge Savings Bank",           aliases: ["cambridge"],                                      domain: "cambridgesavings.com",countryCode: "CA"),
        BankInfo(id: "nbdb.ca",             name: "Banque Nationale Courtage direct", aliases: ["nbdb", "bncd"],                                   domain: "nbdb.ca",             countryCode: "CA"),
    ]

    // ─── USA ─────────────────────────────────────────────────────────────────
    static let usa: [BankInfo] = [
        BankInfo(id: "chase.com",              name: "JPMorgan Chase",             aliases: ["chase", "jpmorgan"],                         domain: "chase.com",              countryCode: "US"),
        BankInfo(id: "bankofamerica.com",       name: "Bank of America",           aliases: ["boa", "bofa", "bank of america"],             domain: "bankofamerica.com",       countryCode: "US"),
        BankInfo(id: "wellsfargo.com",          name: "Wells Fargo",               aliases: ["wells fargo", "wf"],                         domain: "wellsfargo.com",          countryCode: "US"),
        BankInfo(id: "citi.com",                name: "Citibank",                  aliases: ["citi", "citigroup"],                         domain: "citi.com",                countryCode: "US"),
        BankInfo(id: "goldmansachs.com",        name: "Goldman Sachs",             aliases: ["goldman"],                                   domain: "goldmansachs.com",        countryCode: "US"),
        BankInfo(id: "morganstanley.com",       name: "Morgan Stanley",            aliases: ["morgan stanley"],                            domain: "morganstanley.com",       countryCode: "US"),
        BankInfo(id: "usbank.com",              name: "US Bank",                   aliases: ["usbank", "us bancorp"],                      domain: "usbank.com",              countryCode: "US"),
        BankInfo(id: "truist.com",              name: "Truist Bank",               aliases: ["truist"],                                    domain: "truist.com",              countryCode: "US"),
        BankInfo(id: "pnc.com",                 name: "PNC Bank",                  aliases: ["pnc"],                                       domain: "pnc.com",                 countryCode: "US"),
        BankInfo(id: "capitalone.com",          name: "Capital One",               aliases: ["capital one"],                               domain: "capitalone.com",          countryCode: "US"),
        BankInfo(id: "usaa.com",                name: "USAA",                      aliases: ["usaa"],                                      domain: "usaa.com",                countryCode: "US"),
        BankInfo(id: "schwab.com",              name: "Charles Schwab",            aliases: ["schwab"],                                    domain: "schwab.com",              countryCode: "US"),
        BankInfo(id: "americanexpress.com",     name: "American Express",          aliases: ["amex", "american express"],                  domain: "americanexpress.com",     countryCode: "US"),
        BankInfo(id: "discover.com",            name: "Discover Bank",             aliases: ["discover"],                                  domain: "discover.com",            countryCode: "US"),
        BankInfo(id: "ally.com",                name: "Ally Bank",                 aliases: ["ally"],                                      domain: "ally.com",                countryCode: "US"),
        BankInfo(id: "regions.com",             name: "Regions Bank",              aliases: ["regions"],                                   domain: "regions.com",             countryCode: "US"),
        BankInfo(id: "tdbank.com",              name: "TD Bank (US)",              aliases: ["td bank us", "td usa"],                      domain: "tdbank.com",              countryCode: "US"),
        BankInfo(id: "navyfederal.org",         name: "Navy Federal Credit Union", aliases: ["navy federal"],                              domain: "navyfederal.org",         countryCode: "US"),
        BankInfo(id: "fidelity.com",            name: "Fidelity Investments",      aliases: ["fidelity"],                                  domain: "fidelity.com",            countryCode: "US"),
        BankInfo(id: "sofi.com",                name: "SoFi Bank",                 aliases: ["sofi"],                                      domain: "sofi.com",                countryCode: "US"),
        BankInfo(id: "synchrony.com",           name: "Synchrony Bank",            aliases: ["synchrony"],                                 domain: "synchrony.com",           countryCode: "US"),
    ]

    // ─── UK ──────────────────────────────────────────────────────────────────
    static let uk: [BankInfo] = [
        BankInfo(id: "barclays.co.uk",      name: "Barclays",              aliases: ["barclays"],                           domain: "barclays.co.uk",     countryCode: "GB"),
        BankInfo(id: "hsbc.co.uk",          name: "HSBC UK",               aliases: ["hsbc", "hsbc uk"],                    domain: "hsbc.co.uk",          countryCode: "GB"),
        BankInfo(id: "lloydsbank.com",      name: "Lloyds Bank",           aliases: ["lloyds"],                             domain: "lloydsbank.com",      countryCode: "GB"),
        BankInfo(id: "natwest.com",         name: "NatWest",               aliases: ["natwest", "national westminster"],    domain: "natwest.com",         countryCode: "GB"),
        BankInfo(id: "santander.co.uk",     name: "Santander UK",          aliases: ["santander uk"],                       domain: "santander.co.uk",     countryCode: "GB"),
        BankInfo(id: "nationwide.co.uk",    name: "Nationwide",            aliases: ["nationwide"],                         domain: "nationwide.co.uk",    countryCode: "GB"),
        BankInfo(id: "halifax.co.uk",       name: "Halifax",               aliases: ["halifax"],                            domain: "halifax.co.uk",       countryCode: "GB"),
        BankInfo(id: "starlingbank.com",    name: "Starling Bank",         aliases: ["starling"],                           domain: "starlingbank.com",    countryCode: "GB"),
        BankInfo(id: "monzo.com",           name: "Monzo",                 aliases: ["monzo"],                              domain: "monzo.com",           countryCode: "GB"),
        BankInfo(id: "rbs.co.uk",           name: "Royal Bank of Scotland",aliases: ["rbs"],                                domain: "rbs.co.uk",           countryCode: "GB"),
        BankInfo(id: "metrobank.plc.uk",    name: "Metro Bank",            aliases: ["metro bank"],                         domain: "metrobank.plc.uk",    countryCode: "GB"),
        BankInfo(id: "virginmoney.com",     name: "Virgin Money",          aliases: ["virgin money"],                       domain: "virginmoney.com",     countryCode: "GB"),
        BankInfo(id: "tsb.co.uk",           name: "TSB Bank",              aliases: ["tsb"],                                domain: "tsb.co.uk",           countryCode: "GB"),
        BankInfo(id: "co-operativebank.co.uk",name: "Co-operative Bank",   aliases: ["co-op bank", "cooperative"],          domain: "co-operativebank.co.uk", countryCode: "GB"),
    ]

    // ─── France ──────────────────────────────────────────────────────────────
    static let france: [BankInfo] = [
        BankInfo(id: "bnpparibas.com",         name: "BNP Paribas",            aliases: ["bnp", "bnp paribas"],                        domain: "bnpparibas.com",        countryCode: "FR"),
        BankInfo(id: "societegenerale.com",     name: "Société Générale",       aliases: ["sg", "societe generale"],                    domain: "societegenerale.com",   countryCode: "FR"),
        BankInfo(id: "credit-agricole.com",     name: "Crédit Agricole",        aliases: ["ca", "credit agricole"],                     domain: "credit-agricole.com",   countryCode: "FR"),
        BankInfo(id: "creditmutuel.fr",         name: "Crédit Mutuel",          aliases: ["credit mutuel", "cm"],                       domain: "creditmutuel.fr",       countryCode: "FR"),
        BankInfo(id: "labanquepostale.fr",       name: "La Banque Postale",      aliases: ["banque postale", "la poste"],                 domain: "labanquepostale.fr",    countryCode: "FR"),
        BankInfo(id: "cic.fr",                  name: "CIC",                    aliases: ["cic"],                                       domain: "cic.fr",                countryCode: "FR"),
        BankInfo(id: "caisse-epargne.fr",       name: "Caisse d'Épargne",       aliases: ["caisse epargne", "ce"],                      domain: "caisse-epargne.fr",     countryCode: "FR"),
        BankInfo(id: "banquepopulaire.fr",      name: "Banque Populaire",       aliases: ["bp", "banque pop"],                          domain: "banquepopulaire.fr",    countryCode: "FR"),
        BankInfo(id: "lcl.fr",                  name: "LCL",                    aliases: ["lcl", "lyonnais"],                           domain: "lcl.fr",                countryCode: "FR"),
        BankInfo(id: "fortuneo.fr",             name: "Fortuneo",               aliases: ["fortuneo"],                                  domain: "fortuneo.fr",           countryCode: "FR"),
        BankInfo(id: "boursorama.com",          name: "Boursorama",             aliases: ["boursorama", "boursobank"],                  domain: "boursorama.com",        countryCode: "FR"),
        BankInfo(id: "hsbc.fr",                 name: "HSBC France",            aliases: ["hsbc france"],                               domain: "hsbc.fr",               countryCode: "FR"),
    ]

    // ─── Germany ─────────────────────────────────────────────────────────────
    static let germany: [BankInfo] = [
        BankInfo(id: "db.com",              name: "Deutsche Bank",      aliases: ["db", "deutsche bank"],        domain: "db.com",              countryCode: "DE"),
        BankInfo(id: "commerzbank.com",     name: "Commerzbank",        aliases: ["commerzbank"],                domain: "commerzbank.com",     countryCode: "DE"),
        BankInfo(id: "hypovereinsbank.de",  name: "HypoVereinsbank",    aliases: ["hvb", "hypovereins"],         domain: "hypovereinsbank.de",  countryCode: "DE"),
        BankInfo(id: "sparkasse.de",        name: "Sparkasse",          aliases: ["sparkasse"],                  domain: "sparkasse.de",        countryCode: "DE"),
        BankInfo(id: "dkb.de",              name: "DKB Bank",           aliases: ["dkb"],                        domain: "dkb.de",              countryCode: "DE"),
        BankInfo(id: "ing.de",              name: "ING Deutschland",    aliases: ["ing de"],                     domain: "ing.de",              countryCode: "DE"),
        BankInfo(id: "n26.com",             name: "N26",                aliases: ["n26", "n26 bank"],             domain: "n26.com",             countryCode: "DE"),
        BankInfo(id: "comdirect.de",        name: "Comdirect",          aliases: ["comdirect"],                  domain: "comdirect.de",        countryCode: "DE"),
    ]

    // ─── Spain ───────────────────────────────────────────────────────────────
    static let spain: [BankInfo] = [
        BankInfo(id: "santander.com",    name: "Banco Santander",   aliases: ["santander"],                   domain: "santander.com",   countryCode: "ES"),
        BankInfo(id: "bbva.com",         name: "BBVA",              aliases: ["bbva"],                        domain: "bbva.com",        countryCode: "ES"),
        BankInfo(id: "caixabank.com",    name: "CaixaBank",         aliases: ["caixa", "la caixa"],           domain: "caixabank.com",   countryCode: "ES"),
        BankInfo(id: "bankia.es",        name: "Bankia",            aliases: ["bankia"],                      domain: "bankia.es",       countryCode: "ES"),
        BankInfo(id: "sabadell.com",     name: "Banco Sabadell",    aliases: ["sabadell"],                    domain: "sabadell.com",    countryCode: "ES"),
        BankInfo(id: "bankinter.com",    name: "Bankinter",         aliases: ["bankinter"],                   domain: "bankinter.com",   countryCode: "ES"),
    ]

    // ─── Portugal ────────────────────────────────────────────────────────────
    static let portugal: [BankInfo] = [
        BankInfo(id: "cgd.pt",          name: "Caixa Geral de Depósitos", aliases: ["cgd", "caixa geral"],  domain: "cgd.pt",      countryCode: "PT"),
        BankInfo(id: "millenniumbcp.pt",name: "Millennium BCP",            aliases: ["bcp", "millennium"],  domain: "millenniumbcp.pt", countryCode: "PT"),
        BankInfo(id: "bes.pt",          name: "Banco Espírito Santo",      aliases: ["bes"],                domain: nil,           countryCode: "PT"),
        BankInfo(id: "novobanco.pt",    name: "Novo Banco",                aliases: ["novo banco"],         domain: "novobanco.pt",countryCode: "PT"),
        BankInfo(id: "santandertotta.pt",name: "Santander Portugal",       aliases: ["santander pt"],       domain: "santander.pt",countryCode: "PT"),
        BankInfo(id: "activobank.com",  name: "ActivoBank",                aliases: ["activo"],             domain: "activobank.com", countryCode: "PT"),
    ]

    // ─── Netherlands ─────────────────────────────────────────────────────────
    static let netherlands: [BankInfo] = [
        BankInfo(id: "ing.com",       name: "ING",         aliases: ["ing"],         domain: "ing.com",       countryCode: "NL"),
        BankInfo(id: "rabobank.com",  name: "Rabobank",    aliases: ["rabo"],        domain: "rabobank.com",  countryCode: "NL"),
        BankInfo(id: "abnamro.com",   name: "ABN AMRO",    aliases: ["abn amro"],    domain: "abnamro.com",   countryCode: "NL"),
        BankInfo(id: "asn.nl",        name: "ASN Bank",    aliases: ["asn"],         domain: "asn.nl",        countryCode: "NL"),
        BankInfo(id: "bunq.com",      name: "bunq",         aliases: ["bunq"],        domain: "bunq.com",      countryCode: "NL"),
    ]

    // ─── Belgium ─────────────────────────────────────────────────────────────
    static let belgium: [BankInfo] = [
        BankInfo(id: "kbc.com",      name: "KBC",        aliases: ["kbc"],       domain: "kbc.com",     countryCode: "BE"),
        BankInfo(id: "belfius.be",   name: "Belfius",    aliases: ["belfius"],   domain: "belfius.be",  countryCode: "BE"),
        BankInfo(id: "bnpparibasfortis.be", name: "BNP Paribas Fortis", aliases: ["fortis"], domain: "bnpparibasfortis.be", countryCode: "BE"),
        BankInfo(id: "ing.be",       name: "ING Belgium",aliases: ["ing be"],    domain: "ing.be",      countryCode: "BE"),
    ]

    // ─── Switzerland ─────────────────────────────────────────────────────────
    static let switzerland: [BankInfo] = [
        BankInfo(id: "ubs.com",           name: "UBS",             aliases: ["ubs"],                domain: "ubs.com",         countryCode: "CH"),
        BankInfo(id: "credit-suisse.com", name: "Credit Suisse",   aliases: ["cs", "credit suisse"],domain: "credit-suisse.com",countryCode: "CH"),
        BankInfo(id: "postfinance.ch",    name: "PostFinance",      aliases: ["post finance"],       domain: "postfinance.ch",  countryCode: "CH"),
        BankInfo(id: "raiffeisen.ch",     name: "Raiffeisen",       aliases: ["raiffeisen"],         domain: "raiffeisen.ch",   countryCode: "CH"),
        BankInfo(id: "zürcher-kb.ch",     name: "Zürcher Kantonalbank", aliases: ["zkb"],           domain: "zkb.ch",          countryCode: "CH"),
    ]

    // ─── Africa (corridor Cameroun + grandes banques continentales) ───────────
    static let africa: [BankInfo] = [
        BankInfo(id: "afrilandfirstbank.com",name: "Afriland First Bank",      aliases: ["afriland"],                        domain: "afrilandfirstbank.com",  countryCode: "AF"),
        BankInfo(id: "societegenerale.cm",   name: "Société Générale Cameroun",aliases: ["sg cameroun", "sgc"],             domain: "societegenerale.cm",     countryCode: "AF"),
        BankInfo(id: "ecobank.com",          name: "Ecobank",                  aliases: ["ecobank"],                        domain: "ecobank.com",            countryCode: "AF"),
        BankInfo(id: "ubagroup.com",         name: "United Bank for Africa (UBA)", aliases: ["uba"],                        domain: "ubagroup.com",           countryCode: "AF"),
        BankInfo(id: "standardchartered.com",name: "Standard Chartered",       aliases: ["standard chartered", "stanchart"],domain: "standardchartered.com",  countryCode: "AF"),
        BankInfo(id: "bicec.com",            name: "BICEC",                    aliases: ["bicec"],                          domain: "bicec.com",              countryCode: "AF"),
        BankInfo(id: "cbca.cm",              name: "Crédit du Cameroun (CBC)",  aliases: ["cbc", "credit du cameroun"],     domain: "cbca.cm",                countryCode: "AF"),
        BankInfo(id: "access.bank",          name: "Access Bank",              aliases: ["access bank"],                    domain: "accessbankplc.com",      countryCode: "AF"),
        BankInfo(id: "zenithbank.com",       name: "Zenith Bank",              aliases: ["zenith"],                         domain: "zenithbank.com",         countryCode: "AF"),
        BankInfo(id: "attijariwafabank.com", name: "Attijariwafa Bank",        aliases: ["attijariwafa", "wafa"],            domain: "attijariwafabank.com",   countryCode: "AF"),
        BankInfo(id: "cib.com.eg",           name: "Commercial International Bank (CIB)", aliases: ["cib egypt"],          domain: "cib.com.eg",             countryCode: "AF"),
    ]

    // ─── International / Digital ─────────────────────────────────────────────
    static let international: [BankInfo] = [
        BankInfo(id: "wise.com",       name: "Wise (TransferWise)",aliases: ["wise", "transferwise"],   domain: "wise.com",       countryCode: "INT"),
        BankInfo(id: "revolut.com",    name: "Revolut",            aliases: ["revolut"],                domain: "revolut.com",    countryCode: "INT"),
        BankInfo(id: "paypal.com",     name: "PayPal",             aliases: ["paypal"],                 domain: "paypal.com",     countryCode: "INT"),
        BankInfo(id: "hsbc.com",       name: "HSBC (International)",aliases: ["hsbc", "hsbc intl"],    domain: "hsbc.com",       countryCode: "INT"),
        BankInfo(id: "citigroup.com",  name: "Citigroup",          aliases: ["citi global"],            domain: "citigroup.com",  countryCode: "INT"),
        BankInfo(id: "dbs.com",        name: "DBS Bank",           aliases: ["dbs"],                    domain: "dbs.com",        countryCode: "INT"),
        BankInfo(id: "ocbc.com",       name: "OCBC Bank",          aliases: ["ocbc"],                   domain: "ocbc.com",       countryCode: "INT"),
        BankInfo(id: "crypto.com",     name: "Crypto.com",         aliases: ["crypto"],                 domain: "crypto.com",     countryCode: "INT"),
        BankInfo(id: "stripe.com",     name: "Stripe",             aliases: ["stripe"],                 domain: "stripe.com",     countryCode: "INT"),
    ]
}
