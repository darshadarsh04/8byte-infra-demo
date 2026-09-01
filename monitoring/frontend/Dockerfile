# Static frontend served by nginx. No build step needed - it's plain HTML/JS -
# but kept as its own image/tier so it scales and deploys independently of the API.
FROM nginx:1.27-alpine

# Replace the default server block with our own (adds /healthz + SPA fallback)
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY src/ /usr/share/nginx/html/

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -q -O /dev/null http://localhost/healthz || exit 1
# nginx:alpine already runs as an unprivileged user for worker processes and
# drops to it automatically; the base image's default CMD starts nginx.
