FROM nginxinc/nginx-unprivileged:alpine-slim

# Copy minimal, secure Nginx reverse proxy configuration
COPY --chown=nginx:nginx nginx.conf /etc/nginx/nginx.conf

# Expose non-privileged HTTP port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost:8080/health || exit 1

STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]
