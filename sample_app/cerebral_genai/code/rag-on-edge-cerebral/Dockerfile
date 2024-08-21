FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt /app/

RUN pip install --no-cache-dir -r requirements.txt

COPY . /app

ENV AZURE_OPENAI_API_KEY=your_azure_openai_api_key \
    CHATGPT_MODEL=gpt-35-turbo \
    AZURE_OPENAI_ENDPOINT=https://hmidemo-openai.openai.azure.com \
    OPENAI_API_VERSION=2024-03-01-preview \
    INFLUXDB_URL=http://10.0.0.4:8086 \
    INFLUXDB_BUCKET=cerebral \
    INFLUXDB_TOKEN=secret-token \
    INFLUXDB_ORG=InfluxData \
    REDIS_URL=redis://10.0.0.4:6379

EXPOSE 5000

CMD ["python", "app.py"]

