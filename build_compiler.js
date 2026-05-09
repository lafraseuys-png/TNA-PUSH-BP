const fs = require('fs');
const path = require('path');
const JavaScriptObfuscator = require('javascript-obfuscator');

// Define your directories here
const sourceDir = __dirname; // Change 'src' to wherever your JS files live
const buildDir = 'C:\\Apps\\encryptedApp';

// Files that should NEVER be obfuscated (add your specific config file names here)
const ignoreList = ['.env', 'config.js', 'database.js', 'build_compiler.js', 'secrets.env', 'config', 'build_encrypted', '.gitignore', 'README.md', 'web.config', 'ecosystem.config.js'];
function processDirectory(currentDir, targetDir) {
    if (!fs.existsSync(targetDir)) {
        fs.mkdirSync(targetDir, { recursive: true });
    }

    const items = fs.readdirSync(currentDir);

    for (const item of items) {
        const srcPath = path.join(currentDir, item);
        const destPath = path.join(targetDir, item);

       // Completely skip node_modules, the build folder itself, git history, and secrets files so environments don't overwrite each other
        if (item === 'node_modules' || item === 'build_encrypted' || item === '.git' || item === 'secrets.env' || item === '.env') continue;

        const isIgnored = ignoreList.includes(item);

        if (fs.statSync(srcPath).isDirectory()) {
            // If it is a folder, run the function again to go deeper
            processDirectory(srcPath, destPath);
        } else {
            if (isIgnored || !item.endsWith('.js')) {
                // Copy non-JS files and ignored config files exactly as they are
                fs.copyFileSync(srcPath, destPath);
                console.log(`Copied Plain Text: ${item}`);
            } else {
                // Read the plain text JS code
                const code = fs.readFileSync(srcPath, 'utf8');
                
                // Obfuscate the code securely
                const obfuscationResult = JavaScriptObfuscator.obfuscate(code, {
                    compact: true,
                    controlFlowFlattening: true,
                    deadCodeInjection: true,
                    stringArray: true,
                    stringArrayEncoding: ['base64'],
                    disableConsoleOutput: false 
                });
                
                // Save the scrambled code to the new build folder
                fs.writeFileSync(destPath, obfuscationResult.getObfuscatedCode());
                console.log(`Secured/Obfuscated: ${item}`);
            }
        }
    }
}

// Start the build process
console.log("Starting TNA Africa build process...");
processDirectory(sourceDir, buildDir);
console.log("Build complete. Ready for local VS Code testing.");