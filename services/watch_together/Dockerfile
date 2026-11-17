FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get
COPY lib ./lib
COPY bin ./bin
RUN dart compile exe bin/server.dart -o /watch-server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /watch-server /watch-server
ENV HOST=0.0.0.0 PORT=18444
EXPOSE 18444
USER 65534:65534
ENTRYPOINT ["/watch-server"]
