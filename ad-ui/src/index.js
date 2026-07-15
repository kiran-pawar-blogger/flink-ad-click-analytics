'use strict';

const express = require('express');
const path    = require('path');
const morgan  = require('morgan');
const helmet  = require('helmet');

const app  = express();
const PORT = process.env.PORT || 3000;

app.use(morgan('combined'));
app.use(helmet({
  contentSecurityPolicy: false, // relaxed for demo inline scripts
}));
app.use(express.static(path.join(__dirname, '../public')));

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.listen(PORT, () => {
  console.log(`[Ad UI] Listening on port ${PORT}`);
});
