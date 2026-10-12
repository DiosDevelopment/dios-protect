-- dios_protect settings
-- Edit values below. Keep field names unchanged; validation runs at resource startup.
-- Custom server key integration: config/integration.lua

Protect = {
    -- GENERAL
    -- ----------------------------------------------------------------
    -- en = English, es = Spanish, nl = Dutch, de = German, hi = Hindi.
    -- Add locales/<code>.json for another language.
    locale = 'en',

    -- FRAMEWORK AND VEHICLE KEYS
    -- ----------------------------------------------------------------
    integration = {
        -- auto: Falcon > QBox > QBCore > ESX > standalone. Or select a framework explicitly.
        framework = 'auto',
        -- Register missing job definitions when the framework supports it. ESX uses the setup SQL.
        createJobs = true,
        -- auto: all started providers below. Or use an adapter ID, none, or custom.
        keys = 'auto',
        -- Change resource names here when a supported core has been renamed.
        resources = {
            falcon = 'falcon_core',
            qbox = 'qbx_core',
            qbcore = 'qb-core',
            esx = 'es_extended',
        },
    },
    -- Adapter ID = resource name. Change names here for renamed key resources.
    keyResources = {
        qbox = 'qbx_vehiclekeys',
        qbcore = 'qb-vehiclekeys',
        wasabi = 'wasabi_carlock',
        renewed = 'Renewed-Vehiclekeys',
        mrnewb = 'MrNewbVehicleKeys',
        zrx = 'zrx_carlock',
        jaksam = 'vehicles_keys',
        quasar = 'qs-vehiclekeys',
        codesign = 'cd_garage',
        okok = 'okokGarage',
        t1ger = 't1ger_keys',
        mk = 'mk_vehiclekeys',
        ak47 = 'ak47_vehiclekeys',
        ak47qb = 'ak47_qb_vehiclekeys',
    },

    -- COMMANDS AND ACCESS
    -- ----------------------------------------------------------------
    commands = {
        menu = 'protect',
        controls = 'detailcontrol',
        diagnostics = 'detailstatus',
        environment = 'protectenvironment',
    },
    standalone = {
        -- Required ACE permission when running without a framework.
        presidentAce = 'dios_protect.president',
    },
    access = {
        -- Minimum President job grade required to manage a detail.
        minimumGrade = 0,
        -- Require the President to be on duty when using a framework.
        requireDuty = false,
    },

    -- JOBS AND PAY
    -- ----------------------------------------------------------------
    presidentJob = 'president',
    serviceJob = 'secretservice',
    -- Job templates for supported frameworks. Payments are framework salaries; standalone has no payroll.
    jobs = {
        president = {
            label = 'President',
            defaultDuty = true,
            offDutyPay = false,
            grades = {
                [0] = {
                    name = 'President',
                    payment = 300,
                    isboss = true,
                },
            },
        },
        service = {
            label = 'Secret Service',
            defaultDuty = true,
            offDutyPay = false,
            grades = {
                [0] = {
                    name = 'Protection Agent',
                    payment = 150,
                },
                [1] = {
                    name = 'Detail Commander',
                    payment = 200,
                    isboss = true,
                },
            },
        },
    },

    -- INTERFACE
    -- ----------------------------------------------------------------
    ui = {
        brand = 'DIOS SCRIPTS',
        office = 'EXECUTIVE PROTECTION',
        accent = '#ddc68e',
        -- Initial guard count shown in the deployment menu.
        defaultGuards = 4,
    },

    -- SERVER DIAGNOSTICS
    -- ----------------------------------------------------------------
    diagnostics = {
        enabled = true,
        -- Scan readable resource scripts for possible entity-spawn blockers (advisory only).
        scanScripts = true,
        -- Known resources to flag in the server console when present.
        resources = {
            ['qb-smallresources'] = 'May blacklist protection vehicles/peds in server/entities.lua.',
            ['qbx_smallresources'] = 'May suppress or blacklist protection models.',
            ['esx_blacklist'] = 'May block protection vehicle or ped models.',
        },
    },

    -- DETAIL LIMITS
    -- ----------------------------------------------------------------
    -- Maximum foot NPC guards per detail; vehicle crew are separate.
    maxGuards = 6,
    -- Maximum ground vehicles per detail.
    maxVehicles = 20,
    -- Maximum appointed player agents per President.
    maxAgents = 6,
    -- Server-wide cap on protection vehicles and NPCs, including pending deployment reservations.
    globalEntityLimit = 80,

    -- INVITATIONS AND DEPLOYMENT
    -- ----------------------------------------------------------------
    -- Metres: maximum distance for offering and accepting an appointment.
    inviteRange = 25.0,
    -- Seconds: time allowed to accept an invitation.
    inviteExpiry = 60,
    -- Seconds: minimum interval between deployment requests.
    deployCooldown = 10,
    -- Metres: minimum distance from the President for foot staging.
    footSpawnMin = 45.0,
    -- Metres: minimum distance from the President for vehicle staging.
    vehicleSpawnMin = 90.0,
    -- Metres: maximum staging distance.
    spawnMax = 380.0,
    -- Metres: maximum allowed staging height difference.
    stagingHeightRange = 80.0,

    -- GUARD LOADOUT AND APPEARANCE
    -- ----------------------------------------------------------------
    guardWeapon = 'WEAPON_CARBINERIFLE',
    -- GTA health scale, not a percentage.
    guardHealth = 250,
    -- Armour assigned when the guard is first equipped.
    guardArmour = 100,
    -- Models are checked on the client. concealed keeps weapons holstered until needed.
    guards = {
        police = {
            label = 'Police protection',
            model = 's_m_y_swat_01',
            models = { 's_m_y_swat_01', 's_m_y_cop_01', 's_f_y_cop_01' },
        },
        military = {
            label = 'Military protection',
            model = 's_m_y_marine_01',
            models = { 's_m_y_marine_01', 's_m_y_marine_02', 's_m_y_marine_03' },
        },
        civilian = {
            label = 'Plainclothes protection',
            concealed = true,
            models = { 's_m_m_highsec_01', 's_m_m_highsec_02', 's_m_m_fiboffice_01', 's_m_m_fiboffice_02' },
        },
        casual = {
            label = 'Casual protection',
            concealed = true,
            models = { 'a_m_y_business_02', 's_m_y_dealer_01', 'a_m_y_hipster_01', 'a_f_y_business_02' },
        },
    },

    -- CONVOY VEHICLE CATALOG
    -- ----------------------------------------------------------------
    -- seats = NPC crew count (including driver), not total vehicle seats. Leave space for the President.
    vehicles = {
        { model = 'granger2', label = 'Armored Granger', category = 'Executive', seats = 2 },
        { model = 'baller6', label = 'Armored Baller', category = 'Executive', seats = 2 },
        { model = 'cavalcade3', label = 'Cavalcade XL', category = 'Executive', seats = 2 },
        { model = 'insurgent', label = 'Insurgent', category = 'Military', seats = 2 },
        { model = 'barrage', label = 'Barrage', category = 'Military', seats = 2 },
        { model = 'crusader', label = 'Crusader', category = 'Military', seats = 2 },
        { model = 'rhino', label = 'Rhino tank', category = 'Military', seats = 1 },
        { model = 'apc', label = 'Armored personnel carrier', category = 'Military', seats = 2 },
        { model = 'halftrack', label = 'Half-track escort', category = 'Military', seats = 2 },
        { model = 'police', label = 'Police cruiser', category = 'Police', seats = 2 },
        { model = 'police3', label = 'Police interceptor', category = 'Police', seats = 2 },
    },

    -- CONVOY DRIVING
    -- ----------------------------------------------------------------
    -- km/h: initial requested convoy speed, capped by the slowest vehicle.
    defaultSpeedKph = 60,
    -- Metres: initial convoy spacing (allowed range: 4?20).
    defaultGap = 6,
    -- Vehicle count above which the extended convoy layout is used.
    longConvoyThreshold = 5,
    -- Metres: spacing for extended convoys.
    longConvoyGap = 10,
    -- Milliseconds: delay between departures in an extended convoy.
    longDepartureInterval = 700,

    -- HELICOPTER SUPPORT
    -- ----------------------------------------------------------------
    airModel = 'polmav',
    -- Seconds: minimum interval between helicopter requests.
    airCooldown = 45,
    -- Metres: normal helicopter escort altitude.
    airHeight = 85,
    airWeapon = 'WEAPON_CARBINERIFLE',

    -- UPDATE INTERVALS AND TIMEOUTS
    -- ----------------------------------------------------------------
    -- All intervals/timeouts below are milliseconds. AI uses common natives in both GTA editions.
    performance = {
        aiTick = 650,
        -- Foot-slot supervision only; persistent native tasks track the VIP between updates.
        formationTick = 50,
        maintenanceTick = 2000,
        stagingTimeout = 30000,
        -- Total client preparation budget, including model loading and hidden-position search.
        deploymentPreparationTimeout = 30000,
        -- One shared search deadline for the entire selected detail, not per NPC/vehicle.
        stagingSearchTimeout = 10000,
        modelTimeout = 5000,
    },

    -- TACTICAL BEHAVIOR (ADVANCED)
    -- ----------------------------------------------------------------
    -- Distances are metres and times are milliseconds unless stated. Reports never authorize arbitrary spawning, damage, jobs or blacklist exemptions.
    tactical = {
        -- Detection and reporting
        enabled = true,
        scanInterval = 750,
        reportInterval = 1000,
        maxScanPeds = 96,
        maxThreats = 16,
        awarenessRadius = 65,
        attackRadius = 150,
        suspicionThreshold = 18,
        threatThreshold = 45,

        -- Protection zones and threat scoring
        -- Protection zones around the President, in metres.
        radii = {
            inner = 4,
            close = 10,
            observation = 25,
            outer = 50,
        },
        contactThreshold = 75,
        -- Threat-score points removed per second without fresh evidence.
        decayPerSecond = 12,
        forgetAfter = 12000,
        clearPeriod = 6000,

        -- Recovery and close protection
        recoveryPeriod = 4000,
        aimSustain = 1500,
        minimumCloseGuards = 2,
        -- adaptive / diamond / box / column / close / loose / left / right.
        formation = 'adaptive',

        -- Formation movement
        spacing = 2.2,
        looseSpacing = 3.8,
        movementTolerance = 0.35,
        -- Seconds of bounded slot prediction to counter native follow/braking latency.
        formationLookAhead = 0.45,
        taskRefresh = 3000,

        -- Extraction
        automaticExtraction = true,
        -- GTA health scale used to trigger automatic extraction.
        extractionHealth = 125,
        extractionSustain = 3000,
        extractionRadius = 80,
        -- m/s: approaching-vehicle suspicion threshold.
        vehicleApproachSpeed = 16,
        driverReadinessTimeout = 15000,
        replaceDeadDriver = true,
        extractionBlip = true,
        preferredVehicle = 'granger2',
        -- Server-side job trust map; empty by default. Example: { police = true }.
        trustedJobs = {},

        -- Tactical air support
        -- Metres: helicopter altitude during tactical support.
        airSupportHeight = 75,
        -- m/s: helicopter speed during emergency support.
        emergencyHeliSpeed = 40,
    },
}
