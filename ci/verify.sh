#!/usr/bin/env bash
set -euo pipefail

export MIX_ENV="${MIX_ENV:-test}"

mix local.hex --force
mix local.rebar --force
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix test
