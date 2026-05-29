#!/usr/bin/env bash
set -euo pipefail

STATUS="${1:?Usage: $0 <success|failure|cancelled> [pipeline-name] [environment] [image-tag]}"
PIPELINE_NAME="${2:-CI/CD Pipeline}"
ENVIRONMENT="${3:-}"
IMAGE_TAG="${4:-${GITHUB_SHA:-}}"

CI_MODE="${GITHUB_ACTIONS:-false}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

case "${STATUS}" in
    success) EMOJI="✅"; COLOR="#36a64f" ;;
    failure) EMOJI="❌"; COLOR="#ff0000" ;;
    cancelled) EMOJI="⚠️"; COLOR="#ffaa00" ;;
    *) EMOJI="ℹ️"; COLOR="#0000ff" ;;
esac

TRIGGERED_BY="$(whoami)"
if [ "${CI_MODE}" = "true" ]; then
    TRIGGERED_BY="GitHub Actions (${GITHUB_ACTOR:-unknown})"
fi

send_slack() {
    local webhook_url="${SLACK_WEBHOOK_URL:-}"
    if [ -z "${webhook_url}" ]; then
        log "SLACK_WEBHOOK_URL not set, skipping Slack notification"
        return 0
    fi

    local payload
    payload=$(cat <<EOF
{
    "attachments": [{
        "color": "${COLOR}",
        "title": "${EMOJI} ${PIPELINE_NAME} - ${STATUS}",
        "fields": [
            {"title": "Environment", "value": "${ENVIRONMENT:-N/A}", "short": true},
            {"title": "Image Tag", "value": "${IMAGE_TAG:-N/A}", "short": true},
            {"title": "Triggered by", "value": "${TRIGGERED_BY}", "short": true}
        ],
        "ts": $(date +%s)
    }]
}
EOF
    )

    curl -sf -X POST -H 'Content-type: application/json' \
        --data "${payload}" \
        "${webhook_url}" || log "Failed to send Slack notification"
}

send_dingtalk() {
    local webhook_url="${DINGTALK_WEBHOOK_URL:-}"
    if [ -z "${webhook_url}" ]; then
        log "DINGTALK_WEBHOOK_URL not set, skipping DingTalk notification"
        return 0
    fi

    local payload
    payload=$(cat <<EOF
{
    "msgtype": "markdown",
    "markdown": {
        "title": "${PIPELINE_NAME} ${STATUS}",
        "text": "## ${EMOJI} ${PIPELINE_NAME} - ${STATUS}\n\n- **Environment:** ${ENVIRONMENT:-N/A}\n- **Image Tag:** ${IMAGE_TAG:-N/A}\n- **Triggered by:** ${TRIGGERED_BY}\n"
    }
}
EOF
    )

    curl -sf -X POST -H 'Content-type: application/json' \
        --data "${payload}" \
        "${webhook_url}" || log "Failed to send DingTalk notification"
}

send_github_summary() {
    if [ "${CI_MODE}" != "true" ]; then
        return 0
    fi

    log "Running in GitHub Actions mode"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        {
            echo "## ${EMOJI} ${PIPELINE_NAME} - ${STATUS}"
            echo "| Field | Value |"
            echo "|-------|-------|"
            echo "| Environment | ${ENVIRONMENT:-N/A} |"
            echo "| Image Tag | ${IMAGE_TAG:-N/A} |"
            echo "| Triggered by | ${TRIGGERED_BY} |"
        } >> "${GITHUB_STEP_SUMMARY}"
    fi
}

log "=== Sending Notifications ==="
log "Status: ${STATUS}"
log "Pipeline: ${PIPELINE_NAME}"
log "CI Mode: ${CI_MODE}"

send_slack
send_dingtalk
send_github_summary

log "=== Notifications Sent ==="
