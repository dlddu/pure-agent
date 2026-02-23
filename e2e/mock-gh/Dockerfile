FROM alpine:3.20
RUN apk add --no-cache bash coreutils
COPY gh /usr/local/bin/gh
RUN chmod +x /usr/local/bin/gh
ENTRYPOINT ["gh"]
