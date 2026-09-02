FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY scanner.py .
RUN useradd -m scanner
USER scanner
ENTRYPOINT ["python", "scanner.py"]
