#!/usr/bin/env bash
#
# benchmark-allocator.sh — Compare glibc vs jemalloc allocator for Electric.
#
# Builds two Electric images (one with glibc malloc, one with jemalloc), runs
# the load_generator Turbo scenario against each, and collects container memory
# (RSS) and load_generator stats into timestamped output files.
#
# Usage:
#   ./bin/benchmark-allocator.sh [DURATION_SECONDS] [ELECTRIC_CONTEXT_PATH]
#
#   DURATION_SECONDS       how long to run each variant (default: 600 = 10 min)
#   ELECTRIC_CONTEXT_PATH  docker build context for Electric (default: ../electric/packages/sync-service)

set -euo pipefail

DURATION="${1:-600}"
ELECTRIC_CONTEXT="${2:-../electric/packages/sync-service}"
COMPOSE_FILE="docker-compose.benchmark.yaml"
RESULTS_DIR="benchmark-results/$(date +%Y%m%d-%H%M%S)"
SAMPLE_INTERVAL=10  # seconds between memory samples

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

mkdir -p "$RESULTS_DIR"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# ── Build both Electric images ───────────────────────────────────────────────

log "Building Electric (glibc)..."
docker build \
  --build-arg USE_JEMALLOC=false \
  -t electric:bench-glibc \
  -f Dockerfile.electric \
  "$ELECTRIC_CONTEXT" 2>&1 | tail -5

log "Building Electric (jemalloc)..."
docker build \
  --build-arg USE_JEMALLOC=true \
  -t electric:bench-jemalloc \
  -f Dockerfile.electric \
  "$ELECTRIC_CONTEXT" 2>&1 | tail -5

log "Building load_generator..."
docker compose -f "$COMPOSE_FILE" build load_generator 2>&1 | tail -3

# ── Helper: collect docker stats for the electric container ──────────────────

collect_stats() {
  local output_file="$1"
  local container_name

  # Write CSV header
  echo "elapsed_s,rss_bytes,mem_limit_bytes,mem_percent,pids" > "$output_file"

  local start_time
  start_time=$(date +%s)

  while true; do
    # Find the electric container — may take a moment to start
    container_name=$(docker compose -f "$COMPOSE_FILE" ps -q electric 2>/dev/null || true)

    if [[ -n "$container_name" ]]; then
      # Use the cgroup memory file for precise RSS when available, fall back to
      # docker stats. docker stats --format gives us what we need in one call.
      local stats_line
      stats_line=$(docker stats "$container_name" --no-stream \
        --format '{{.MemUsage}},{{.MemPerc}},{{.PIDs}}' 2>/dev/null || echo ",,")

      if [[ -n "$stats_line" && "$stats_line" != ",," ]]; then
        local elapsed=$(( $(date +%s) - start_time ))
        # Parse "123.4MiB / 7.5GiB" into bytes
        local raw_usage raw_limit mem_pct pids
        raw_usage=$(echo "$stats_line" | cut -d',' -f1 | cut -d'/' -f1 | xargs)
        raw_limit=$(echo "$stats_line" | cut -d',' -f1 | cut -d'/' -f2 | xargs)
        mem_pct=$(echo "$stats_line" | cut -d',' -f2 | tr -d '%' | xargs)
        pids=$(echo "$stats_line" | cut -d',' -f3 | xargs)

        echo "${elapsed},${raw_usage},${raw_limit},${mem_pct},${pids}" >> "$output_file"
      fi
    fi

    sleep "$SAMPLE_INTERVAL"
  done
}

# ── Helper: run one benchmark variant ────────────────────────────────────────

run_variant() {
  local variant="$1"          # "glibc" or "jemalloc"
  local image="electric:bench-${variant}"
  local stats_file="${RESULTS_DIR}/${variant}-memory.csv"
  local logs_file="${RESULTS_DIR}/${variant}-loadgen.log"
  local electric_logs_file="${RESULTS_DIR}/${variant}-electric.log"
  local meta_file="${RESULTS_DIR}/${variant}-meta.txt"

  log "════════════════════════════════════════════════════"
  log "Starting benchmark: ${variant} (duration: ${DURATION}s)"
  log "════════════════════════════════════════════════════"

  # Record metadata
  cat > "$meta_file" <<EOF
variant: ${variant}
image: ${image}
duration_seconds: ${DURATION}
sample_interval_seconds: ${SAMPLE_INTERVAL}
started_at: $(date -Iseconds)
electric_context: ${ELECTRIC_CONTEXT}
EOF

  # Start the stack
  ELECTRIC_IMAGE="$image" docker compose -f "$COMPOSE_FILE" up -d

  # Wait for electric to be healthy
  log "Waiting for Electric to become healthy..."
  local retries=0
  while ! docker compose -f "$COMPOSE_FILE" ps electric 2>/dev/null | grep -q "healthy"; do
    retries=$((retries + 1))
    if [[ $retries -ge 60 ]]; then
      log "ERROR: Electric did not become healthy after 60s"
      docker compose -f "$COMPOSE_FILE" logs electric >> "$electric_logs_file" 2>&1
      docker compose -f "$COMPOSE_FILE" down -v 2>/dev/null
      return 1
    fi
    sleep 1
  done
  log "Electric is healthy."

  # Start memory stats collection in background
  collect_stats "$stats_file" &
  local stats_pid=$!

  # Stream load_generator logs to file (background)
  docker compose -f "$COMPOSE_FILE" logs -f load_generator > "$logs_file" 2>&1 &
  local logs_pid=$!

  # Let it run for the specified duration
  log "Load running — collecting data for ${DURATION}s..."
  sleep "$DURATION"

  # Capture final electric logs
  docker compose -f "$COMPOSE_FILE" logs electric > "$electric_logs_file" 2>&1

  # Append end time to metadata
  echo "ended_at: $(date -Iseconds)" >> "$meta_file"

  # Tear down
  log "Stopping ${variant} stack..."
  kill "$stats_pid" 2>/dev/null || true
  kill "$logs_pid" 2>/dev/null || true
  wait "$stats_pid" 2>/dev/null || true
  wait "$logs_pid" 2>/dev/null || true

  docker compose -f "$COMPOSE_FILE" down -v 2>/dev/null

  # Brief pause to let ports free up
  sleep 5

  log "Done with ${variant}. Data in ${RESULTS_DIR}/${variant}-*"
}

