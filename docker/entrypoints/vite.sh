#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

pnpm store prune
pnpm install --force

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
