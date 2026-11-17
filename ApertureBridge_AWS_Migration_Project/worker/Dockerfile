FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /srv
RUN useradd --uid 10001 --create-home appuser
COPY worker/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
 && mkdir -p /srv/shared/certs \
 && python -c "import urllib.request; urllib.request.urlretrieve('https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem', '/srv/shared/certs/global-bundle.pem')"
COPY shared /srv/shared
COPY worker /srv/worker
USER appuser
CMD ["python", "-m", "worker.processor"]