# ── Helper: generate summary ─────────────────────────────────────────────────

generate_summary() {
  local summary_file="${RESULTS_DIR}/summary.txt"

  log "Generating summary..."

  cat > "$summary_file" <<'HEADER'
═══════════════════════════════════════════════════════════
  Allocator Benchmark Summary
═══════════════════════════════════════════════════════════

HEADER

  for variant in glibc jemalloc; do
    local mem_file="${RESULTS_DIR}/${variant}-memory.csv"
    local log_file="${RESULTS_DIR}/${variant}-loadgen.log"

    echo "── ${variant} ──────────────────────────────────" >> "$summary_file"
    echo "" >> "$summary_file"

    if [[ -f "$mem_file" ]]; then
      echo "Memory samples: $(( $(wc -l < "$mem_file") - 1 ))" >> "$summary_file"

      # Extract RSS values (column 2), skipping header
      # These are human-readable (e.g. "123.4MiB") so just show first/last/max
      echo "" >> "$summary_file"
      echo "Memory timeline (elapsed_s, rss):" >> "$summary_file"
      echo "  First: $(sed -n '2p' "$mem_file" | cut -d',' -f1-2)" >> "$summary_file"
      echo "  Last:  $(tail -1 "$mem_file" | cut -d',' -f1-2)" >> "$summary_file"
      echo "" >> "$summary_file"

      echo "Raw memory samples:" >> "$summary_file"
      # Show samples at 25%, 50%, 75%, 100% of the run
      local total_lines=$(( $(wc -l < "$mem_file") - 1 ))
      if [[ $total_lines -gt 0 ]]; then
        for pct in 25 50 75 100; do
          local line_num=$(( total_lines * pct / 100 + 1 ))
          [[ $line_num -lt 2 ]] && line_num=2
          local line
          line=$(sed -n "${line_num}p" "$mem_file")
          if [[ -n "$line" ]]; then
            echo "  ${pct}%: ${line}" >> "$summary_file"
          fi
        done
      fi
    else
      echo "  (no memory data)" >> "$summary_file"
    fi

    echo "" >> "$summary_file"

    if [[ -f "$log_file" ]]; then
      echo "Load generator stats (last 5 reports):" >> "$summary_file"
      grep -E "\{.*duration" "$log_file" | tail -5 >> "$summary_file" 2>/dev/null || echo "  (no stats lines found)" >> "$summary_file"
    else
      echo "  (no load generator data)" >> "$summary_file"
    fi

    echo "" >> "$summary_file"
  done

  cat >> "$summary_file" <<FOOTER

═══════════════════════════════════════════════════════════
Results directory: ${RESULTS_DIR}

Files per variant:
  {variant}-memory.csv     — RSS sampled every ${SAMPLE_INTERVAL}s (CSV)
  {variant}-loadgen.log    — full load_generator stdout/stderr
  {variant}-electric.log   — Electric service logs
  {variant}-meta.txt       — run metadata (times, config)
═══════════════════════════════════════════════════════════
FOOTER

  log "Summary written to ${summary_file}"
  echo ""
  cat "$summary_file"
}

# ── Main ─────────────────────────────────────────────────────────────────────

log "Allocator benchmark: glibc vs jemalloc"
log "Duration per variant: ${DURATION}s"
log "Results directory: ${RESULTS_DIR}"
log "Electric build context: ${ELECTRIC_CONTEXT}"
echo ""

# Make sure nothing is running from a previous benchmark
docker compose -f "$COMPOSE_FILE" down -v 2>/dev/null || true

run_variant "glibc"
run_variant "jemalloc"
generate_summary

log "Benchmark complete. All data in ${RESULTS_DIR}/"
