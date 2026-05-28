FROM node:20-alpine

# Répertoire de travail
WORKDIR /app

# Copier les fichiers de dépendances en premier (cache Docker)
COPY package*.json ./

# Installer les dépendances (production uniquement)
RUN npm install --omit=dev

# Copier le reste du code
COPY server.js ./

# Port exposé
EXPOSE 3000

# Healthcheck Docker natif
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

# Démarrer le serveur
CMD ["node", "server.js"]
