module.exports = {
  apps: [
    {
      name: "server_TNAQC",
      script: "server.js",
      watch: false,
      env: {
        NODE_ENV: "qc"
      }
    },
    {
      name: "tna_server_TNAQC",
      script: "tna_server.js",
      watch: false,
      env: {
        NODE_ENV: "qc",
        PORT: 3041 // FIXED: Moved TNA Engine to its dedicated port to prevent collision
      }
    },
    {
      name: "hr_server_TNAQC",
      script: "hr_server.js",
      watch: false,
      env: {
        NODE_ENV: "qc",
        PORT: 3633 // Usually HR runs on 3633 based on your proxy settings
      }
    },
    {
      name: "hardware_TNAQC",
      script: "hardware.js", 
      watch: false,
      env: {
        NODE_ENV: "qc",
        PORT: 3200 // Usually HW runs on 3200 based on your proxy settings
      }
    },
    {
      name: "Fuelserver_TNAQC",
      script: "Fuelserver.js",
      watch: false,
      env: {
        NODE_ENV: "qc"
      }
    },
    {
      name: "server_TNAPROD",
      script: "server.js",
      watch: false,
      env: {
        NODE_ENV: "production"
      }
    },
    {
      name: "tna_server_TNAPROD",
      script: "tna_server.js",
      watch: false,
      env: {
        NODE_ENV: "production",
        PORT: 3042
      }
    },
    {
      name: "hr_server_TNAPROD",
      script: "hr_server.js",
      watch: false,
      env: {
        NODE_ENV: "production",
        PORT: 3634
      }
    },
    {
      name: "hardware_TNAPROD",
      script: "hardware.js", 
      watch: false,
      env: {
        NODE_ENV: "production",
        PORT: 3201
      }
    },
    {
      name: "Fuelserver_TNAPROD",
      script: "Fuelserver.js",
      watch: false,
      env: {
        NODE_ENV: "production"
      }
    }
  ]
};