# --- build stage ---
FROM node:20-alpine AS build
WORKDIR /app
# copy manifests first so the dependency layer is cached unless they change
COPY package.json package-lock.json ./
# npm ci installs the exact locked versions - reproducible, unlike `npm install`
RUN npm ci --omit=dev
COPY src ./src

# --- runtime stage ---
FROM node:20-alpine
# drop root: run the app as an unprivileged user
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/src ./src
USER app
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD node -e "require('http').get('http://localhost:3000/health',(r)=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"
CMD ["node", "src/index.js"]
