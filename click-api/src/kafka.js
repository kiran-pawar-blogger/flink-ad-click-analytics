'use strict';

const { Kafka, logLevel } = require('kafkajs');

const BROKERS  = (process.env.KAFKA_BROKERS || 'localhost:9092').split(',');
const TOPIC    = process.env.KAFKA_TOPIC   || 'ad-clicks';
const CLIENT_ID = 'click-api';

const kafka = new Kafka({
  clientId: CLIENT_ID,
  brokers: BROKERS,
  logLevel: logLevel.WARN,
  retry: {
    initialRetryTime: 300,
    retries: 10,
  },
});

const producer = kafka.producer({
  allowAutoTopicCreation: true,
  transactionTimeout: 30000,
});

let connected = false;

async function connect() {
  if (!connected) {
    await producer.connect();
    connected = true;
    console.log(`[Kafka] Producer connected to brokers: ${BROKERS.join(', ')}`);
  }
}

async function publishClickEvent(event) {
  await connect();
  await producer.send({
    topic: TOPIC,
    messages: [
      {
        key: `${event.userId}-${event.adId}`,
        value: JSON.stringify(event),
        timestamp: String(event.timestamp),
      },
    ],
  });
}

async function disconnect() {
  if (connected) {
    await producer.disconnect();
    connected = false;
  }
}

// Ensure the topic exists on startup
async function ensureTopicExists() {
  const admin = kafka.admin();
  try {
    await admin.connect();
    const topics = await admin.listTopics();
    if (!topics.includes(TOPIC)) {
      await admin.createTopics({
        topics: [
          {
            topic: TOPIC,
            numPartitions: 3,
            replicationFactor: 1,
          },
        ],
      });
      console.log(`[Kafka] Created topic: ${TOPIC}`);
    } else {
      console.log(`[Kafka] Topic already exists: ${TOPIC}`);
    }
  } catch (err) {
    console.warn('[Kafka] Could not ensure topic exists:', err.message);
  } finally {
    await admin.disconnect();
  }
}

module.exports = { publishClickEvent, disconnect, ensureTopicExists };
