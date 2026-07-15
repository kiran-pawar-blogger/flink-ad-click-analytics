package com.hellointerview.flink.aggregator;

import com.hellointerview.flink.model.AdClickAggregate;
import com.hellointerview.flink.model.AdClickEvent;
import org.apache.flink.api.common.functions.AggregateFunction;

/**
 * Aggregates AdClickEvent records into AdClickAggregate by counting clicks.
 */
public class AdClickAggregateFunction implements AggregateFunction<AdClickEvent, AdClickAggregate, AdClickAggregate> {

    @Override
    public AdClickAggregate createAccumulator() {
        return new AdClickAggregate(null, null, null, 0L, 0L, Long.MAX_VALUE, null, null);
    }

    @Override
    public AdClickAggregate add(AdClickEvent event, AdClickAggregate accumulator) {
        long ts = event.getTimestamp();
        return new AdClickAggregate(
            event.getUserId(),
            event.getAdId(),
            event.getAdName(),
            accumulator.getClickCount() + 1,
            Math.max(accumulator.getLastClickTimestamp(), ts),
            Math.min(accumulator.getFirstClickTimestamp(), ts),
            accumulator.getWindowStart(),
            accumulator.getWindowEnd()
        );
    }

    @Override
    public AdClickAggregate getResult(AdClickAggregate accumulator) {
        return accumulator;
    }

    @Override
    public AdClickAggregate merge(AdClickAggregate a, AdClickAggregate b) {
        return new AdClickAggregate(
            a.getUserId() != null ? a.getUserId() : b.getUserId(),
            a.getAdId() != null ? a.getAdId() : b.getAdId(),
            a.getAdName() != null ? a.getAdName() : b.getAdName(),
            a.getClickCount() + b.getClickCount(),
            Math.max(a.getLastClickTimestamp(), b.getLastClickTimestamp()),
            Math.min(a.getFirstClickTimestamp(), b.getFirstClickTimestamp()),
            a.getWindowStart(),
            a.getWindowEnd()
        );
    }
}
