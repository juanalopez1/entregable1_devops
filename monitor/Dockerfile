# ---------- Etapa 1: build ----------
# Compila el .jar con Maven (esta etapa no llega a la imagen final)
FROM maven:3.9.9-eclipse-temurin-21 AS build

WORKDIR /app

# Primero solo el pom.xml: si no cambian las dependencias, Docker reusa esta capa
COPY pom.xml .
RUN mvn -q -B dependency:go-offline

# Después el código fuente
COPY src ./src
RUN mvn -q -B -DskipTests package

# ---------- Etapa 2: runtime ----------
# Solo el JRE sobre Alpine (sin compilador ni Maven) + el .jar
FROM eclipse-temurin:21.0.13_9-jre-alpine-3.23

# Usuario y grupo sin privilegios, con UID/GID numérico (sintaxis de Alpine)
RUN addgroup -g 10001 appuser \
    && adduser -u 10001 -G appuser -H -D -s /sbin/nologin appuser

WORKDIR /app

COPY --from=build --chown=appuser:appuser /app/target/monitor.jar app.jar

# La JVM usa como máximo el 75 % de la memoria que le da Kubernetes (limits)
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"

EXPOSE 8080

USER 10001:10001

ENTRYPOINT ["java", "-jar", "app.jar"]