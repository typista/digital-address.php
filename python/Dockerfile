FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential curl && \
    rm -rf /var/lib/apt/lists/*

COPY python/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY shared /app/shared
COPY python /app/python

EXPOSE 8003

WORKDIR /app/python

CMD ["python", "index.py"]
