# Image durcie : JRE seule, base Alpine reduite, utilisateur non-root
FROM eclipse-temurin:17-jre-alpine

RUN addgroup -S app && adduser -S app -G app
WORKDIR /app

# Le .jar est produit par le stage Maven du pipeline (target/achat.jar)
COPY --chown=app:app target/achat.jar app.jar
USER app

EXPOSE 8089
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget -qO- http://localhost:8089/SpringMVC/actuator/health > /dev/null || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
