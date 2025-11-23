FROM python:3.12-slim

RUN pip install --no-cache-dir ansible-core

RUN mkdir -p /var/log && touch /var/log/remediation.log

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5001

ENTRYPOINT ["uvicorn", "receiver:app", "--host", "0.0.0.0", "--port", "5001"]
