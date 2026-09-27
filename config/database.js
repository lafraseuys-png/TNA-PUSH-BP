const sql = require('mssql');
// DEMO / SETUP MODE: marks the requests that belong to a demo session (set in middleware/auth.js).
// Everything below behaves exactly as before for every other request.
const { AsyncLocalStorage } = require('async_hooks');
const demoContext = new AsyncLocalStorage();

// Master DB Config
const masterConfig = {
    server: process.env.DB_SERVER,
    port: process.env.DB_PORT ? parseInt(process.env.DB_PORT, 10) : 1433,
    database: process.env.DB_NAME,
    options: {
        encrypt: false,
        trustServerCertificate: true,
        connectionTimeout: 30000,
        requestTimeout: 60000,
        useUTC: false
    },
    // PERFORMANCE FIX: Restrict max connections to 10. 
    // This forces Node to recycle lightning-fast connections instead of opening 16 concurrent TCP handshakes,
    // completely preventing SQL Server from triggering its 25-second Anti-DDoS login throttle.
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
};

// AUTO-HEAL: Support both standard SQL Authentication and Domain NTLM Authentication
if (process.env.DB_DOMAIN) {
    masterConfig.authentication = {
        type: 'ntlm',
        options: {
            domain: process.env.DB_DOMAIN,
            userName: process.env.DB_USER,
            password: process.env.DB_PASSWORD
        }
    };
} else {
    masterConfig.user = process.env.DB_USER;
    masterConfig.password = process.env.DB_PASSWORD;
}

const masterPool = new sql.ConnectionPool(masterConfig);
masterPool.on('error', err => console.error('⚠️ Master SQL Pool Error Caught:', err.message));

// DEMO / SETUP MODE (AUTO-HEAL): a demo request may never change devices or company-wide settings.
// Writes to these master tables are refused; everything else runs normally.
const DEMO_BLOCKED_MASTER_WRITES = /\b(INSERT\s+INTO|UPDATE|DELETE\s+FROM|DELETE|MERGE(\s+INTO)?)\s+(dbo\.)?\[?(command_queue|Devices|Tenants|SystemSecuritySettings)\]?(\s|\(|$)/i;
const realMasterRequest = masterPool.request.bind(masterPool);
masterPool.request = function () {
    const r = realMasterRequest.apply(null, arguments);
    const demo = demoContext.getStore();
    if (!demo) return r;
    const realQuery = r.query.bind(r);
    r.query = function (text) {
        if (typeof text === 'string' && DEMO_BLOCKED_MASTER_WRITES.test(text)) {
            console.log('[Demo] Blocked a master-database change from a demo request.');
            const err = new Error('Blocked in demo / setup mode: devices and company-wide settings are not changed from a demo copy.');
            err.code = 'TNA_DEMO_BLOCKED';
            return Promise.reject(err);
        }
        return realQuery.apply(null, arguments);
    };
    return r;
};

const tenantPools = {};
const tenantConnecting = {}; 

async function connectMaster() {
    try {
        // Primary Phase: Force attempt on standard SQL port 1433
        masterConfig.port = 1433;
        masterPool.config.port = 1433;
        
        if (!masterPool.connected && !masterPool.connecting) {
            await masterPool.connect();
        }
        console.log('✔ Connected to Master DB on default port 1433');
    } catch (err) {
        console.log('✘ Connection failed on 1433. Attempting fallback to secrets.env DB_PORT...');
        
        // Fallback Phase: Use custom port from secrets.env
        if (process.env.DB_PORT) {
            const customPort = parseInt(process.env.DB_PORT, 10);
            try {
                masterConfig.port = customPort;        // Updates config so future Tenant pools use the right port
                masterPool.config.port = customPort;   // Updates the current Master pool connection logic
                
                await masterPool.connect();
                console.log(`✔ Successfully connected to Master DB on fallback port ${customPort}`);
            } catch (fallbackErr) {
                console.error(`✘ Fallback Connection also failed on port ${customPort}:`, fallbackErr.message);
                throw fallbackErr; // Send the real error up to server.js
            }
        } else {
            console.error('✘ No DB_PORT found in secrets.env. Cannot attempt fallback.');
        }
    }
}

async function getTenantConnection(dbName) {
    // DEMO / SETUP MODE (AUTO-HEAL): a request in a demo session gets the tenant's sandbox copy
    // instead of its live database. Any other request, or any other database, is unchanged.
    const demo = demoContext.getStore();
    if (demo && dbName && demo.liveDb && demo.sandboxDb &&
        String(dbName).trim().toLowerCase() === String(demo.liveDb).trim().toLowerCase()) {
        dbName = demo.sandboxDb;
    }
    if (!dbName) {
        throw new Error("getTenantConnection was called with an undefined or empty database name!");
    }
    
    const targetDb = String(dbName).trim(); 
    
    // 1. FAST PATH: Return existing pool instantly. No SELECT 1 ping bottleneck!
    if (tenantPools[targetDb]) {
        return tenantPools[targetDb];
    }

    // 2. THE LOCK: If another request is already building the connection, wait for it!
    if (tenantConnecting[targetDb]) {
        try { await tenantConnecting[targetDb]; } catch(e) {}
        if (tenantPools[targetDb]) return tenantPools[targetDb];
        throw new Error(`Database ${targetDb} is unavailable.`);
    }

    // 3. BUILD AND LOCK
    if (!tenantPools[targetDb]) {
        tenantConnecting[targetDb] = (async () => {
            console.log(`[DB ROUTER] Attempting to connect to Tenant DB: >>>${targetDb}<<<`);
            try {
                const pool = new sql.ConnectionPool({ ...masterConfig, database: targetDb });
                await pool.connect();
                console.log(`[DB ROUTER] Successfully connected to ${targetDb}!`);
                tenantPools[targetDb] = pool;
            } catch (err) {
                // SILENCED: Mute the terminal spam for databases that don't exist yet on QC
                throw new Error(`Connection to ${targetDb} failed.`); 
            }
        })();
        
        try {
            await tenantConnecting[targetDb];
        } catch (e) {} 
        
        tenantConnecting[targetDb] = null; // Unlock the door
    }
    
    if (!tenantPools[targetDb]) {
        throw new Error(`Database ${targetDb} is unavailable.`);
    }
    
    return tenantPools[targetDb];
}

// Closes a cached tenant connection (used before a demo sandbox is deleted or refreshed)
async function closeTenantPool(dbName) {
    const key = String(dbName || '').trim();
    const pool = tenantPools[key];
    delete tenantPools[key];
    if (pool) { try { await pool.close(); } catch (e) {} }
}

module.exports = {
    masterPool,
    connectMaster,
    getTenantConnection,
    demoContext,
    closeTenantPool
};