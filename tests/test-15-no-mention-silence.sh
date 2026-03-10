#!/bin/bash
# test-15-no-mention-silence.sh - Case 15: Worker stays silent when not @mentioned
# Verifies: Worker receives messages from authorized senders but does NOT respond
# when the message does not @mention them (behavioral compliance with AGENTS.md).
#
# NOTE: This test is NON-BLOCKING in the full test suite. It verifies LLM behavioral
# compliance (instruction-following), not a hard technical gate. Occasional failures
# are expected due to LLM non-determinism.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/test-helpers.sh"
source "${SCRIPT_DIR}/lib/matrix-client.sh"

test_setup "15-no-mention-silence"

# ---- Prerequisites ----
log_section "Prerequisites"

require_llm_key || { echo "SKIP: LLM key required"; exit 0; }

# Find an existing Worker room (reuse from previous tests)
ADMIN_TOKEN=$(matrix_login "${TEST_ADMIN_USER}" "${TEST_ADMIN_PASSWORD}" | jq -r '.access_token // empty')
if [ -z "${ADMIN_TOKEN}" ]; then
    log_fail "Could not login as admin"
    test_summary
    exit $?
fi
log_pass "Admin login successful"

# Find a Worker room — look for "Worker:" prefix in room names
WORKER_ROOM_ID=$(matrix_find_room_by_name "${ADMIN_TOKEN}" "Worker:" 2>/dev/null)
if [ -z "${WORKER_ROOM_ID}" ]; then
    log_info "SKIP: No Worker room found. Run test-02-create-worker first."
    exit 0
fi
log_pass "Found Worker room: ${WORKER_ROOM_ID}"

# Extract Worker name from room name
ROOM_NAME=$(exec_in_manager curl -sf "${TEST_MATRIX_DIRECT_URL}/_matrix/client/v3/rooms/$(_encode_room_id "${WORKER_ROOM_ID}")/state/m.room.name" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" 2>/dev/null | jq -r '.name // empty')
WORKER_NAME=$(echo "${ROOM_NAME}" | sed 's/^Worker: *//')
log_info "Testing with Worker: ${WORKER_NAME} in room: ${ROOM_NAME}"

# ---- No-Mention Silence Test (with retries) ----
log_section "No-Mention Silence Test"

MAX_RETRIES=2
GRACE_WINDOW=90  # seconds to wait for Worker silence
LAST_FAILURE_REASON=""

for attempt in $(seq 0 ${MAX_RETRIES}); do
    if [ "${attempt}" -gt 0 ]; then
        log_info "Retry ${attempt}/${MAX_RETRIES}..."
        sleep 10
    fi

    # Snapshot: get the latest Worker message event_id before our test
    BASELINE_EVENT=$(matrix_read_messages "${ADMIN_TOKEN}" "${WORKER_ROOM_ID}" 5 2>/dev/null | \
        jq -r --arg user "@${WORKER_NAME}" \
        '[.chunk[] | select(.sender | startswith($user)) | .event_id] | first // ""' 2>/dev/null)

    # Send a message WITHOUT @mentioning the Worker
    TEST_MSG="General status update: all systems nominal. No action needed from anyone. (test-15 attempt ${attempt})"
    SEND_RESULT=$(matrix_send_message "${ADMIN_TOKEN}" "${WORKER_ROOM_ID}" "${TEST_MSG}")
    SENT_EVENT_ID=$(echo "${SEND_RESULT}" | jq -r '.event_id // empty')

    if [ -z "${SENT_EVENT_ID}" ]; then
        [ "${LAST_FAILURE_REASON}" != "worker_responded" ] && LAST_FAILURE_REASON="send_failed"
        log_info "Failed to send test message (attempt ${attempt}), retrying..."
        continue
    fi
    log_info "Sent test message (no @mention): event_id=${SENT_EVENT_ID}"

    # Verify message delivery by reading room timeline (hard gate — without confirmed
    # delivery, Worker silence could be a false positive from a failed send)
    sleep 2
    DELIVERY_CONFIRMED=false
    for dc_attempt in 1 2 3; do
        TIMELINE=$(matrix_read_messages "${ADMIN_TOKEN}" "${WORKER_ROOM_ID}" 5 2>/dev/null)
        if echo "${TIMELINE}" | jq -r '.chunk[].event_id' 2>/dev/null | grep -q "${SENT_EVENT_ID}"; then
            DELIVERY_CONFIRMED=true
            log_info "Message delivery confirmed in room timeline"
            break
        fi
        sleep 2
    done
    if [ "${DELIVERY_CONFIRMED}" = "false" ]; then
        [ "${LAST_FAILURE_REASON}" != "worker_responded" ] && LAST_FAILURE_REASON="delivery_unconfirmed"
        log_info "Could not confirm message delivery in room timeline (attempt ${attempt}), retrying..."
        continue
    fi

    # Wait and check if Worker responds (it should NOT)
    log_info "Waiting ${GRACE_WINDOW}s for Worker silence..."
    WORKER_RESPONDED=false

    ELAPSED=0
    while [ "${ELAPSED}" -lt "${GRACE_WINDOW}" ]; do
        sleep 15
        ELAPSED=$((ELAPSED + 15))

        LATEST_EVENT=$(matrix_read_messages "${ADMIN_TOKEN}" "${WORKER_ROOM_ID}" 5 2>/dev/null | \
            jq -r --arg user "@${WORKER_NAME}" \
            '[.chunk[] | select(.sender | startswith($user)) | .event_id] | first // ""' 2>/dev/null)

        if [ -n "${LATEST_EVENT}" ] && [ "${LATEST_EVENT}" != "${BASELINE_EVENT}" ]; then
            WORKER_RESPONDED=true
            break
        fi
    done

    if [ "${WORKER_RESPONDED}" = "false" ]; then
        log_pass "Worker stayed silent for ${GRACE_WINDOW}s when not @mentioned (attempt ${attempt})"
        test_summary
        exit $?
    else
        LAST_FAILURE_REASON="worker_responded"
        log_info "Worker responded to non-mentioned message (attempt ${attempt}) — may retry"
    fi
done

# All retries exhausted — report accurate failure reason
case "${LAST_FAILURE_REASON}" in
    send_failed)
        log_fail "Could not send test message after ${MAX_RETRIES} retries (Matrix API issue)" ;;
    delivery_unconfirmed)
        log_fail "Message delivery could not be confirmed after ${MAX_RETRIES} retries (timeline issue)" ;;
    worker_responded)
        log_fail "Worker responded to non-mentioned message after ${MAX_RETRIES} retries (behavioral compliance issue)" ;;
    *)
        log_fail "Test failed for unknown reason after ${MAX_RETRIES} retries" ;;
esac

test_summary
exit $?
