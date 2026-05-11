const fs = require('fs');
const path = require('path');
const JavaScriptObfuscator = require('javascript-obfuscator');

// Define your directories here
const sourceDir = __dirname; // Change 'src' to wherever your JS files live
const buildDir = 'C:\\Apps\\encryptedApp';

// Files that should NEVER be obfuscated
const ignoreList = ['.env', 'config.js', 'database.js', 'builder_compiler.js', 'secrets.env', 'config', 'build_encrypted', '.gitignore', 'README.md', 'web.config', 'ecosystem.config.js'];

// --- NEW: Single File Processor ---
function processSingleFile(relativeFilePath) {
    const srcPath = path.join(sourceDir, relativeFilePath);
    const destPath = path.join(buildDir, relativeFilePath);
    const item = path.basename(srcPath);

    if (!fs.existsSync(srcPath)) {
        console.error(`\n❌ Error: File not found at ${srcPath}`);
        return;
    }

    // Ensure the target directory exists (if the file is inside a subfolder)
    const targetFolder = path.dirname(destPath);
    if (!fs.existsSync(targetFolder)) {
        fs.mkdirSync(targetFolder, { recursive: true });
    }

    const isIgnored = ignoreList.includes(item);

    if (isIgnored || !item.endsWith('.js')) {
        // Copy non-JS files and ignored config files exactly as they are
        fs.copyFileSync(srcPath, destPath);
        console.log(`✅ Copied Plain Text: ${relativeFilePath}`);
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
        console.log(`🔒 Secured/Obfuscated: ${relativeFilePath}`);
    }
}

// --- EXISTING: Full Directory Processor ---
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

// --- UPDATED: Execution Logic ---
// process.argv[2] grabs the first argument passed after the file name
const targetFile = process.argv[2];

if (targetFile) {
    // If a file was specified, only process that file
    console.log(`\nStarting single file build process for: ${targetFile}...`);
    processSingleFile(targetFile);
    console.log("Single file build complete.\n");
} else {
    // If no file was specified, run the full directory
    console.log("\nStarting full build process...");
    processDirectory(sourceDir, buildDir);
    console.log("Full build complete. Ready for local VS Code testing.\n");
}