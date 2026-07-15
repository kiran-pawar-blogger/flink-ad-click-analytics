FROM node:20-alpine
WORKDIR /app

# Install dependencies first (layer cache)
COPY package.json ./
RUN npm install --omit=dev

COPY src ./src

EXPOSE 3001

USER node

CMD ["node", "src/index.js"]
