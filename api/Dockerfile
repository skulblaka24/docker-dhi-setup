# Build stage #################################################################
FROM dhi.io/python:3.11-alpine3.23-dev AS builder

WORKDIR /app

# Copy requirements first for better layer caching
COPY requirements.txt .

# Install dependencies into /install so the runtime stage gets only what it needs
RUN pip install --no-cache-dir --target=/install -r requirements.txt

# Runtime stage ################################################################
FROM dhi.io/python:3.11-alpine3.23

WORKDIR /app

# Copy application code
COPY --from=builder /install /app/lib
COPY app.py .

# Change the python folder path
ENV PYTHONPATH=/app/lib

# Expose port
EXPOSE 5000

# Run the application
CMD ["python", "app.py"]
