package com.hellointerview.flink.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * Represents a raw ad click event consumed from Kafka.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class AdClickEvent {

    private String userId;
    private String adId;
    private String adName;
    private long timestamp;
    private String sessionId;
    private String ipAddress;

    public AdClickEvent() {}

    public AdClickEvent(String userId, String adId, String adName, long timestamp, String sessionId, String ipAddress) {
        this.userId = userId;
        this.adId = adId;
        this.adName = adName;
        this.timestamp = timestamp;
        this.sessionId = sessionId;
        this.ipAddress = ipAddress;
    }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getAdId() { return adId; }
    public void setAdId(String adId) { this.adId = adId; }

    public String getAdName() { return adName; }
    public void setAdName(String adName) { this.adName = adName; }

    public long getTimestamp() { return timestamp; }
    public void setTimestamp(long timestamp) { this.timestamp = timestamp; }

    public String getSessionId() { return sessionId; }
    public void setSessionId(String sessionId) { this.sessionId = sessionId; }

    public String getIpAddress() { return ipAddress; }
    public void setIpAddress(String ipAddress) { this.ipAddress = ipAddress; }

    @Override
    public String toString() {
        return "AdClickEvent{userId='" + userId + "', adId='" + adId + "', adName='" + adName +
               "', timestamp=" + timestamp + "}";
    }
}
