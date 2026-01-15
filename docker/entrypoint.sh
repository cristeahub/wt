#!/bin/bash

# Source wt env file if present (contains auth tokens)
if [ -f /home/dev/.wt-env ]; then
  source /home/dev/.wt-env
fi

# Ensure PostgreSQL run directory exists with correct permissions
sudo mkdir -p /var/run/postgresql
sudo chown postgres:postgres /var/run/postgresql

# Start PostgreSQL
sudo service postgresql start

# Execute the command passed to docker run
exec "$@"
