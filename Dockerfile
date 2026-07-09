FROM python:3.9-slim

WORKDIR /app

ARG VCS_REF=unknown

LABEL org.opencontainers.image.title="calculator-app" \
      org.opencontainers.image.revision="${VCS_REF}"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

COPY requirements.txt .

RUN python -m pip install \
        --no-cache-dir \
        --upgrade pip \
    && python -m pip install \
        --no-cache-dir \
        -r requirements.txt \
        pytest

COPY api.py .
COPY calculator_app.py .
COPY calculator_logic.py .
COPY tests ./tests

RUN useradd \
        --create-home \
        --shell /usr/sbin/nologin \
        appuser \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 5000

HEALTHCHECK \
    --interval=10s \
    --timeout=3s \
    --retries=6 \
    --start-period=10s \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=2)" || exit 1

CMD ["python", "-m", "flask", "--app", "api:app", "run", "--host=0.0.0.0", "--port=5000"]
