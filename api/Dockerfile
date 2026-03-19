# ── Build stage ──────────────────────────────────────────────────────────────
FROM dhi.io/python:3.11-alpine3.23-dev AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --target=/install -r requirements.txt

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM dhi.io/python:3.11-alpine3.23

WORKDIR /app

COPY --from=builder /install /app/lib
COPY app.py .

ENV PYTHONPATH=/app/lib

EXPOSE 5000

CMD ["python", "app.py"]
