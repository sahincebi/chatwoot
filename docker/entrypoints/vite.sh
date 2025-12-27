#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

pnpm store prune
pnpm install --force

export GEM_HOME="${GEM_HOME:-/gems}"
export BUNDLE_PATH="${BUNDLE_PATH:-/gems}"
export GEM_PATH="$GEM_HOME:/usr/local/lib/ruby/gems/3.4.0:/usr/local/bundle:/root/.local/share/gem/ruby/3.4.0"
export BUNDLE_WITHOUT="${BUNDLE_WITHOUT:-}"

gem list -i bundler -v 2.5.11 || gem install bundler -v 2.5.11 --no-document
bundle _2.5.11_ check || bundle _2.5.11_ install --jobs 4 --retry 3

echo "Ready to run Vite development server."

exec "$@"
