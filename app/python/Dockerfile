ARG RUN_IMAGE=cgr.dev/chainguard/python:latest

FROM ${RUN_IMAGE}

WORKDIR /app
COPY app.py .

EXPOSE 8080
CMD ["python", "app.py"]
