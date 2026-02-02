const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const os = require('os');
const readline = require('readline');

const envFile = path.join(__dirname, '.env');
const dataDir = path.join(__dirname, 'data');
const tasksFile = path.join(dataDir, 'tasks.json');
const homeKey = path.join(os.homedir(), '.executive-key');
const homeMachine = path.join(os.homedir(), '.executive-machine');
const homeHost = path.join(os.homedir(), '.executive-host');

async function setup() {
  // Create data dir
  if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

  // Init tasks file
  if (!fs.existsSync(tasksFile)) {
    fs.writeFileSync(tasksFile, JSON.stringify({ tasks: [] }, null, 2));
    console.log('Created tasks.json');
  }

  // Check if .env already exists
  let envVars = {};
  if (fs.existsSync(envFile)) {
    const content = fs.readFileSync(envFile, 'utf8');
    for (const line of content.split('\n')) {
      const match = line.match(/^([^#=]+)=(.*)$/);
      if (match) envVars[match[1].trim()] = match[2].trim();
    }
    console.log('Found existing .env file.');
  }

  // Generate API key if missing
  if (!envVars.EXECUTIVE_API_KEY) {
    envVars.EXECUTIVE_API_KEY = crypto.randomBytes(32).toString('hex');
    console.log('Generated new API key.');
  } else {
    console.log('API key already set.');
  }

  // Generate cookie secret if missing
  if (!envVars.EXECUTIVE_COOKIE_SECRET) {
    envVars.EXECUTIVE_COOKIE_SECRET = crypto.randomBytes(32).toString('hex');
    console.log('Generated new cookie secret.');
  }

  // Set port default
  if (!envVars.EXECUTIVE_PORT) {
    envVars.EXECUTIVE_PORT = '7778';
  }

  // Prompt for password if hash missing
  if (!envVars.EXECUTIVE_PASSWORD_HASH) {
    const bcrypt = require('bcrypt');
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const password = await new Promise(resolve => {
      rl.question('Set dashboard password: ', answer => {
        rl.close();
        resolve(answer);
      });
    });
    if (!password) {
      console.error('Password cannot be empty.');
      process.exit(1);
    }
    envVars.EXECUTIVE_PASSWORD_HASH = await bcrypt.hash(password, 12);
    console.log('Password hashed.');
  } else {
    console.log('Password hash already set.');
  }

  // Write .env
  const envContent = [
    '# Executive Cloud Configuration',
    `EXECUTIVE_PASSWORD_HASH=${envVars.EXECUTIVE_PASSWORD_HASH}`,
    `EXECUTIVE_API_KEY=${envVars.EXECUTIVE_API_KEY}`,
    `EXECUTIVE_COOKIE_SECRET=${envVars.EXECUTIVE_COOKIE_SECRET}`,
    `EXECUTIVE_PORT=${envVars.EXECUTIVE_PORT}`,
    '',
  ].join('\n');
  fs.writeFileSync(envFile, envContent);
  console.log(`Wrote ${envFile}`);

  // Write home config files
  fs.writeFileSync(homeKey, envVars.EXECUTIVE_API_KEY);
  console.log(`Wrote API key to ${homeKey}`);

  if (!fs.existsSync(homeMachine)) {
    fs.writeFileSync(homeMachine, 'local');
    console.log(`Wrote machine identity to ${homeMachine}`);
  }

  // Server machine always talks to localhost directly
  fs.writeFileSync(homeHost, 'http://127.0.0.1:7778');
  console.log(`Wrote ${homeHost} = http://127.0.0.1:7778`);

  console.log('\n--- Setup complete ---');
  console.log(`API Key: ${envVars.EXECUTIVE_API_KEY}`);
  console.log('Run: ./start.sh');
}

setup().catch(err => {
  console.error('Setup failed:', err);
  process.exit(1);
});
