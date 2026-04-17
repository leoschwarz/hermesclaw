#!/usr/bin/env bash
# Start HermesClaw — sandboxed (OpenShell) or plain Docker.
#
# Usage:
#   ./scripts/start.sh
#   ./scripts/start.sh --gpu                    # Pass NVIDIA GPU to sandbox
#   ./scripts/start.sh --policy permissive      # Use a policy preset
#
# Skip the local llama.cpp health check when using an external API that
# OpenShell routes through its privacy router:
#   HERMESCLAW_SKIP_INFERENCE_CHECK=1 ./scripts/start.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

GPU_FLAG=""
POLICY_PRESET="strict"
SANDBOX_NAME="${HERMESCLAW_SANDBOX:-hermesclaw-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_DIR="$SCRIPT_DIR/../openshell"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpu)    GPU_FLAG="--gpu"; shift ;;
        --policy) POLICY_PRESET="$2"; shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

# ── Pre-check: inference backend ─────────────────────────────────────────────
# Skip if using external API (OpenShell's inference.local handles routing).
# Only check for local llama.cpp when no external provider is configured.
SKIP_INFERENCE_CHECK="${HERMESCLAW_SKIP_INFERENCE_CHECK:-}"
if [ -z "$SKIP_INFERENCE_CHECK" ]; then
    if ! curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠  No local llama.cpp on port 8080.${RESET}"
        echo ""
        echo "If using a cloud API (Nous, OpenAI, etc.), skip this check:"
        echo -e "  ${CYAN}HERMESCLAW_SKIP_INFERENCE_CHECK=1 ./scripts/start.sh --policy gateway${RESET}"
        echo ""
        echo "Or start a local model first:"
        echo -e "  ${CYAN}llama-server -m models/<model>.gguf --port 8080 -ngl 99${RESET}"
        exit 1
    fi
    echo -e "${GREEN}✓ llama.cpp is running${RESET}"
else
    echo -e "${CYAN}ℹ  Skipping local inference check (external API mode)${RESET}"
fi

# ── Choose mode ──────────────────────────────────────────────────────────────
if command -v openshell &>/dev/null; then
    echo ""
    echo -e "${BOLD}Starting HermesClaw inside OpenShell sandbox...${RESET}"

    # Resolve policy file
    case "$POLICY_PRESET" in
        strict)      POLICY_FILE="$POLICY_DIR/policy-strict.yaml" ;;
        gateway)     POLICY_FILE="$POLICY_DIR/policy-gateway.yaml" ;;
        permissive)  POLICY_FILE="$POLICY_DIR/policy-permissive.yaml" ;;
        default)     POLICY_FILE="$POLICY_DIR/hermesclaw-policy.yaml" ;;
        *)
            echo -e "${YELLOW}Unknown policy preset: $POLICY_PRESET${RESET}" >&2
            echo "Available: strict, gateway, permissive, default" >&2
            exit 1
            ;;
    esac

    # Validate policy file exists
    if [ ! -f "$POLICY_FILE" ]; then
        echo -e "${YELLOW}Policy file not found: $POLICY_FILE${RESET}" >&2
        echo "Run ./scripts/setup.sh first." >&2
        exit 1
    fi

    # Validate OpenShell gateway is running
    if ! openshell status &>/dev/null; then
        echo -e "${YELLOW}⚠  OpenShell gateway is not running.${RESET}"
        echo -e "  Start it: ${CYAN}openshell gateway start${RESET}"
        exit 1
    fi

    # When skipping the local llama.cpp check, the agent will route via
    # OpenShell's inference.local proxy — which needs a registered provider.
    if [ -n "$SKIP_INFERENCE_CHECK" ] && ! openshell inference get &>/dev/null; then
        echo -e "${YELLOW}⚠  No OpenShell inference provider configured.${RESET}"
        echo "  Register one before chatting, e.g.:"
        echo -e "    ${CYAN}openshell provider create anthropic-prod --type anthropic --api-key \$ANTHROPIC_API_KEY${RESET}"
        echo -e "    ${CYAN}openshell inference set --provider anthropic-prod --model claude-sonnet-4-6${RESET}"
    fi

    echo -e "  Policy:  ${CYAN}$POLICY_PRESET${RESET}"
    echo -e "  Sandbox: ${CYAN}$SANDBOX_NAME${RESET}"
    [ -n "$GPU_FLAG" ] && echo -e "  GPU:     ${CYAN}enabled${RESET}"
    echo ""

    # Delete existing sandbox if present
    if openshell sandbox get "$SANDBOX_NAME" &>/dev/null; then
        echo -e "${YELLOW}Sandbox '$SANDBOX_NAME' already exists — deleting...${RESET}"
        openshell sandbox delete "$SANDBOX_NAME"
    fi

    # Run `sandbox create` without pipefail aborting the whole script — we want
    # to dump diagnostics on failure.
    set +e
    openshell sandbox create \
        --from "$SCRIPT_DIR/.." \
        --policy "$POLICY_FILE" \
        --name "$SANDBOX_NAME" \
        $GPU_FLAG \
        -- hermes gateway
    CREATE_RC=$?
    set -e

    if [ $CREATE_RC -ne 0 ]; then
        echo ""
        echo -e "${YELLOW}sandbox create exited with code $CREATE_RC — dumping diagnostics:${RESET}"
        echo ""
        echo -e "${BOLD}openshell sandbox get $SANDBOX_NAME${RESET}"
        openshell sandbox get "$SANDBOX_NAME" || true
        echo ""
        echo -e "${BOLD}openshell logs $SANDBOX_NAME --tail 200${RESET}"
        openshell logs "$SANDBOX_NAME" --tail 200 || true
        exit "$CREATE_RC"
    fi

    echo -e "${GREEN}✓ Sandbox started: $SANDBOX_NAME${RESET}"
    echo ""
    echo "Next steps:"
    echo -e "  ${CYAN}./scripts/hermesclaw status${RESET}      — health check"
    echo -e "  ${CYAN}./scripts/hermesclaw connect${RESET}     — open shell"
    echo -e "  ${CYAN}./scripts/hermesclaw logs${RESET}        — view logs"
    echo -e "  ${CYAN}./scripts/hermesclaw chat \"hi\"${RESET}  — talk to Hermes"
else
    echo ""
    echo -e "${YELLOW}OpenShell not available — starting in Docker-only mode.${RESET}"
    docker compose up
fi
