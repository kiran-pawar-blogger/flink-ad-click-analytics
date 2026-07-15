'use strict';

const { MongoClient } = require('mongodb');

const MONGO_URI        = process.env.MONGO_URI        || 'mongodb://localhost:27017';
const MONGO_DATABASE   = process.env.MONGO_DATABASE   || 'adclicks';
const MONGO_COLLECTION = process.env.MONGO_COLLECTION || 'click_aggregates';

let client;
let db;

async function connect() {
  if (!client) {
    client = new MongoClient(MONGO_URI, {
      serverSelectionTimeoutMS: 5000,
      connectTimeoutMS: 10000,
    });
    await client.connect();
    db = client.db(MONGO_DATABASE);
    console.log(`[DB] Connected to MongoDB: ${MONGO_URI} / ${MONGO_DATABASE}`);
  }
  return db;
}

async function getCollection() {
  const database = await connect();
  return database.collection(MONGO_COLLECTION);
}

/**
 * Returns total clicks per ad across all users.
 */
async function getClicksPerAd() {
  const col = await getCollection();
  return col.aggregate([
    {
      $group: {
        _id:        '$adId',
        adName:     { $first: '$adName' },
        totalClicks:{ $sum: '$clickCount' },
        uniqueUsers:{ $addToSet: '$userId' },
      }
    },
    { $addFields: { uniqueUserCount: { $size: '$uniqueUsers' } } },
    { $project: { uniqueUsers: 0 } },
    { $sort: { totalClicks: -1 } },
  ]).toArray();
}

/**
 * Returns total clicks per user across all ads.
 */
async function getClicksPerUser() {
  const col = await getCollection();
  return col.aggregate([
    {
      $group: {
        _id:        '$userId',
        totalClicks:{ $sum: '$clickCount' },
        uniqueAds:  { $addToSet: '$adId' },
      }
    },
    { $addFields: { uniqueAdCount: { $size: '$uniqueAds' } } },
    { $project: { uniqueAds: 0 } },
    { $sort: { totalClicks: -1 } },
  ]).toArray();
}

/**
 * Returns the raw aggregation records (userId + adId + window) most recent first.
 */
async function getDetailRecords(limit = 200) {
  const col = await getCollection();
  return col.find({}, { projection: { _id: 0 } })
    .sort({ lastClickTimestamp: -1 })
    .limit(limit)
    .toArray();
}

/**
 * Returns clicks per user per ad (the main report).
 */
async function getClicksPerUserPerAd() {
  const col = await getCollection();
  return col.aggregate([
    {
      $group: {
        _id:        { userId: '$userId', adId: '$adId' },
        adName:     { $first: '$adName' },
        totalClicks:{ $sum: '$clickCount' },
        lastClick:  { $max: '$lastClickTimestamp' },
      }
    },
    {
      $project: {
        _id:        0,
        userId:     '$_id.userId',
        adId:       '$_id.adId',
        adName:     1,
        totalClicks:1,
        lastClick:  1,
      }
    },
    { $sort: { userId: 1, totalClicks: -1 } },
  ]).toArray();
}

module.exports = { getClicksPerAd, getClicksPerUser, getDetailRecords, getClicksPerUserPerAd };
