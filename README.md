# Ad Click Analytics — Apache Flink + Kafka + MongoDB on Kubernetes

A full end-to-end real-time ad click analytics platform demonstrating:

- **Apache Flink** streaming aggregation
- **Apache Kafka** event bus
- **MongoDB** as the data sink
- **Kubernetes (kind)** local cluster
- **Prometheus + Grafana** observability

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Kubernetes (kind)                            │
│                                                                     │
│  ┌──────────┐   click    ┌───────────┐   Kafka    ┌─────────────┐  │
│  │  Ad UI   │──────────▶│ Click API │──────────▶│    Kafka     │  │
│  │ (Node.js)│  POST/api  │ (Node.js) │  ad-clicks │ (Confluent)  │  │
│  └──────────┘            └───────────┘            └──────┬──────┘  │
│       ▲ ingress                                           │         │
│       │                                                   ▼         │
│  ┌────────────┐                                  ┌─────────────────┐│
│  │ Report UI  │◀── MongoDB reads ──────────────  │  Apache Flink   ││
│  │ (Node.js)  │                                  │  (JobManager +  ││
│  └────────────┘                                  │  2×TaskManager) ││
│       ▲ ingress                                  └───────┬─────────┘│
│                                                          │ upsert    │
│  ┌────────────────────────────────┐              ┌───────▼─────────┐│
│  │ Prometheus + Grafana           │              │    MongoDB      ││
│  │ (metrics scraping + dashboards)│              │ (click_aggregates│
│  └────────────────────────────────┘              └─────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

**Data Flow:**
1. User clicks an ad banner in the Ad UI (browser)
2. Browser sends `POST /api/clicks` to Click API via NGINX Ingress
3. Click API publishes the event to Kafka topic `ad-clicks`
4. Apache Flink consumes from Kafka, keys by `userId|adId`, and aggregates in 60-second tumbling windows
5. Aggregated results are upserted into MongoDB collection `click_aggregates`
6. Report UI queries MongoDB and renders tables/charts, auto-refreshing every 10s

---

## Project Layout

```
apache-flink/
├── deploy.sh                  # 🚀 One-shot deploy script (bash / Mac / Linux / WSL)
├── deploy.ps1                 # 🚀 One-shot deploy script (PowerShell / Windows)
├── teardown.sh                # 🧹 Destroy everything (bash)
├── teardown.ps1               # 🧹 Destroy everything (PowerShell)
│
├── flink-job/                 # Java/Maven — Flink streaming job
│   ├── pom.xml
│   ├── Dockerfile
│   └── src/main/java/com/hellointerview/flink/
│       ├── AdClickAggregationJob.java      # Main entry point
│       ├── model/
│       │   ├── AdClickEvent.java           # Kafka message DTO
│       │   └── AdClickAggregate.java       # Aggregated result DTO
│       ├── deserializer/
│       │   └── AdClickEventDeserializer.java
│       ├── aggregator/
│       │   ├── AdClickAggregateFunction.java
│       │   └── AdClickWindowFunction.java
│       └── sink/
│           └── MongoAdClickSink.java       # Custom MongoDB upsert sink
│
├── click-api/                 # Node.js — Kafka producer REST API
│   ├── package.json
│   ├── Dockerfile
│   └── src/
│       ├── index.js           # Express server + /api/clicks endpoint
│       ├── kafka.js           # KafkaJS producer
│       └── metrics.js         # Prometheus metrics
│
├── ad-ui/                     # Node.js — Demo ads website
│   ├── package.json
│   ├── Dockerfile
│   ├── src/index.js
│   └── public/index.html      # 6 clickable ad banners
│
├── report-ui/                 # Node.js — Analytics dashboard
│   ├── package.json
│   ├── Dockerfile
│   ├── src/
│   │   ├── index.js           # Express + MongoDB API routes
│   │   └── db.js              # MongoDB aggregation queries
│   └── public/index.html      # Multi-tab analytics dashboard
│
└── k8s/                       # Kubernetes manifests
    ├── namespace.yaml
    ├── zookeeper.yaml
    ├── kafka.yaml
    ├── mongodb.yaml
    ├── flink.yaml              # JobManager + 2×TaskManager + ConfigMap
    ├── click-api.yaml
    ├── ad-ui.yaml
    ├── report-ui.yaml
    ├── ingress.yaml
    └── monitoring/
        ├── prometheus-configmap.yaml
        ├── prometheus.yaml
        ├── grafana.yaml        # Pre-provisioned dashboard + datasource
        └── ingress-monitoring.yaml
```

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Docker Desktop | 4.x+ | Must be running |
| kind | 0.20+ | `brew install kind` / `choco install kind` |
| kubectl | 1.28+ | Usually bundled with Docker Desktop |
| Maven | 3.9+ | To build the Flink JAR |
| Node.js | 18+ | To install npm deps during build |

---

## Quick Start

**Windows — PowerShell** (recommended on Windows):
```powershell
cd apache-flink

# If you haven't relaxed the execution policy yet (one-time):
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

.\deploy.ps1
```

Optional flags:
```powershell
# Skip rebuilding images (reuse what's already in Docker)
.\deploy.ps1 -SkipBuild

# Skip cluster creation (re-deploy to an existing cluster)
.\deploy.ps1 -SkipCluster

# Both — just re-apply manifests
.\deploy.ps1 -SkipBuild -SkipCluster

# Use a different cluster name
.\deploy.ps1 -ClusterName my-test

# Change the Flink window size (seconds)
.\deploy.ps1 -WindowSeconds 30
```

**Mac / Linux / WSL — bash**:
```bash
cd apache-flink
chmod +x deploy.sh
./deploy.sh
```

---

## Access URLs

| Service | URL |
|---------|-----|
| **Ad Demo UI** | http://localhost/ads |
| **Report UI** | http://localhost/reports |
| **Grafana** | http://localhost/grafana (admin / admin123) |
| **Prometheus** | http://localhost/prometheus |
| **Flink Web UI** | http://localhost/flink |
| Click API (internal) | http://localhost/api/clicks |

---

## How to Test

1. Open **http://localhost/ads** — click several ad banners as different users (switch from the dropdown)
2. Flink aggregates clicks in **60-second tumbling windows** — wait ~60 seconds
3. Open **http://localhost/reports** — switch tabs to see:
   - **Overview** — total clicks per ad + share bar
   - **Clicks per Ad** — sorted leaderboard
   - **Clicks per User** — who clicked the most
   - **User × Ad Matrix** — full cross-reference table
   - **Raw Windows** — Flink window records straight from MongoDB

---

## Flink Job Details

| Parameter | Default | Override via |
|-----------|---------|-------------|
| Kafka brokers | `kafka:9092` | `KAFKA_BROKERS` env var |
| Kafka topic | `ad-clicks` | `KAFKA_TOPIC` env var |
| Consumer group | `flink-ad-click-group` | `KAFKA_GROUP` env var |
| MongoDB URI | `mongodb://mongodb:27017` | `MONGO_URI` env var |
| Window size | 60 seconds | `WINDOW_SECONDS` env var |
| Checkpointing | every 30s | hardcoded in job |

The Flink job runs in **standalone session mode**: 1 JobManager + 2 TaskManagers (2 slots each = 4 total slots).

---

## Monitoring

Grafana is pre-provisioned with an **"Ad Analytics — System Health"** dashboard showing:

- Total click events received & published to Kafka
- Click API error rate
- Kafka publish latency (p99)
- Clicks per ad per minute (time series)
- Node.js heap memory and event loop lag
- MongoDB connection count

Prometheus scrapes all services via Kubernetes pod annotations:
```yaml
prometheus.io/scrape: "true"
prometheus.io/port:   "3001"
prometheus.io/path:   "/metrics"
```

---

## Teardown

**PowerShell:**
```powershell
.\teardown.ps1

# Keep the Docker images (faster re-deploy later)
.\teardown.ps1 -KeepImages

# Target a differently-named cluster
.\teardown.ps1 -ClusterName my-test
```

**Bash:**
```bash
bash teardown.sh
```

Both scripts delete the kind cluster and remove the four local Docker images.
