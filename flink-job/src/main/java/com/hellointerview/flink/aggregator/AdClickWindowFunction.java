package com.hellointerview.flink.aggregator;

import com.hellointerview.flink.model.AdClickAggregate;
import org.apache.flink.streaming.api.functions.windowing.WindowFunction;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import org.apache.flink.util.Collector;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

/**
 * Enriches aggregated results with window start/end timestamps.
 */
public class AdClickWindowFunction implements WindowFunction<AdClickAggregate, AdClickAggregate, String, TimeWindow> {

    private static final DateTimeFormatter FMT = DateTimeFormatter
            .ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'")
            .withZone(ZoneId.of("UTC"));

    @Override
    public void apply(String key, TimeWindow window, Iterable<AdClickAggregate> input, Collector<AdClickAggregate> out) {
        AdClickAggregate agg = input.iterator().next();

        String windowStart = FMT.format(Instant.ofEpochMilli(window.getStart()));
        String windowEnd   = FMT.format(Instant.ofEpochMilli(window.getEnd()));

        agg.setWindowStart(windowStart);
        agg.setWindowEnd(windowEnd);

        out.collect(agg);
    }
}
