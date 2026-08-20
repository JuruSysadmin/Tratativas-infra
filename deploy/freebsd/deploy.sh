#!/bin/sh

# Native FreeBSD deployment for the Chat release.
# This script expects the release to be built before it is called.

set -eu
umask 027

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)

APP_NAME=${CHAT_APP_NAME:-chat}
APP_USER=${CHAT_APP_USER:-chat}
APP_GROUP=${CHAT_APP_GROUP:-chat}
APP_DIR=${CHAT_APP_DIR:-/opt/chat}
RELEASES_DIR=${CHAT_RELEASES_DIR:-${APP_DIR}/releases}
CURRENT_LINK=${CHAT_CURRENT_LINK:-${APP_DIR}/current}
ENV_FILE=${CHAT_ENV_FILE:-/usr/local/etc/chat.env}
RC_SCRIPT=${CHAT_RC_SCRIPT:-/usr/local/etc/rc.d/${APP_NAME}}
RELEASE_SOURCE=${CHAT_RELEASE_SOURCE:-${PROJECT_DIR}/_build/prod/rel/${APP_NAME}}
HEALTH_HOST=${CHAT_HEALTH_HOST:-::1}
HEALTH_PORT=${CHAT_HEALTH_PORT:-5000}
HEALTH_TIMEOUT=${CHAT_HEALTH_TIMEOUT:-30}

usage()
{
    cat <<EOF
Usage: $0 [--bootstrap]

Without arguments, installs the prepared release and performs a validated
FreeBSD deployment. --bootstrap creates the service directories, installs the
rc.d script and enables the service without starting it.

Environment overrides:
  CHAT_APP_DIR, CHAT_RELEASES_DIR, CHAT_CURRENT_LINK
  CHAT_ENV_FILE, CHAT_RELEASE_SOURCE, CHAT_HEALTH_HOST, CHAT_HEALTH_PORT
EOF
}

fail()
{
    echo "chat deploy: $*" >&2
    exit 1
}

require_root()
{
    [ "$(id -u)" -eq 0 ] || fail "run this script through sudo as root"
}

require_command()
{
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

ensure_user_and_directories()
{
    if ! pw groupshow "${APP_GROUP}" >/dev/null 2>&1; then
        pw groupadd "${APP_GROUP}" || fail "could not create group ${APP_GROUP}"
    fi

    if ! pw usershow "${APP_USER}" >/dev/null 2>&1; then
        pw useradd "${APP_USER}" -g "${APP_GROUP}" -d /nonexistent -s /usr/sbin/nologin || \
            fail "could not create user ${APP_USER}"
    fi

    install -d -o root -g "${APP_GROUP}" -m 0750 "${APP_DIR}"
    install -d -o root -g "${APP_GROUP}" -m 0750 "${RELEASES_DIR}"
    install -d -o "${APP_USER}" -g "${APP_GROUP}" -m 0750 "/var/run/${APP_NAME}"
    install -d -o "${APP_USER}" -g "${APP_GROUP}" -m 0750 "/var/log/${APP_NAME}"
}

install_service()
{
    install -o root -g wheel -m 0555 "${PROJECT_DIR}/priv/${APP_NAME}" "${RC_SCRIPT}"
}

bootstrap()
{
    ensure_user_and_directories
    install_service
    sysrc "${APP_NAME}_enable=YES" >/dev/null
    echo "Bootstrap complete. Create ${ENV_FILE} before starting ${APP_NAME}."
}

source_environment()
{
    [ -r "${ENV_FILE}" ] || fail "environment file not found: ${ENV_FILE}"

    set -a
    . "${ENV_FILE}"
    set +a
}

wait_for_ready()
{
    health_url="http://${HEALTH_HOST}:${HEALTH_PORT}"
    case "${HEALTH_HOST}" in
        *:*) health_url="http://[${HEALTH_HOST}]:${HEALTH_PORT}" ;;
    esac

    attempt=1
    while [ "${attempt}" -le "${HEALTH_TIMEOUT}" ]; do
        if curl -fsS "${health_url}/health" >/dev/null 2>&1 && \
           curl -fsS "${health_url}/ready" >/dev/null 2>&1; then
            return 0
        fi

        sleep 1
        attempt=$((attempt + 1))
    done

    return 1
}

switch_current_release()
{
    release_dir=$1
    temporary_link="${CURRENT_LINK}.new.$$"

    rm -f "${temporary_link}"
    ln -s "${release_dir}" "${temporary_link}"
    mv -f "${temporary_link}" "${CURRENT_LINK}"
}

restore_previous_release()
{
    previous_release=$1

    service "${APP_NAME}" stop >/dev/null 2>&1 || true

    if [ -n "${previous_release}" ]; then
        switch_current_release "${previous_release}"
        service "${APP_NAME}" start || true
    fi
}

deploy()
{
    [ -x "${RELEASE_SOURCE}/bin/${APP_NAME}" ] || \
        fail "release not found or not executable: ${RELEASE_SOURCE}"
    [ -r "${ENV_FILE}" ] || fail "environment file not found: ${ENV_FILE}"

    ensure_user_and_directories
    install_service
    source_environment

    release_id=$(date -u +%Y%m%d%H%M%S)-$$
    release_dir="${RELEASES_DIR}/${release_id}"
    previous_release=""

    if [ -L "${CURRENT_LINK}" ]; then
        previous_release=$(readlink "${CURRENT_LINK}")
    fi

    install -d -o "${APP_USER}" -g "${APP_GROUP}" -m 0750 "${release_dir}"
    cp -R "${RELEASE_SOURCE}/." "${release_dir}/"
    chown -R "${APP_USER}:${APP_GROUP}" "${release_dir}"

    service "${APP_NAME}" stop >/dev/null 2>&1 || true
    switch_current_release "${release_dir}"

    if ! su -m "${APP_USER}" -c "HOME=/var/run/${APP_NAME}; export HOME; ${CURRENT_LINK}/bin/${APP_NAME} eval 'Chat.Release.migrate()'"; then
        echo "Migration failed; restoring the previous release." >&2
        restore_previous_release "${previous_release}"
        fail "migration failed; verify database compatibility before retrying"
    fi

    if ! service "${APP_NAME}" start; then
        echo "Service failed to start; restoring the previous release." >&2
        restore_previous_release "${previous_release}"
        fail "service start failed"
    fi

    if ! wait_for_ready; then
        echo "Readiness checks failed; restoring the previous release." >&2
        restore_previous_release "${previous_release}"
        fail "post-deploy health/readiness validation failed"
    fi

    echo "Deployment complete: ${release_id}"
}

main()
{
    case "${1:-}" in
        --help|-h) usage; exit 0 ;;
        ""|--bootstrap) ;;
        *) usage >&2; exit 2 ;;
    esac

    require_root
    require_command install
    require_command pw
    require_command service
    require_command sysrc
    require_command curl
    require_command su

    case "${1:-}" in
        "") deploy ;;
        --bootstrap) bootstrap ;;
    esac
}

main "$@"
