#!/usr/bin/env bash
# ============================================================
#  build-all.sh — Clean & Build of all microservices
#  Saga Orchestration + ai-saga-agent
# ============================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Configuration ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$SCRIPT_DIR}"
LOG_DIR="$ROOT_DIR/build-logs"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
SKIP_TESTS=${SKIP_TESTS:-true}

# Dependencies first
SERVICES=(
  "orchestrator-service"
  "inventory-service"
  "payment-service"
  "product-validation-service"
  "order-service"
  "ai-saga-agent"
)

# ── Counters ───────────────────────────────────────────────
SUCCESS=0
FAILED=0
SKIPPED=0
FAILED_SERVICES=()
BUILD_TIME_KEYS=()
BUILD_TIME_VALS=()

# ── Helpers ──────────────────────────────────────────────────
log()    { echo -e "${BOLD}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()     { echo -e "${GREEN}✔${NC}  $*"; }
err()    { echo -e "${RED}✘${NC}  $*"; }
warn()   { echo -e "${YELLOW}⚠${NC}  $*"; }
info()   { echo -e "${CYAN}ℹ${NC}  $*"; }
section(){ echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}"; \
           echo -e "${BOLD}${BLUE}  $*${NC}"; \
           echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}\n"; }

detect_build_tool() {
  local dir="$1"
  if [[ -f "$dir/gradlew" ]]; then
    echo "gradle"
  elif [[ -f "$dir/mvnw" ]]; then
    echo "maven"
  elif command -v gradle &>/dev/null && [[ -f "$dir/build.gradle" ]]; then
    echo "gradle-global"
  elif command -v mvn &>/dev/null && [[ -f "$dir/pom.xml" ]]; then
    echo "maven-global"
  else
    echo "unknown"
  fi
}

build_service() {
  local service="$1"
  local dir="$ROOT_DIR/$service"
  local log_file="$LOG_DIR/${service}_${TIMESTAMP}.log"
  local start_time end_time elapsed

  # Check if directory exists
  if [[ ! -d "$dir" ]]; then
    warn "Directory not found: $dir — skipping $service"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  log "${BOLD}Starting:${NC} $service"

  local tool
  tool=$(detect_build_tool "$dir")
  start_time=$(date +%s)

  local cmd=""
  local test_flag=""

  case "$tool" in
    gradle)
      test_flag=$([[ "$SKIP_TESTS" == "true" ]] && echo "-x test" || echo "")
      cmd="./gradlew clean build $test_flag --no-daemon --console=plain"
      ;;
    gradle-global)
      test_flag=$([[ "$SKIP_TESTS" == "true" ]] && echo "-x test" || echo "")
      cmd="gradle clean build $test_flag --no-daemon --console=plain"
      ;;
    maven)
      test_flag=$([[ "$SKIP_TESTS" == "true" ]] && echo "-DskipTests" || echo "")
      cmd="./mvnw clean package $test_flag -q"
      ;;
    maven-global)
      test_flag=$([[ "$SKIP_TESTS" == "true" ]] && echo "-DskipTests" || echo "")
      cmd="mvn clean package $test_flag -q"
      ;;
    unknown)
      err "No build tool recognized in: $dir"
      FAILED=$((FAILED + 1))
      FAILED_SERVICES+=("$service")
      return 1
      ;;
  esac

  info "Tool: $tool | Cmd: $cmd"
    info "Log: $log_file"

    if (cd "$dir" && eval "$cmd") > "$log_file" 2>&1; then
      end_time=$(date +%s)
      elapsed=$((end_time - start_time))
      BUILD_TIME_KEYS+=("$service")
      BUILD_TIME_VALS+=("${elapsed}s")
      ok "$service ${GREEN}BUILD SUCCESS${NC} (${elapsed}s)"
      SUCCESS=$((SUCCESS + 1))
    else
      end_time=$(date +%s)
      elapsed=$((end_time - start_time))
      BUILD_TIME_KEYS+=("$service")
      BUILD_TIME_VALS+=("${elapsed}s ✘")
      err "$service ${RED}BUILD FAILED${NC} (${elapsed}s)"
      echo -e "${YELLOW}  Last 20 lines of log:${NC}"
    tail -20 "$log_file" | sed 's/^/    /'
    FAILED=$((FAILED + 1))
    FAILED_SERVICES+=("$service")

    if [[ "${STOP_ON_FAILURE:-false}" == "true" ]]; then
      err "STOP_ON_FAILURE=true — aborting."
      exit 1
    fi
  fi
}


