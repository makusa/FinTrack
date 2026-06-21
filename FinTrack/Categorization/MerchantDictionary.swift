//
//  MerchantDictionary.swift
//  FinTrack
//
//  Built-in keyword → category rules for cold-start categorization of imported
//  transactions, BEFORE any personal history exists. Two families share one scan:
//   • banking operations, recognized on NAME+MEMO (Service Charge → Frais bancaires,
//     Bill Payment/TAXES → Impôts, Overdraft → Frais bancaires…), which is what
//     chequing-account statements (e.g. BNC) actually contain;
//   • merchants, recognized on the normalized payee (Canadian + US chains).
//
//  Rules map to a CanonicalCategory whose `defaultCategoryName` matches the FR system
//  categories seeded in SeedData; the categorizer (A4) resolves it against the user's
//  actual categories and only proposes one that fits the transaction's income/expense
//  side. Pure transfers (Interac, card payments) match nothing on purpose → left blank.
//  Matching is best-effort and always surfaced as a suggestion in the import preview.
//

import Foundation

enum CanonicalCategory: String, CaseIterable {
    // expense
    case alimentation, restaurant, transport, servicesPublics, sante, loisirs
    case vetements, voyage, logement, education, impots, fraisBancaires
    // income
    case salaire, interets, dividendes, remboursement

    var isIncome: Bool {
        switch self {
        case .salaire, .interets, .dividendes, .remboursement: return true
        default: return false
        }
    }

    /// Must match the FR system category names seeded in SeedData for resolution.
    var defaultCategoryName: String {
        switch self {
        case .alimentation:    return "Alimentation"
        case .restaurant:      return "Restaurant"
        case .transport:       return "Transport"
        case .servicesPublics: return "Services publics"
        case .sante:           return "Santé"
        case .loisirs:         return "Loisirs"
        case .vetements:       return "Vêtements"
        case .voyage:          return "Voyage"
        case .logement:        return "Logement"
        case .education:       return "Éducation"
        case .impots:          return "Impôts"
        case .fraisBancaires:  return "Frais bancaires"
        case .salaire:         return "Salaire"
        case .interets:        return "Intérêts"
        case .dividendes:      return "Dividendes"
        case .remboursement:   return "Remboursement"
        }
    }
}

enum MerchantDictionary {

