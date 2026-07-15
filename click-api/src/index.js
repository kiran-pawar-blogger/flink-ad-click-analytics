'use strict';

const express     = require('express');
const cors        = require('cors');
const helmet      = require('helmet');
const morgan      = require('morgan');
const rateLimit   = require('express-rate-limit');
const { v4: uuidv4 } = require('uuid');

const { publishClickEvent, disconnect, ensureTopicExists } = require('./kafka');
const { register, clicksReceived, clicksPublished, clickErrors, kafkaPublishDuration } = require('./metrics');

const app  = express();
const PORT = process.env.PORT || 3001;

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(cors());
app.use(express.json({ limit: '10kb' }));
app.use(morgan('combined'));

app.use(rateLimit({
  windowMs: 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
}));

// ── Click handler ─────────────────────────────────────────────────────────────
// Registered on both paths:
//   POST /clicks     — NGINX ingress rewrites /api/clicks -> /clicks
//   POST /api/clicks — direct access (health checks, tests, port-forward)
async function handleClick(req, res) {
  const { userId, adId, adName, sessionId } = req.body || {};

  if (!userId || !adId) {
    return res.status(400).json({ error: 'userId and adId are required' });
  }

  const event = {
    eventId:   uuidv4(),
    userId:    String(userId),
    adId:      String(adId),
    adName:    adName    || `Ad ${adId}`,
    sessionId: sessionId || uuidv4(),
    ipAddress: req.ip,
    timestamp: Date.now(),
  };

  clicksReceived.inc({ adId: event.adId });

  const end = kafkaPublishDuration.startTimer();
  try {
    await publishClickEvent(event);
    end();
    clicksPublished.inc({ adId: event.adId });
    return res.status(202).json({ status: 'accepted', eventId: event.eventId });
  } catch (err) {
    end();
    clickErrors.inc();
    console.error('[API] Failed to publish click event:', err.message);
    return res.status(500).json({ error: 'Failed to publish event' });
  }
}

app.post('/clicks',     handleClick);
app.post('/api/clicks', handleClick);

// ── Probes & metrics ──────────────────────────────────────────────────────────
app.get('/health',  (_req, res) => res.json({ status: 'ok', ts: Date.now() }));
app.get('/ready',   (_req, res) => res.json({ status: 'ready' }));
app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// ── Bootstrap ─────────────────────────────────────────────────────────────────
async function start() {
  try {
    await ensureTopicExists();
  } catch (err) {
    console.warn('[App] Could not ensure Kafka topic (will retry on first publish):', err.message);
  }
  app.listen(PORT, () => console.log(`[App] Click API listening on port ${PORT}`));
}

process.on('SIGTERM', async () => {
  console.log('[App] SIGTERM received, shutting down...');
  await disconnect();
  process.exit(0);
});

start();