# ── Banner ───────────────────────────────────────────────────
echo -e "${BOLD}${BLUE}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║   Saga Orchestration — Clean & Build All      ║"
echo "  ║   LangChain4j + MCP + Sub-Agents              ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Arguments ──────────────────────────────────────────────
# Usage: ./build-all.sh [service1 service2 ...] [--with-tests] [--stop-on-failure]
TARGET_SERVICES=()
for arg in "$@"; do
  case "$arg" in
    --with-tests)      SKIP_TESTS=false ;;
    --stop-on-failure) STOP_ON_FAILURE=true ;;
    --help|-h)
      echo "Usage: $0 [services...] [options]"
      echo ""
      echo "Available services:"
      printf '  %s\n' "${SERVICES[@]}"
      echo ""
      echo "Options:"
      echo "  --with-tests       Include test execution"
      echo "  --stop-on-failure  Stop on first error"
      echo "  --help             This message"
      echo ""
      echo "Environment variables:"
      echo "  ROOT_DIR=<path>    Root directory of projects (default: script folder)"
      echo ""
      echo "Examples:"
      echo "  ./build-all.sh                          # All, without tests"
      echo "  ./build-all.sh --with-tests             # All with tests"
      echo "  ./build-all.sh inventory-service ai-saga-agent  # Only these two"
      echo "  ROOT_DIR=/home/user/projects ./build-all.sh     # Custom root"
      exit 0
      ;;
    *)
      TARGET_SERVICES+=("$arg")
      ;;
  esac
done

# Se especificou servicos especificos, usa eles; senao usa todos
if [[ ${#TARGET_SERVICES[@]} -gt 0 ]]; then
  SERVICES=("${TARGET_SERVICES[@]}")
fi

# ── Setup ────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"

section "Configuration"
info "Root dir:    $ROOT_DIR"
info "Log dir:     $LOG_DIR"
info "Skip tests:  $SKIP_TESTS"
info "Services:    ${SERVICES[*]}"

# ── Pre-build checks ───────────────────────────────────
section "Checks"

# Java
if ! command -v java &>/dev/null; then
  err "Java not found. Install JDK 17+."
  exit 1
fi
JAVA_VERSION=$(java -version 2>&1 | head -1)
ok "Java: $JAVA_VERSION"

# Check OPENAI_API_KEY if ai-saga-agent is in the list
if printf '%s\n' "${SERVICES[@]}" | grep -q "ai-saga-agent"; then
  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    warn "OPENAI_API_KEY not defined — ai-saga-agent may fail at runtime"
    warn "  Export: export OPENAI_API_KEY=sk-..."
  else
    ok "OPENAI_API_KEY: configured"
  fi
fi

# ── Publish saga-commons ─────────────────────────────────────
section "Publishing saga-commons"
SAGA_COMMONS_DIR="$ROOT_DIR/saga-commons"
if [[ -d "$SAGA_COMMONS_DIR" ]]; then
  log "Publishing saga-commons to mavenLocal..."
  if (cd "$SAGA_COMMONS_DIR" && ./gradlew publishToMavenLocal --no-daemon --console=plain) > "$LOG_DIR/saga-commons-publish_${TIMESTAMP}.log" 2>&1; then
    ok "saga-commons published successfully"
  else
    err "Failed to publish saga-commons — all dependent services will fail"
    tail -10 "$LOG_DIR/saga-commons-publish_${TIMESTAMP}.log" | sed 's/^/    /'
    exit 1
  fi
else
  err "saga-commons directory not found at $SAGA_COMMONS_DIR"
  exit 1
fi

# ── Build ─────────────────────────────────────────────────────
section "Build (${#SERVICES[@]} services)"
GLOBAL_START=$(date +%s)

for service in "${SERVICES[@]}"; do
  echo ""
  build_service "$service"
done

GLOBAL_END=$(date +%s)
GLOBAL_ELAPSED=$((GLOBAL_END - GLOBAL_START))

# ── Final Report ───────────────────────────────────────────
section "Final Report"

echo -e "${BOLD}Time per service:${NC}"
for service in "${SERVICES[@]}"; do
  time_str=""
  for i in "${!BUILD_TIME_KEYS[@]}"; do
    if [[ "${BUILD_TIME_KEYS[$i]}" == "$service" ]]; then
      time_str="${BUILD_TIME_VALS[$i]}"
      break
    fi
  done

  if [[ -z "$time_str" ]]; then
    echo -e "  ${YELLOW}–${NC}  $(printf '%-40s' "$service") ${YELLOW}skipped${NC}"
  elif [[ "$time_str" == *"✘"* ]]; then
    echo -e "  ${RED}✘${NC}  $(printf '%-40s' "$service") ${RED}$time_str${NC}"
  else
    echo -e "  ${GREEN}✔${NC}  $(printf '%-40s' "$service") ${GREEN}$time_str${NC}"
  fi
done

echo ""
echo -e "${BOLD}Summary:${NC}"
echo -e "  ${GREEN}✔  Success: $SUCCESS${NC}"
echo -e "  ${RED}✘  Failures: $FAILED${NC}"
echo -e "  ${YELLOW}–  Skipped: $SKIPPED${NC}"
echo -e "  ${CYAN}⏱  Total:   ${GLOBAL_ELAPSED}s${NC}"

if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
  echo ""
  err "Services with failures:"
  for svc in "${FAILED_SERVICES[@]}"; do
    echo -e "  ${RED}•${NC} $svc — log: $LOG_DIR/${svc}_${TIMESTAMP}.log"
  done
  echo ""
  exit 1
else
  echo ""
  ok "${GREEN}${BOLD}All builds completed successfully!${NC}"
  echo ""
fi