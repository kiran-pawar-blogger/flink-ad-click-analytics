# ---- Build stage ----
FROM maven:3.9.6-eclipse-temurin-11 AS build
WORKDIR /app
COPY pom.xml .
# Download dependencies first (layer cache)
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn clean package -DskipTests -q

# ---- Runtime stage ----
FROM flink:1.18.1-java11
WORKDIR /opt/flink/usrlib
COPY --from=build /app/target/flink-ad-clicks-1.0.0.jar flink-ad-clicks.jar

# Entry point is provided by Flink's docker image via the COMMAND in k8s spec
