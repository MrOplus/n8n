FROM n8nio/n8n:latest

USER root

# Install undici into a known path and expose via NODE_PATH
# This ensures the patch-http-timeouts.js can find and configure the undici dispatcher
RUN mkdir -p /opt/extra && \
    npm --prefix /opt/extra install undici@7 && \
    chown -R node:node /opt/extra

ENV NODE_PATH=/opt/extra/node_modules

USER node
