FROM alpine:3.20
RUN apk add --no-cache bash coreutils
WORKDIR /app
COPY e2e/mock-agent/entrypoint.sh ./
RUN chmod +x entrypoint.sh
CMD ["/app/entrypoint.sh"]
