#!/bin/sh

set -eu

MIX_ENV=prod mix sentry.package_source_code
MIX_ENV=prod mix release chat