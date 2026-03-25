FROM python:3.12-alpine

WORKDIR /app

COPY planner/pyproject.toml .
COPY planner/src/ src/

RUN pip install --no-cache-dir .

CMD ["planner"]
