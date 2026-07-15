'use strict';

const express = require('express');
const path    = require('path');
const morgan  = require('morgan');
const helmet  = require('helmet');
const cors    = require('cors');
const client  = require('prom-client');

const { getClicksPerAd, getClicksPerUser, getDetailRecords, getClicksPerUserPerAd } = require('./db');

const app  = express();
const PORT = process.env.PORT || 3002;

// Prometheus
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const apiRequests = new client.Counter({
  name: 'report_ui_api_requests_total',
  help: 'Total API requests to report-ui',
  labelNames: ['endpoint'],
  registers: [register],
});

// Middleware
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors());
app.use(morgan('combined'));
app.use(express.static(path.join(__dirname, '../public')));

// ── API routes ────────────────────────────────────────────────────────────────
// Each endpoint is registered on both the full path (/api/reports/...)
// and the ingress-rewritten path (/reports/...) since NGINX strips /api.

app.get(['/api/reports/per-ad', '/reports/per-ad'], async (_req, res) => {
  apiRequests.inc({ endpoint: 'per-ad' });
  try {
    const data = await getClicksPerAd();
    res.json(data);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

app.get(['/api/reports/per-user', '/reports/per-user'], async (_req, res) => {
  apiRequests.inc({ endpoint: 'per-user' });
  try {
    const data = await getClicksPerUser();
    res.json(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get(['/api/reports/per-user-per-ad', '/reports/per-user-per-ad'], async (_req, res) => {
  apiRequests.inc({ endpoint: 'per-user-per-ad' });
  try {
    const data = await getClicksPerUserPerAd();
    res.json(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get(['/api/reports/detail', '/reports/detail'], async (req, res) => {
  apiRequests.inc({ endpoint: 'detail' });
  try {
    const limit = Math.min(parseInt(req.query.limit || '200'), 1000);
    const data  = await getDetailRecords(limit);
    res.json(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/health',  (_req, res) => res.json({ status: 'ok' }));
app.get('/ready',   (_req, res) => res.json({ status: 'ready' }));
app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Serve SPA for all other routes
app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

app.listen(PORT, () => {
  console.log(`[Report UI] Listening on port ${PORT}`);
});
