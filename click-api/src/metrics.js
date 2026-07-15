'use strict';

const client = require('prom-client');

// Collect default Node.js metrics (memory, CPU, event loop lag, etc.)
const register = new client.Registry();
client.collectDefaultMetrics({ register });

// Custom counters
const clicksReceived = new client.Counter({
  name: 'click_api_clicks_received_total',
  help: 'Total number of click events received',
  labelNames: ['adId'],
  registers: [register],
});

const clicksPublished = new client.Counter({
  name: 'click_api_clicks_published_total',
  help: 'Total number of click events successfully published to Kafka',
  labelNames: ['adId'],
  registers: [register],
});

const clickErrors = new client.Counter({
  name: 'click_api_errors_total',
  help: 'Total number of errors while processing click events',
  registers: [register],
});

const kafkaPublishDuration = new client.Histogram({
  name: 'click_api_kafka_publish_duration_seconds',
  help: 'Histogram of Kafka publish latency',
  buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1],
  registers: [register],
});

module.exports = {
  register,
  clicksReceived,
  clicksPublished,
  clickErrors,
  kafkaPublishDuration,
};
