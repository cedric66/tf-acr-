ARG RUN_IMAGE=cgr.dev/chainguard/node:latest

FROM ${RUN_IMAGE}

WORKDIR /app
COPY app.js .

EXPOSE 8080
CMD ["node", "app.js"]
