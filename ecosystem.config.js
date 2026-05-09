module.exports = {
  apps: [
    {
      name: "server_TNAPROD",
      script: "server.js",
      watch: false,
      env: { NODE_ENV: "production", PORT: 3035 }
    },
    {
      name: "tna_server_TNAPROD",
      script: "tna_server.js",
      watch: false,
      env: { NODE_ENV: "production", PORT: 3042 }
    },
    {
      name: "hr_server_TNAPROD",
      script: "hr_server.js",
      watch: false,
      env: { NODE_ENV: "production", PORT: 3634 }
    },
    {
      name: "hardware_TNAPROD",
      script: "hardware.js", 
      watch: false,
      env: { NODE_ENV: "production", PORT: 3201 }
    },
    {
      name: "Fuelserver_TNAPROD",
      script: "Fuelserver.js",
      watch: false,
      env: { NODE_ENV: "production", PORT: 3308 }
    }
  ]
};