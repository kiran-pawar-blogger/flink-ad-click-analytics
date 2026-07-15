package com.hellointerview.flink.sink;

import com.hellointerview.flink.model.AdClickAggregate;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import com.mongodb.client.MongoCollection;
import com.mongodb.client.model.Filters;
import com.mongodb.client.model.ReplaceOptions;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.functions.sink.RichSinkFunction;
import org.bson.Document;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Custom MongoDB sink that upserts aggregated click data.
 * Uses userId + adId + windowStart as the upsert key so re-runs are idempotent.
 */
public class MongoAdClickSink extends RichSinkFunction<AdClickAggregate> {

    private static final Logger LOG = LoggerFactory.getLogger(MongoAdClickSink.class);

    private final String mongoUri;
    private final String database;
    private final String collection;

    private transient MongoClient mongoClient;
    private transient MongoCollection<Document> mongoCollection;

    public MongoAdClickSink(String mongoUri, String database, String collection) {
        this.mongoUri   = mongoUri;
        this.database   = database;
        this.collection = collection;
    }

    @Override
    public void open(Configuration parameters) {
        mongoClient     = MongoClients.create(mongoUri);
        mongoCollection = mongoClient.getDatabase(database).getCollection(collection);
        LOG.info("Connected to MongoDB at {}", mongoUri);
    }

    @Override
    public void invoke(AdClickAggregate agg, Context context) {
        try {
            Document doc = new Document()
                    .append("userId",              agg.getUserId())
                    .append("adId",                agg.getAdId())
                    .append("adName",              agg.getAdName())
                    .append("clickCount",          agg.getClickCount())
                    .append("firstClickTimestamp", agg.getFirstClickTimestamp())
                    .append("lastClickTimestamp",  agg.getLastClickTimestamp())
                    .append("windowStart",         agg.getWindowStart())
                    .append("windowEnd",           agg.getWindowEnd());

            // Upsert so that running the job multiple times stays idempotent
            mongoCollection.replaceOne(
                Filters.and(
                    Filters.eq("userId",      agg.getUserId()),
                    Filters.eq("adId",        agg.getAdId()),
                    Filters.eq("windowStart", agg.getWindowStart())
                ),
                doc,
                new ReplaceOptions().upsert(true)
            );

            LOG.debug("Upserted aggregate: {}", agg);
        } catch (Exception e) {
            LOG.error("Failed to write aggregate to MongoDB: {}", agg, e);
        }
    }

    @Override
    public void close() {
        if (mongoClient != null) {
            mongoClient.close();
        }
    }
}
