package com.hellointerview.flink;

import com.hellointerview.flink.aggregator.AdClickAggregateFunction;
import com.hellointerview.flink.aggregator.AdClickWindowFunction;
import com.hellointerview.flink.deserializer.AdClickEventDeserializer;
import com.hellointerview.flink.model.AdClickAggregate;
import com.hellointerview.flink.model.AdClickEvent;
import com.hellointerview.flink.sink.MongoAdClickSink;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.windowing.assigners.TumblingProcessingTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;

/**
 * Main Flink streaming job.
 *
 * Pipeline:
 *   Kafka topic "ad-clicks"
 *     → filter nulls
 *     → keyBy(userId + "|" + adId)
 *     → tumbling window (60 s)
 *     → aggregate click count
 *     → MongoDB "adclicks" collection (upsert)
 */
public class AdClickAggregationJob {

    private static final Logger LOG = LoggerFactory.getLogger(AdClickAggregationJob.class);

    public static void main(String[] args) throws Exception {

        // Read config from environment (injected via k8s ConfigMap / env vars)
        String kafkaBrokers  = getEnv("KAFKA_BROKERS",  "kafka:9092");
        String kafkaTopic    = getEnv("KAFKA_TOPIC",    "ad-clicks");
        String kafkaGroup    = getEnv("KAFKA_GROUP",    "flink-ad-click-group");
        String mongoUri      = getEnv("MONGO_URI",      "mongodb://mongodb:27017");
        String mongoDatabase = getEnv("MONGO_DATABASE", "adclicks");
        String mongoCollection = getEnv("MONGO_COLLECTION", "click_aggregates");
        int    windowSeconds = Integer.parseInt(getEnv("WINDOW_SECONDS", "60"));

        LOG.info("Starting AdClickAggregationJob");
        LOG.info("  Kafka: {} / topic: {} / group: {}", kafkaBrokers, kafkaTopic, kafkaGroup);
        LOG.info("  MongoDB: {} / db: {} / collection: {}", mongoUri, mongoDatabase, mongoCollection);
        LOG.info("  Window: {} seconds", windowSeconds);

        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        // Enable checkpointing every 30 seconds for fault tolerance
        env.enableCheckpointing(30_000);

        // --- Kafka Source ---
        KafkaSource<AdClickEvent> kafkaSource = KafkaSource.<AdClickEvent>builder()
                .setBootstrapServers(kafkaBrokers)
                .setTopics(kafkaTopic)
                .setGroupId(kafkaGroup)
                .setStartingOffsets(OffsetsInitializer.earliest())
                .setValueOnlyDeserializer(new AdClickEventDeserializer())
                .build();

        DataStream<AdClickEvent> clickStream = env
                .fromSource(kafkaSource, WatermarkStrategy.forBoundedOutOfOrderness(Duration.ofSeconds(5)), "Kafka Ad Clicks")
                .filter(event -> event != null && event.getUserId() != null && event.getAdId() != null)
                .name("Filter Valid Events");

        // --- Aggregate: keyBy(userId + adId), tumbling window ---
        DataStream<AdClickAggregate> aggregated = clickStream
                .keyBy(event -> event.getUserId() + "|" + event.getAdId())
                .window(TumblingProcessingTimeWindows.of(Time.seconds(windowSeconds)))
                .aggregate(new AdClickAggregateFunction(), new AdClickWindowFunction())
                .name("Aggregate Click Counts");

        // --- MongoDB Sink ---
        aggregated
                .addSink(new MongoAdClickSink(mongoUri, mongoDatabase, mongoCollection))
                .name("MongoDB Sink");

        env.execute("Ad Click Aggregation Job");
    }

    private static String getEnv(String key, String defaultValue) {
        String val = System.getenv(key);
        return (val != null && !val.isEmpty()) ? val : defaultValue;
    }
}
