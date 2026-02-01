const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const os = require('os');

const dataDir = path.join(__dirname, 'data');
const keyFile = path.join(dataDir, 'key.txt');
const tasksFile = path.join(dataDir, 'tasks.json');
const homeKey = path.join(os.homedir(), '.executive-key');
const homeMachine = path.join(os.homedir(), '.executive-machine');
const homeHost = path.join(os.homedir(), '.executive-host');

// Create data dir
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

// Generate API key
let apiKey;
if (fs.existsSync(keyFile)) {
  apiKey = fs.readFileSync(keyFile, 'utf8').trim();
  console.log('API key already exists, keeping it.');
} else {
  apiKey = crypto.randomBytes(32).toString('hex');
  fs.writeFileSync(keyFile, apiKey);
  console.log('Generated new API key.');
}

// Init tasks file
if (!fs.existsSync(tasksFile)) {
  fs.writeFileSync(tasksFile, JSON.stringify({ tasks: [] }, null, 2));
  console.log('Created tasks.json');
}

// Write home config files
fs.writeFileSync(homeKey, apiKey);
console.log(`Wrote API key to ${homeKey}`);

if (!fs.existsSync(homeMachine)) {
  fs.writeFileSync(homeMachine, 'local');
  console.log(`Wrote machine identity to ${homeMachine}`);
} else {
  console.log(`Machine identity already set: ${fs.readFileSync(homeMachine, 'utf8').trim()}`);
}

if (!fs.existsSync(homeHost)) {
  fs.writeFileSync(homeHost, 'http://localhost:7777');
  console.log(`Wrote dashboard host to ${homeHost}`);
} else {
  console.log(`Dashboard host already set: ${fs.readFileSync(homeHost, 'utf8').trim()}`);
}

console.log('\n--- Setup complete ---');
console.log(`API Key: ${apiKey}`);
console.log('Run: npm start');
