const sql = require('mssql');

// Master DB Config
const masterConfig = {
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD, 
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

const masterPool = new sql.ConnectionPool(masterConfig);
masterPool.on('error', err => console.error('⚠️ Master SQL Pool Error Caught:', err.message));

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
            try {
                const customPort = parseInt(process.env.DB_PORT, 10);
                masterConfig.port = customPort;        // Updates config so future Tenant pools use the right port
                masterPool.config.port = customPort;   // Updates the current Master pool connection logic
                
                await masterPool.connect();
                console.log(`✔ Successfully connected to Master DB on fallback port ${customPort}`);
            } catch (fallbackErr) {
                console.error(`✘ Fallback Connection also failed on port ${customPort}:`, fallbackErr.message);
            }
        } else {
            console.error('✘ No DB_PORT found in secrets.env. Cannot attempt fallback.');
        }
    }
}

async function getTenantConnection(dbName) {
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

module.exports = {
    masterPool,
    connectMaster,
    getTenantConnection
};