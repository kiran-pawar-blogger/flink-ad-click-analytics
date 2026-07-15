package com.hellointerview.flink.model;

/**
 * Aggregated click count per userId + adId combination, stored in MongoDB.
 */
public class AdClickAggregate {

    private String userId;
    private String adId;
    private String adName;
    private long clickCount;
    private long lastClickTimestamp;
    private long firstClickTimestamp;
    private String windowStart;
    private String windowEnd;

    public AdClickAggregate() {}

    public AdClickAggregate(String userId, String adId, String adName, long clickCount,
                             long lastClickTimestamp, long firstClickTimestamp,
                             String windowStart, String windowEnd) {
        this.userId = userId;
        this.adId = adId;
        this.adName = adName;
        this.clickCount = clickCount;
        this.lastClickTimestamp = lastClickTimestamp;
        this.firstClickTimestamp = firstClickTimestamp;
        this.windowStart = windowStart;
        this.windowEnd = windowEnd;
    }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getAdId() { return adId; }
    public void setAdId(String adId) { this.adId = adId; }

    public String getAdName() { return adName; }
    public void setAdName(String adName) { this.adName = adName; }

    public long getClickCount() { return clickCount; }
    public void setClickCount(long clickCount) { this.clickCount = clickCount; }

    public long getLastClickTimestamp() { return lastClickTimestamp; }
    public void setLastClickTimestamp(long lastClickTimestamp) { this.lastClickTimestamp = lastClickTimestamp; }

    public long getFirstClickTimestamp() { return firstClickTimestamp; }
    public void setFirstClickTimestamp(long firstClickTimestamp) { this.firstClickTimestamp = firstClickTimestamp; }

    public String getWindowStart() { return windowStart; }
    public void setWindowStart(String windowStart) { this.windowStart = windowStart; }

    public String getWindowEnd() { return windowEnd; }
    public void setWindowEnd(String windowEnd) { this.windowEnd = windowEnd; }

    @Override
    public String toString() {
        return "AdClickAggregate{userId='" + userId + "', adId='" + adId +
               "', clickCount=" + clickCount + "}";
    }
}
