require('dotenv').config();
const express = require('express');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');
const bcrypt = require('bcrypt');
const cookieParser = require('cookie-parser');

const app = express();
const PORT = process.env.EXECUTIVE_PORT || 7778;
const DATA_DIR = path.join(__dirname, 'data');
const TASKS_FILE = path.join(DATA_DIR, 'tasks.json');

const API_KEY = process.env.EXECUTIVE_API_KEY || '';
const PASSWORD_HASH = process.env.EXECUTIVE_PASSWORD_HASH || '';
const COOKIE_SECRET = process.env.EXECUTIVE_COOKIE_SECRET || 'change-me';

if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
if (!fs.existsSync(TASKS_FILE)) fs.writeFileSync(TASKS_FILE, JSON.stringify({ tasks: [] }));

// Session store (in-memory, single user)
const sessions = new Set();

function loadTasks() {
  try { return JSON.parse(fs.readFileSync(TASKS_FILE, 'utf8')); }
  catch { return { tasks: [] }; }
}

function saveTasks(data) {
  const tmp = TASKS_FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
  fs.renameSync(tmp, TASKS_FILE);
}

const sseClients = [];
function broadcast(event, data) {
  const msg = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  sseClients.forEach(res => res.write(msg));
}

app.use(express.json());
app.use(cookieParser(COOKIE_SECRET));

// Auth middleware — checks cookie OR API key on every request
function requireAuth(req, res, next) {
  // Check API key header (for hooks / machine-to-machine)
  const apiKey = req.headers['x-api-key'];
  if (API_KEY && apiKey === API_KEY) return next();

  // Check signed session cookie (for browser)
  const sessionToken = req.signedCookies['executive-session'];
  if (sessionToken && sessions.has(sessionToken)) return next();

  // Not authenticated
  if (req.path.startsWith('/api/')) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  return res.redirect('/login.html');
}

// Public routes (no auth needed)
app.get('/login.html', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'login.html'));
});

app.post('/api/login', async (req, res) => {
  const { password } = req.body;
  if (!password || !PASSWORD_HASH) {
    return res.status(401).json({ error: 'invalid credentials' });
  }
  const match = await bcrypt.compare(password, PASSWORD_HASH);
  if (!match) {
    return res.status(401).json({ error: 'invalid credentials' });
  }
  const token = crypto.randomBytes(32).toString('hex');
  sessions.add(token);
  res.cookie('executive-session', token, {
    signed: true,
    httpOnly: true,
    secure: true,
    sameSite: 'strict',
    maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days
  });
  res.json({ success: true });
});

// Everything below requires auth
app.use(requireAuth);

// Serve static files (behind auth)
app.use(express.static(path.join(__dirname, 'public')));

app.post('/api/logout', (req, res) => {
  const token = req.signedCookies['executive-session'];
  if (token) sessions.delete(token);
  res.clearCookie('executive-session');
  res.json({ success: true });
});

// SSE
app.get('/api/events', (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();
  sseClients.push(res);
  req.on('close', () => {
    const idx = sseClients.indexOf(res);
    if (idx >= 0) sseClients.splice(idx, 1);
  });
});

// List tasks
app.get('/api/tasks', (req, res) => {
  res.json(loadTasks());
});

// Register session (SessionStart + PreToolUse hooks call this)
app.post('/api/register', (req, res) => {
  const { sessionId, machine, cwd } = req.body;
  if (!sessionId) return res.status(400).json({ error: 'sessionId required' });

  const data = loadTasks();
  const existing = data.tasks.find(t => t.sessionId === sessionId);
  if (existing) return res.json({ taskId: existing.id, resumed: true });

  const task = {
    id: uuidv4(),
    title: cwd ? path.basename(cwd) : 'unknown',
    tier: 'routine',
    status: 'working',
    machine: machine || 'unknown',
    autopilot: false,
    sessionId,
    cwd: cwd || null,
    createdAt: new Date().toISOString(),
    completedAt: null,
  };
  data.tasks.push(task);
  saveTasks(data);
  broadcast('task-created', task);
  res.json({ taskId: task.id, resumed: false });
});

// Mark complete (Stop hook)
app.post('/api/complete', (req, res) => {
  const { taskId } = req.body;
  if (!taskId) return res.status(400).json({ error: 'taskId required' });
  const data = loadTasks();
  const task = data.tasks.find(t => t.id === taskId);
  if (!task) return res.status(404).json({ error: 'not found' });
  if (task.status !== 'done') {
    task.status = 'done';
    task.completedAt = new Date().toISOString();
    saveTasks(data);
    broadcast('task-complete', task);
  }
  res.json({ success: true });
});

// Check autopilot (PreToolUse hook)
app.post('/api/autopilot', (req, res) => {
  const { taskId, check } = req.body;
  if (check !== '1') return res.json({ allow: false });
  if (!taskId) return res.json({ allow: false });
  const data = loadTasks();
  const task = data.tasks.find(t => t.id === taskId);
  if (!task) return res.json({ allow: false });
  res.json({ allow: task.autopilot === true });
});

// Create manual (non-Claude) task
app.post('/api/tasks/manual', (req, res) => {
  const { title } = req.body;
  if (!title || !title.trim()) return res.status(400).json({ error: 'title required' });
  const data = loadTasks();
  const task = {
    id: uuidv4(),
    title: title.trim().substring(0, 500),
    tier: 'routine',
    status: 'queued',
    machine: null,
    autopilot: false,
    sessionId: null,
    cwd: null,
    manual: true,
    createdAt: new Date().toISOString(),
    completedAt: null,
  };
  data.tasks.push(task);
  saveTasks(data);
  broadcast('task-created', task);
  res.json(task);
});

// Toggle autopilot / edit task (dashboard)
app.patch('/api/tasks/:id', (req, res) => {
  const data = loadTasks();
  const task = data.tasks.find(t => t.id === req.params.id);
  if (!task) return res.status(404).json({ error: 'not found' });
  if (req.body.autopilot !== undefined) task.autopilot = !!req.body.autopilot;
  if (req.body.tier) task.tier = req.body.tier;
  if (req.body.title) task.title = String(req.body.title).substring(0, 500);
  if (req.body.status && task.manual) {
    const valid = ['queued', 'working', 'done'];
    if (valid.includes(req.body.status)) {
      task.status = req.body.status;
      task.completedAt = req.body.status === 'done' ? new Date().toISOString() : null;
    }
  }
  saveTasks(data);
  broadcast('task-updated', task);
  res.json(task);
});

// Resume task (UserPromptSubmit hook — user sent a new message)
app.post('/api/resume', (req, res) => {
  const { taskId } = req.body;
  if (!taskId) return res.status(400).json({ error: 'taskId required' });
  const data = loadTasks();
  const task = data.tasks.find(t => t.id === taskId);
  if (!task) return res.status(404).json({ error: 'not found' });
  if (task.status !== 'working') {
    task.status = 'working';
    task.completedAt = null;
    saveTasks(data);
    broadcast('task-updated', task);
  }
  res.json({ success: true });
});

// Delete task (SessionEnd hook)
app.delete('/api/tasks/:id', (req, res) => {
  const data = loadTasks();
  data.tasks = data.tasks.filter(t => t.id !== req.params.id);
  saveTasks(data);
  broadcast('task-deleted', { id: req.params.id });
  res.json({ success: true });
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`Executive cloud dashboard running on 127.0.0.1:${PORT}`);
});
