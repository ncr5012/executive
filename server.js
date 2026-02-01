const express = require('express');
const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = 7777;
const DATA_DIR = path.join(__dirname, 'data');
const TASKS_FILE = path.join(DATA_DIR, 'tasks.json');
const KEY_FILE = path.join(DATA_DIR, 'key.txt');

if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
if (!fs.existsSync(TASKS_FILE)) fs.writeFileSync(TASKS_FILE, JSON.stringify({ tasks: [] }));

let API_KEY = '';
if (fs.existsSync(KEY_FILE)) {
  API_KEY = fs.readFileSync(KEY_FILE, 'utf8').trim();
}

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
app.use(express.static(path.join(__dirname, 'public')));

// Auth: localhost gets full access, remote needs API key
app.use('/api', (req, res, next) => {
  const ip = req.ip || req.connection.remoteAddress;
  const isLocal = ip === '127.0.0.1' || ip === '::1' || ip === '::ffff:127.0.0.1';
  if (isLocal) return next();
  const key = req.headers['x-api-key'];
  if (API_KEY && key !== API_KEY) return res.status(401).json({ error: 'unauthorized' });
  next();
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

// Toggle autopilot / edit task (dashboard)
app.patch('/api/tasks/:id', (req, res) => {
  const data = loadTasks();
  const task = data.tasks.find(t => t.id === req.params.id);
  if (!task) return res.status(404).json({ error: 'not found' });
  if (req.body.autopilot !== undefined) task.autopilot = !!req.body.autopilot;
  if (req.body.tier) task.tier = req.body.tier;
  if (req.body.title) task.title = req.body.title;
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

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Executive dashboard running at http://localhost:${PORT}`);
});
