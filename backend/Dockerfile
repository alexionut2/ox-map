FROM node:22-alpine
WORKDIR /app
COPY package.json ./
COPY src ./src
ENV NODE_ENV=production PORT=8080 OXYDE_DATA_FILE=/data/reports.json
VOLUME /data
EXPOSE 8080
USER node
CMD ["node", "src/server.js"]
