FROM amazoncorretto:17-alpine
WORKDIR /app
RUN mkdir /otel && \
    wget -q -O /otel/opentelemetry-javaagent.jar \
    https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.24.0/opentelemetry-javaagent.jar && \
    echo "5c48cd48f9907f824214e22f14a28375c92613a94b0cf98381997e0a678220ce  /otel/opentelemetry-javaagent.jar" | sha256sum -c
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-javaagent:/otel/opentelemetry-javaagent.jar", "-jar", "app.jar"]
