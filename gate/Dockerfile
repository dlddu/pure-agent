FROM python:3.12-alpine

WORKDIR /app

COPY gate/pyproject.toml .
COPY gate/src/ src/

RUN pip install --no-cache-dir .

CMD ["gate"]
