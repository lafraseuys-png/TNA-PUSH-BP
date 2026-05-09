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
    // TRACER ROUND: Strip invisible spaces and log the exact target
    if (!dbName) {
        throw new Error("getTenantConnection was called with an undefined or empty database name!");
    }
    
    const targetDb = String(dbName).trim(); 
    console.log(`[DB ROUTER] Attempting to connect to Tenant DB: >>>${targetDb}<<<`);
    
    if (tenantPools[targetDb]) {
        try {
            await tenantPools[targetDb].request().query('SELECT 1');
            return tenantPools[targetDb];
        } catch (e) {
            console.log(`[DB ROUTER] Existing pool for ${targetDb} died. Rebuilding...`);
            tenantPools[targetDb] = null;
        }
    }
    
    if (!tenantPools[targetDb]) {
        tenantConnecting[targetDb] = (async () => {
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
        
        // Catch the rejection right here so it doesn't escape as an Unhandled Promise Rejection!
        try {
            await tenantConnecting[targetDb];
        } catch (e) {} 
        
        tenantConnecting[targetDb] = null; 
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