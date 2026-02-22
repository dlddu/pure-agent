FROM alpine:3.20
RUN apk add --no-cache bash coreutils
WORKDIR /app
COPY entrypoint.sh ./
RUN chmod +x entrypoint.sh
CMD ["/app/entrypoint.sh"]
