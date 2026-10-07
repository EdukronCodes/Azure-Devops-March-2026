FROM python:3.12.15-alpine3.24
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 DATABASE_PATH=/data/shop.db
WORKDIR /app
RUN apk upgrade --no-cache \
    && addgroup -S -g 10001 volt && adduser -S -D -H -u 10001 -G volt volt \
    && mkdir /data && chown volt:volt /data
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chown=10001:10001 app.py catalog.py ./
COPY --chown=10001:10001 static ./static
COPY --chown=10001:10001 templates ./templates
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=3)"
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--threads", "1", "--timeout", "60", "app:app"]
