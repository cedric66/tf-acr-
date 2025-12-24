ARG RUN_IMAGE=python:3.11-alpine

FROM ${RUN_IMAGE}

WORKDIR /app
COPY app.py .

EXPOSE 8080
CMD ["python", "app.py"]
