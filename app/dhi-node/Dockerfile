ARG RUN_IMAGE=node:20-alpine

FROM ${RUN_IMAGE}

WORKDIR /app
COPY app.js .

EXPOSE 8080
CMD ["node", "app.js"]
