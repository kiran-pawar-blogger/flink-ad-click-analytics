package com.hellointerview.flink.deserializer;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.hellointerview.flink.model.AdClickEvent;
import org.apache.flink.api.common.serialization.DeserializationSchema;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Deserializes JSON byte arrays from Kafka into AdClickEvent objects.
 */
public class AdClickEventDeserializer implements DeserializationSchema<AdClickEvent> {

    private static final Logger LOG = LoggerFactory.getLogger(AdClickEventDeserializer.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Override
    public AdClickEvent deserialize(byte[] message) {
        try {
            return MAPPER.readValue(message, AdClickEvent.class);
        } catch (Exception e) {
            LOG.error("Failed to deserialize message: {}", new String(message), e);
            return null;
        }
    }

    @Override
    public boolean isEndOfStream(AdClickEvent nextElement) {
        return false;
    }

    @Override
    public TypeInformation<AdClickEvent> getProducedType() {
        return TypeInformation.of(AdClickEvent.class);
    }
}
