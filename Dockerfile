# Production Dockerfile for deploying OmniRoute on Render (Docker SDK)
FROM diegosouzapw/omniroute:latest

USER root

# Install Python 3, SQLite tools, ca-certificates, and curl
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-setuptools \
    sqlite3 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir --break-system-packages --ignore-installed huggingface_hub

ENV PORT=20128
ENV HOSTNAME=0.0.0.0
ENV DATA_DIR=/app/data
ENV NODE_ENV=production

WORKDIR /app

# Copy automated sync scripts and entrypoint
COPY hf_sync.py /app/hf_sync.py
COPY pinger.py /app/pinger.py
COPY entrypoint.sh /app/entrypoint.sh

# Set ownership and executable permissions
RUN chmod +x /app/entrypoint.sh /app/hf_sync.py /app/pinger.py \
    && mkdir -p /app/data \
    && chown -R node:node /app/data /app/hf_sync.py /app/entrypoint.sh /app/pinger.py

USER node

EXPOSE 20128

ENTRYPOINT ["/app/entrypoint.sh"]