    // Keywords are uppercase, accent-free fragments matched at a token boundary
    // (so "MCDONALD" also catches "MCDONALDS"). Kept >=4 chars unless very
    // distinctive, to limit false positives. CA = Canada, US = United States.
    static let raw: [(CanonicalCategory, [String])] = [

        // ── Banking operations (NAME + MEMO) ───────────────────────────────
        (.fraisBancaires, [
            "SERVICE CHARGE", "SERVICE FEE", "MONTHLY FEE", "MONTHLY PLAN FEE",
            "FRAIS MENSUELS", "FRAIS DE SERVICE", "FRAIS BANCAIRES", "ACCOUNT FEE",
            "MAINTENANCE FEE", "ANNUAL FEE", "FRAIS ANNUELS", "OVERDRAFT", "OVERDRAWN",
            "DECOUVERT", "HANDLING CHG", "HANDLING CHARGE", "NSF", "INSUFFICIENT FUND",
            "ATM FEE", "GUICHET", "WIRE FEE", "FOREIGN TRANSACTION", "CONVERSION FEE",
            "OVERLIMIT", "FRAIS DE RETARD", "LATE FEE", "CHEQUE ORDER", "STOP PAYMENT",
        ]),
        (.impots, [
            "REVENU QUEBEC", "REVENU-QUEBEC", "CANADA REVENUE", "AGENCE DU REVENU",
            "RECEIVER GENERAL", "RECEVEUR GENERAL", "VILLE DE MONTREAL", "TAXES",
            "TAXE", "MUNICIPAL TAX", "TAXES SCOLAIRES", "TAXES MUNICIPALES",
            "PROPERTY TAX", "IRS", "FRANCHISE TAX", "SALES TAX", "IMPOT",
        ]),
        // ── Income ─────────────────────────────────────────────────────────
        (.salaire, [
            "PAYROLL", "PAIE", "DEPOT SALAIRE", "SALAIRE", "PAY DEP", "PAY/PAIE",
            "DIRECT DEP", "DEPOT DIRECT", "ADP", "CIRIDIAN", "CERIDIAN", "DAYFORCE",
            "GUSTO", "WORKDAY", "PAYCHEX", "REMUNERATION", "WAGES",
        ]),
        (.interets,   ["INTERET", "INTERETS", "INTEREST PAID", "CREDIT INTEREST"]),
        (.dividendes, ["DIVIDENDE", "DIVIDEND"]),
        (.remboursement, ["REMBOURSEMENT", "REFUND", "REMISE", "CASHBACK", "RISTOURNE"]),

        // ── Alimentation (grocery) ─────────────────────────────────────────
        (.alimentation, [
            // CA
            "METRO", "IGA", "PROVIGO", "MAXI", "SUPER C", "SUPERC", "LOBLAW",
            "SOBEYS", "SAFEWAY", "FRESHCO", "NO FRILLS", "NOFRILLS", "SUPERSTORE",
            "REAL CANADIAN", "COSTCO", "WALMART", "WAL MART", "ADONIS", "FARM BOY",
            "FARMBOY", "LONGO", "SAVE ON FOODS", "THRIFTY FOODS", "BULK BARN", "AVRIL",
            "RACHELLE BERY", "INTERMARCHE", "BONICHOIX", "MARCHE", "EPICERIE",
            "SUPERMARCHE", "FRUITERIE", "BOUCHERIE", "H MART", "GIANT TIGER",
            // US
            "WHOLE FOODS", "WHOLEFOODS", "TRADER JOE", "KROGER", "ALBERTSON",
            "PUBLIX", "WEGMANS", "ALDI", "MEIJER", "FOOD LION", "STOP SHOP",
            "RALPHS", "VONS", "SAFEWAY", "SPROUTS", "GIANT EAGLE",
        ]),

        // ── Restaurant / café / fast-food / delivery ───────────────────────
        (.restaurant, [
            // delivery (specific, matched first via ordering)
            "UBER EATS", "UBEREATS", "DOORDASH", "SKIP THE DISHES", "SKIPTHEDISHES",
            "SKIPDISHES", "GRUBHUB", "FOODORA", "RITUEL",
            // CA / QC
            "TIM HORTONS", "TIMS", "MCDONALD", "ST HUBERT", "ST-HUBERT", "SUBWAY",
            "STARBUCKS", "SECOND CUP", "VAN HOUTTE", "NORMANDIN", "VALENTINE",
            "BELLE PROVINCE", "BENNY", "SCORES", "PFK", "KFC", "BURGER KING",
            "HARVEY", "WENDY", "DAIRY QUEEN", "PIZZA HUT", "PIZZA", "DOMINO",
            "BOSTON PIZZA", "EAST SIDE MARIO", "SWISS CHALET", "MILESTONES",
            "CACTUS CLUB", "EARLS", "THE KEG", "RESTAURANT", "RESTO", "BISTRO",
            "BRASSERIE", "TRATTORIA", "SUSHI", "NANDO", "PRESSE CAFE", "CAFE", "COFFEE",
            // US
            "CHIPOTLE", "FIVE GUYS", "FIVEGUYS", "POPEYES", "TACO BELL", "PANERA",
            "DUNKIN", "DENNYS", "IHOP", "OLIVE GARDEN", "SHAKE SHACK", "CHICK FIL A",
            "CHICKFILA", "WHATABURGER", "IN N OUT", "JACK IN THE BOX", "SONIC",
            "ARBY", "CHEESECAKE", "BUFFALO WILD", "PANDA EXPRESS", "WINGSTOP",
        ]),

        // ── Transport (gas / transit / rideshare / parking / auto) ─────────
        (.transport, [
            // gas CA
            "ESSO", "PETRO CANADA", "PETRO-CANADA", "ULTRAMAR", "COUCHE TARD",
            "COUCHE-TARD", "CIRCLE K", "CIRCLEK", "HARNOIS", "CREVIER", "OLCO",
            "PIONEER", "MACEWEN", "HUSKY", "SHELL", "ESSENCE", "STATION SERVICE",
            // gas US
            "EXXON", "MOBIL", "CHEVRON", "TEXACO", "MARATHON", "SPEEDWAY", "SUNOCO",
            "VALERO", "PHILLIPS 66", "CONOCO", "CITGO", "SHEETZ", "WAWA", "QUIKTRIP",
            "RACETRAC", "ARCO",
            // transit CA
            "STM", "EXO", "OPUS", "STL", "RTC", "STO", "SOCIETE DE TRANSPORT",
            "VIA RAIL", "VIARAIL", "GO TRANSIT", "TTC", "OC TRANSPO", "TRANSLINK",
            "PRESTO", "COMPASS", "BIXI", "COMMUNAUTO",
            // transit / rideshare US + intl
            "AMTRAK", "GREYHOUND", "MEGABUS", "UBER", "LYFT", "TURO",
            // parking / auto
            "STATIONNEMENT", "PARKING", "PARKMOBILE", "INDIGO", "IMPARK", "PARKLINK",
            "MR LUBE", "JIFFY LUBE", "MIDAS", "NAPA", "CANADIAN TIRE", "AUTOBUS",
        ]),

        // ── Services publics (utilities + telecom) ─────────────────────────
        (.servicesPublics, [
            // utilities CA
            "HYDRO QUEBEC", "HYDRO-QUEBEC", "HYDRO ONE", "HYDROONE", "HYDRO OTTAWA",
            "ENERGIR", "EPCOR", "ENMAX", "BC HYDRO", "TORONTO HYDRO", "FORTIS",
            "ENBRIDGE", "SASKPOWER", "MANITOBA HYDRO", "NB POWER",
            // telecom CA
            "BELL", "VIDEOTRON", "TELUS", "ROGERS", "FIZZ", "KOODO", "FIDO",
            "VIRGIN PLUS", "PUBLIC MOBILE", "CHATR", "FREEDOM MOBILE", "EBOX",
            "OXIO", "TEKSAVVY", "DISTRIBUTEL", "LUCKY MOBILE", "COGECO", "SHAW",
            "SASKTEL", "EASTLINK",
            // utilities + telecom US
            "VERIZON", "T MOBILE", "TMOBILE", "COMCAST", "XFINITY", "SPECTRUM",
            "CENTURYLINK", "DUKE ENERGY", "CON EDISON", "NATIONAL GRID", "DOMINION",
            "GEORGIA POWER", "PG E", "DTE ENERGY", "AMEREN",
        ]),

        // ── Santé (pharmacy + health) ──────────────────────────────────────
        (.sante, [
            "JEAN COUTU", "JEAN-COUTU", "PHARMAPRIX", "UNIPRIX", "FAMILIPRIX",
            "BRUNET", "PROXIM", "SHOPPERS DRUG", "SHOPPERS", "REXALL", "LONDON DRUGS",
            "PHARMACIE", "PHARMACY", "CLINIQUE", "DENTISTE", "DENTAL", "OPTIQUE",
            "OPTOMETRISTE", "PHYSIO", "HOPITAL", "HOSPITAL", "MEDICAL", "BIRON",
            "CVS", "WALGREENS", "RITE AID", "RITEAID", "GOODRX", "LABCORP",
            "QUEST DIAGNOSTIC",
        ]),

        // ── Loisirs (streaming / cinema / hobbies / alcohol / gym) ──────────
        (.loisirs, [
            // streaming / digital
            "NETFLIX", "SPOTIFY", "DISNEY", "CRAVE", "AMAZON PRIME", "PRIME VIDEO",
            "APPLE.COM", "APPLE COM", "ITUNES", "YOUTUBE PREMIUM", "HBO", "PARAMOUNT",
            "PEACOCK", "HULU", "AUDIBLE", "TWITCH", "PATREON", "STEAM", "STEAMGAMES",
            "PLAYSTATION", "XBOX", "NINTENDO", "EPIC GAMES",
            // cinema / events
            "CINEPLEX", "CINEMA", "GUZZO", "IMAX", "TICKETMASTER", "EVENTBRITE",
            "AMC ", "REGAL", "FANDANGO", "LANDMARK",
            // books / hobbies
            "RENAUD BRAY", "RENAUD-BRAY", "ARCHAMBAULT", "INDIGO", "CHAPTERS",
            "BARNES", "GAMESTOP", "MICHAELS",
            // alcohol
            "SAQ", "LCBO", "BEER STORE", "BEERSTORE", "TOTAL WINE", "BEVMO",
            // gym / fitness
            "ECONOFITNESS", "ENERGIE CARDIO", "GOODLIFE", "GOOD LIFE", "NAUTILUS",
            "PLANET FITNESS", "PLANETFITNESS", "LA FITNESS", "ANYTIME FITNESS",
            "EQUINOX", "ORANGETHEORY", "PELOTON", "CROSSFIT", "YMCA",
        ]),

        // ── Vêtements (clothing / shoes / apparel) ─────────────────────────
        (.vetements, [
            // CA
            "SIMONS", "WINNERS", "MARSHALLS", "HUDSON BAY", "HUDSONS BAY", "LA BAIE",
            "SPORTS EXPERTS", "SPORT CHEK", "SPORTCHEK", "DECATHLON", "MARKS WORK",
            "ALDO", "ROOTS", "ARITZIA", "LULULEMON", "GARAGE", "DYNAMITE", "REITMANS",
            "SAIL", "SIMONS",
            // US / intl
            "ZARA", "UNIQLO", "OLD NAVY", "BANANA REPUBLIC", "NIKE", "ADIDAS",
            "FOOT LOCKER", "FOOTLOCKER", "NORDSTROM", "MACYS", "ROSS DRESS", "TJ MAXX",
            "TJMAXX", "BURLINGTON", "FOREVER 21", "AMERICAN EAGLE", "HOLLISTER",
            "ABERCROMBIE", "URBAN OUTFITTER", "VICTORIA SECRET", "DSW", "SKECHERS",
            "UNDER ARMOUR", "UNDERARMOUR", "GUESS",
        ]),

        // ── Voyage (airlines / hotels / booking) ───────────────────────────
        (.voyage, [
            // airlines CA
            "AIR CANADA", "AIRCANADA", "WESTJET", "WEST JET", "AIR TRANSAT",
            "TRANSAT", "PORTER AIR", "FLAIR", "LYNX AIR", "SUNWING",
            // airlines US / intl
            "DELTA AIR", "UNITED AIR", "AMERICAN AIRLINE", "SOUTHWEST", "JETBLUE",
            "ALASKA AIR", "SPIRIT AIR", "AIR FRANCE", "LUFTHANSA", "BRITISH AIRWAY",
            "EMIRATES", "AIR CANADA",
            // hotels
            "MARRIOTT", "HILTON", "HYATT", "HOLIDAY INN", "BEST WESTERN", "FAIRMONT",
            "SHERATON", "WESTIN", "RADISSON", "MOTEL", "HOTEL", "AUBERGE", "AIRBNB",
            "VRBO",
            // booking
            "EXPEDIA", "BOOKING.COM", "BOOKING COM", "HOTELS.COM", "HOTELS COM",
            "PRICELINE", "KAYAK", "TRIVAGO", "FLIGHTHUB", "FLIGHT CENTRE",
        ]),

        // ── Logement (home improvement / furniture) ────────────────────────
        (.logement, [
            "RONA", "RENO DEPOT", "RENO-DEPOT", "HOME DEPOT", "HOMEDEPOT", "LOWES",
            "HOME HARDWARE", "HOMEHARDWARE", "PATRICK MORIN", "BMR", "MENARDS",
            "ACE HARDWARE", "IKEA", "STRUCTUBE", "THE BRICK", "LEON", "WAYFAIR",
            "BED BATH", "HOMESENSE", "BOUCLAIR", "URBAN BARN", "POTTERY BARN",
            "WEST ELM", "LOYER", "HYPOTHEQUE", "MORTGAGE",
        ]),

        // ── Éducation ──────────────────────────────────────────────────────
        (.education, [
            "UNIVERSITE", "UNIVERSITY", "COLLEGE", "CEGEP", "UQAM", "MCGILL",
            "CONCORDIA", "POLYTECHNIQUE", "COURSERA", "UDEMY", "SKILLSHARE",
            "SCOLARITE", "TUITION", "CHEGG", "DUOLINGO",
        ]),
    ]

    /// Flat, specificity-ordered rules (multi-word & longer keywords first, so
    /// "UBER EATS" wins over "UBER", "OVERDRAFT" over "INTEREST").
    static let rules: [(keyword: String, category: CanonicalCategory)] = {
        var r: [(String, CanonicalCategory)] = []
        for (cat, kws) in raw { for kw in kws { r.append((kw.uppercased(), cat)) } }
        return r.sorted { a, b in
            let at = a.0.split(separator: " ").count, bt = b.0.split(separator: " ").count
            if at != bt { return at > bt }
            return a.0.count > b.0.count
        }
    }()

    /// First canonical whose keyword matches the (already normalized) haystack.
    /// Pass `income` to restrict to income- or expense-side categories.
    static func category(forNormalized haystack: String, income: Bool? = nil) -> CanonicalCategory? {
        guard !haystack.isEmpty else { return nil }
        let padded = " \(haystack) "
        for rule in rules where (income == nil || rule.category.isIncome == income)
            && padded.contains(" \(rule.keyword)") {
            return rule.category
        }
        return nil
    }
}
