#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

if [ "${PNPM_PRUNE:-0}" = "1" ]; then
  pnpm store prune
fi

LOCKFILE="/app/pnpm-lock.yaml"
NODE_MODULES="/app/node_modules"

if [ ! -d "$NODE_MODULES" ]; then
  NEEDS_INSTALL=1
elif [ -f "$LOCKFILE" ] && { [ ! -f "$NODE_MODULES/.pnpm-lock.yaml" ] || [ "$LOCKFILE" -nt "$NODE_MODULES/.pnpm-lock.yaml" ]; }; then
  NEEDS_INSTALL=1
else
  NEEDS_INSTALL=0
fi

if [ "$NEEDS_INSTALL" = "1" ]; then
  pnpm install --frozen-lockfile || pnpm install
fi

export GEM_HOME="${GEM_HOME:-/gems}"
export BUNDLE_PATH="${BUNDLE_PATH:-/gems}"
export GEM_PATH="${GEM_PATH:-$GEM_HOME:/usr/local/lib/ruby/gems/3.4.0:/usr/local/bundle:/root/.local/share/gem/ruby/3.4.0}"
export BUNDLE_WITHOUT="${BUNDLE_WITHOUT:-}"

if ! bundle _2.5.11_ check; then
  echo "Bundle check failed. Run bundle _2.5.11_ install in the rails container to compile native gems."
  exit 1
fi

echo "Ready to run Vite development server."

exec bundle _2.5.11_ exec bin/vite dev
