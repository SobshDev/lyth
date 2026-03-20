#!/bin/sh
# Fix volume ownership at runtime (handles root-owned volumes from prior runs)
chown -R node:node /app/data

# Drop to node user and start the server
exec su -s /bin/sh node -c "node server/server.js $*"
