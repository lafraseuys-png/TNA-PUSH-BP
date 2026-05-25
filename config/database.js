const sql = require('mssql');

// Master DB Config
const masterConfig = {
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD, // <-- Back to reading from secrets.env!
    server: process.env.DB_SERVER,
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
        if (!masterPool.connected && !masterPool.connecting) {
            await masterPool.connect();
        }
        console.log('✔ Connected to Master DB');
    } catch (err) {
        console.error('✘ Master DB Connection Failed:', err);
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