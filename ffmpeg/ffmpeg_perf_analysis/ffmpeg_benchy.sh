#!/usr/bin/env bash
# ============================================================
#  ffmpeg_benchmark.sh — WebM → MP4 Encoding Diagnostic
#  v1.3 — raw cat-merge for WebM fragments, no per-chunk
#          ffprobe (MediaRecorder chunks are not standalone)
# ============================================================

set -uo pipefail

RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m';  BOLD='\033[1m'
DIM='\033[2m';     RESET='\033[0m';    MAGENTA='\033[0;35m'

CHUNKS_DIR="${1:-./webm_chunks}"
RESULTS_DIR="${2:-./ffmpeg_bench_results}"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║       FFMPEG ENCODING BENCHMARK — DIAGNOSTIC LAB         ║${RESET}"
echo -e "${BOLD}${CYAN}║  WebM Chunks → MP4  |  CPU + NVENC  |  H.264 + H.265     ║${RESET}"
echo -e "${BOLD}${CYAN}║  v1.3 — raw cat-merge (MediaRecorder EBML stream model)  ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Preflight ────────────────────────────────────────────────
echo -e "${BOLD}[ PREFLIGHT ]${RESET}"

FFMPEG_BIN=""
for candidate in /usr/local/bin/ffmpeg /usr/bin/ffmpeg; do
  [[ -x "$candidate" ]] && FFMPEG_BIN="$candidate" && break
done
[[ -z "$FFMPEG_BIN" ]] && { echo -e "  ${RED}✗ ffmpeg not found${RESET}"; exit 1; }

FFPROBE_BIN="${FFMPEG_BIN/ffmpeg/ffprobe}"
[[ ! -x "$FFPROBE_BIN" ]] && FFPROBE_BIN=$(command -v ffprobe 2>/dev/null || true)
[[ -z "$FFPROBE_BIN" ]]   && { echo -e "  ${RED}✗ ffprobe not found${RESET}"; exit 1; }

command -v bc &>/dev/null || { echo -e "  ${RED}✗ bc missing: sudo apt install bc${RESET}"; exit 1; }

FFMPEG_VER=$("$FFMPEG_BIN" -version 2>&1 | head -1 | awk '{print $3}')
echo -e "  ${GREEN}✓ ffmpeg  : ${FFMPEG_BIN}  (${FFMPEG_VER})${RESET}"
echo -e "  ${GREEN}✓ ffprobe : ${FFPROBE_BIN}${RESET}"

[[ ! -d "$CHUNKS_DIR" ]] && { echo -e "  ${RED}✗ Chunks dir not found: ${CHUNKS_DIR}${RESET}"; exit 1; }

mapfile -t ALL_CHUNKS < <(ls "${CHUNKS_DIR}"/*.webm 2>/dev/null | sort)
TOTAL_FOUND=${#ALL_CHUNKS[@]}
[[ $TOTAL_FOUND -eq 0 ]] && { echo -e "  ${RED}✗ No .webm files in ${CHUNKS_DIR}${RESET}"; exit 1; }
echo -e "  ${GREEN}✓ Found ${TOTAL_FOUND} .webm chunks in ${CHUNKS_DIR}${RESET}"

mkdir -p "$RESULTS_DIR"
echo -e "  ${GREEN}✓ Results dir: ${RESULTS_DIR}${RESET}"

CPU_CORES=$(nproc)
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
echo -e "  ${GREEN}✓ CPU: ${CPU_MODEL} (${CPU_CORES} cores)${RESET}"

# ── NVENC detection ──────────────────────────────────────────
NVENC_AVAILABLE=false
H265_NVENC_AVAILABLE=false

echo ""
echo -e "  ${BOLD}NVENC diagnostics:${RESET}"

if "$FFMPEG_BIN" -hide_banner -encoders 2>/dev/null | grep -q 'h264_nvenc'; then
  echo -e "    ${GREEN}✓ h264_nvenc compiled in${RESET}"
  NVENC_LIB=$(ldconfig -p 2>/dev/null | grep -i 'libnvidia-encode' | head -1 || true)
  [[ -z "$NVENC_LIB" ]] && NVENC_LIB=$(find /usr/lib /lib -name "libnvidia-encode*" 2>/dev/null | head -1 || true)

  if [[ -z "$NVENC_LIB" ]]; then
    echo -e "    ${RED}✗ libnvidia-encode not found — sudo apt install libnvidia-encode1${RESET}"
  else
    echo -e "    ${GREEN}✓ libnvidia-encode: ${NVENC_LIB}${RESET}"
    nvenc_err=$("$FFMPEG_BIN" -hide_banner -loglevel error \
      -f lavfi -i color=black:s=64x64:d=1 -c:v h264_nvenc -f null - 2>&1 || true)
    if [[ -z "$nvenc_err" ]]; then
      NVENC_AVAILABLE=true
      echo -e "    ${GREEN}✓ h264_nvenc probe: OK${RESET}"
    else
      echo -e "    ${RED}✗ h264_nvenc probe failed: ${nvenc_err}${RESET}"
    fi
  fi

  if $NVENC_AVAILABLE && "$FFMPEG_BIN" -hide_banner -encoders 2>/dev/null | grep -q 'hevc_nvenc'; then
    hevc_err=$("$FFMPEG_BIN" -hide_banner -loglevel error \
      -f lavfi -i color=black:s=64x64:d=1 -c:v hevc_nvenc -f null - 2>&1 || true)
    if [[ -z "$hevc_err" ]]; then
      H265_NVENC_AVAILABLE=true
      echo -e "    ${GREEN}✓ hevc_nvenc probe: OK${RESET}"
    else
      echo -e "    ${YELLOW}⚠ hevc_nvenc probe failed${RESET}"
    fi
  fi
else
  echo -e "    ${YELLOW}⚠ h264_nvenc NOT compiled into this ffmpeg binary${RESET}"
  echo -e "    ${DIM}  Build from source with nv-codec-headers:${RESET}"
  echo -e "    ${DIM}  git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git${RESET}"
  echo -e "    ${DIM}  cd nv-codec-headers && sudo make install${RESET}"
  echo -e "    ${DIM}  cd ffmpeg-src && ./configure --enable-nonfree --enable-nvenc \\${RESET}"
  echo -e "    ${DIM}    --enable-cuvid --enable-libx264 --enable-libx265 --enable-gpl \\${RESET}"
  echo -e "    ${DIM}    --extra-cflags=-I/usr/local/cuda/include \\${RESET}"
  echo -e "    ${DIM}    --extra-ldflags=-L/usr/local/cuda/lib64${RESET}"
  echo -e "    ${DIM}  make -j\$(nproc) && sudo make install${RESET}"
fi

if command -v nvidia-smi &>/dev/null; then
  GPU_MODEL=$(nvidia-smi --query-gpu=name           --format=csv,noheader 2>/dev/null | head -1 || echo "?")
  DRV_VER=$(  nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "?")
  echo -e "    ${GREEN}✓ GPU: ${GPU_MODEL}  driver ${DRV_VER}${RESET}"
fi

echo ""

# ────────────────────────────────────────────────────────────
# PHASE 1 — CHUNK INVENTORY  (size check only — no ffprobe)
# ────────────────────────────────────────────────────────────
echo -e "${BOLD}[ CHUNK INVENTORY ]${RESET}"
echo ""
echo -e "  ${DIM}NOTE: MediaRecorder WebM chunks are NOT standalone files.${RESET}"
echo -e "  ${DIM}  chunk_000  = EBML init segment  (header + Tracks)${RESET}"
echo -e "  ${DIM}  chunk_001+ = Cluster segments   (raw media data, no header)${RESET}"
echo -e "  ${DIM}  Per-chunk ffprobe will always fail. We merge first, then validate.${RESET}"
echo ""

GOOD_CHUNKS=()
EMPTY_CHUNKS=()
TOTAL_RAW_BYTES=0
MIN_SIZE=999999999
MAX_SIZE=0

for f in "${ALL_CHUNKS[@]}"; do
  fsize=$(stat -c%s "$f" 2>/dev/null || echo 0)
  if [[ $fsize -lt 50 ]]; then
    EMPTY_CHUNKS+=("$(basename $f):${fsize}B")
    continue
  fi
  GOOD_CHUNKS+=("$f")
  TOTAL_RAW_BYTES=$(( TOTAL_RAW_BYTES + fsize ))
  (( fsize < MIN_SIZE )) && MIN_SIZE=$fsize
  (( fsize > MAX_SIZE )) && MAX_SIZE=$fsize
done

GOOD_COUNT=${#GOOD_CHUNKS[@]}
EMPTY_COUNT=${#EMPTY_CHUNKS[@]}
AVG_SIZE=$(( TOTAL_RAW_BYTES / (GOOD_COUNT > 0 ? GOOD_COUNT : 1) ))

echo -e "  Non-empty chunks : ${GREEN}${GOOD_COUNT}${RESET}  (of ${TOTAL_FOUND} total)"
[[ $EMPTY_COUNT -gt 0 ]] && echo -e "  Empty/tiny       : ${YELLOW}${EMPTY_COUNT}${RESET}"
echo -e "  Total raw size   : $(numfmt --to=iec $TOTAL_RAW_BYTES)"
echo -e "  Chunk size range : $(numfmt --to=iec $MIN_SIZE) – $(numfmt --to=iec $MAX_SIZE)"
echo -e "  Avg chunk size   : $(numfmt --to=iec $AVG_SIZE)"
echo ""

[[ $GOOD_COUNT -eq 0 ]] && { echo -e "${RED}✗ No non-empty chunks. Exiting.${RESET}"; exit 1; }

# ────────────────────────────────────────────────────────────
# PHASE 2 — RAW CAT MERGE
# ────────────────────────────────────────────────────────────
echo -e "${BOLD}[ MERGE — raw byte concatenation (cat) ]${RESET}"
echo ""
echo -e "  ${DIM}Correct method for MediaRecorder streams: binary cat of all chunks${RESET}"
echo -e "  ${DIM}chunk_000 provides the EBML header; subsequent chunks are its Clusters${RESET}"
echo ""

MERGED_WEBM="${RESULTS_DIR}/merged_input.webm"

echo -ne "  Concatenating ${GOOD_COUNT} chunks..."
MERGE_START=$(date +%s%N)
cat "${GOOD_CHUNKS[@]}" > "$MERGED_WEBM"
MERGE_END=$(date +%s%N)
MERGE_SECS=$(echo "scale=3; ($MERGE_END - $MERGE_START)/1000000000" | bc)
echo -e "  done in ${YELLOW}${MERGE_SECS}s${RESET}"

MERGED_SIZE=$(stat -c%s "$MERGED_WEBM")
echo -e "  Raw merged size  : $(numfmt --to=iec $MERGED_SIZE)"

# Validate the merged file (this one should pass)
echo -ne "  Validating merged file with ffprobe..."
MERGED_PROBE=$("$FFPROBE_BIN" -v error \
  -show_entries format=duration,size \
  -show_entries stream=codec_name,width,height,r_frame_rate,bit_rate \
  -of default=noprint_wrappers=1 "$MERGED_WEBM" 2>&1)
PROBE_EXIT=$?

if [[ $PROBE_EXIT -ne 0 ]] || echo "$MERGED_PROBE" | grep -qi "error\|invalid\|failed"; then
  echo -e "  ${RED} FAILED${RESET}"
  echo -e "  ${RED}  $MERGED_PROBE${RESET}"
  echo -e ""
  echo -e "  ${YELLOW}⚠ Merged file is invalid. Possible causes:${RESET}"
  echo -e "  ${DIM}    1. chunk_000 itself is corrupt (recording started mid-stream)${RESET}"
  echo -e "  ${DIM}    2. Chunks are from different recording sessions (mismatched headers)${RESET}"
  echo -e "  ${DIM}    3. The HTML recorder saved chunks out of order${RESET}"
  exit 1
fi

echo -e "  ${GREEN} OK${RESET}"

MERGED_DUR=$(echo "$MERGED_PROBE"  | grep '^duration='   | cut -d= -f2 | head -1)
MERGED_VCO=$(echo "$MERGED_PROBE"  | grep '^codec_name=' | cut -d= -f2 | head -1)
MERGED_W=$(  echo "$MERGED_PROBE"  | grep '^width='      | cut -d= -f2 | head -1)
MERGED_H=$(  echo "$MERGED_PROBE"  | grep '^height='     | cut -d= -f2 | head -1)
MERGED_FPS=$(echo "$MERGED_PROBE"  | grep '^r_frame_rate='| cut -d= -f2 | head -1)

echo -e "  Duration   : ${CYAN}${MERGED_DUR}s${RESET}"
echo -e "  Resolution : ${CYAN}${MERGED_W}×${MERGED_H}${RESET}  codec=${MERGED_VCO}  fps=${MERGED_FPS}"
echo ""

# Pick a representative single chunk: median index of good chunks
MEDIAN_IDX=$(( GOOD_COUNT / 2 ))
SINGLE_CHUNK="${GOOD_CHUNKS[$MEDIAN_IDX]}"
SINGLE_CHUNK_NAME=$(basename "$SINGLE_CHUNK")
SINGLE_CHUNK_SIZE=$(stat -c%s "$SINGLE_CHUNK")

# Build a mini valid webm for the single-chunk test:
# prepend init segment (chunk_000) to the median chunk → standalone valid webm
SINGLE_CHUNK_VALID="${RESULTS_DIR}/single_chunk_test.webm"
cat "${GOOD_CHUNKS[0]}" "$SINGLE_CHUNK" > "$SINGLE_CHUNK_VALID"
echo -e "  Single-chunk test: ${CYAN}${SINGLE_CHUNK_NAME}${RESET}  (init + chunk = $(numfmt --to=iec $(stat -c%s $SINGLE_CHUNK_VALID)))"
echo ""

# ────────────────────────────────────────────────────────────
# BENCHMARK RUNNER
# ────────────────────────────────────────────────────────────
declare -a RESULTS=()

run_bench() {
  local label="$1" encoder="$2" codec_tag="$3" preset="$4"
  local threads="$5" input="$6" input_tag="$7" extra_opts="$8"

  local out_path="${RESULTS_DIR}/${label// /_}_${input_tag}_${encoder}_${preset}_t${threads}.mp4"
  local thread_flag=""
  [[ "$threads" != "gpu" && "$threads" != "auto" ]] && thread_flag="-threads ${threads}"

  local t_start t_end encode_err encode_exit
  encode_exit=0
  t_start=$(date +%s%N)
  encode_err=$(eval "\"$FFMPEG_BIN\" -hide_banner -loglevel error \
    -i \"${input}\" ${thread_flag} ${extra_opts} \
    -preset ${preset} -movflags +faststart -pix_fmt yuv420p \
    \"${out_path}\" -y" 2>&1) || encode_exit=$?
  t_end=$(date +%s%N)

  if [[ $encode_exit -ne 0 || ! -f "$out_path" || \
        $(stat -c%s "$out_path" 2>/dev/null || echo 0) -lt 100 ]]; then
    RESULTS+=("${label}|${codec_tag}|${encoder}|${preset}|${threads}|${input_tag}|FAILED|—|—|—")
    echo -e "  ${RED}✗ FAILED${RESET}  ${encoder}  preset=${preset}  t=${threads}  (${input_tag})"
    [[ -n "$encode_err" ]] && echo -e "    ${DIM}${encode_err:0:120}${RESET}"
    return 0
  fi

  local elapsed_s out_size in_size ratio duration speed
  elapsed_s=$(echo "scale=3; ($t_end - $t_start)/1000000000" | bc)
  out_size=$(stat -c%s "$out_path")
  in_size=$(stat -c%s "$input")
  ratio=$(echo "scale=2; $in_size/$out_size" | bc 2>/dev/null || echo "—")
  duration=$("$FFPROBE_BIN" -v error -select_streams v:0 \
    -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$out_path" 2>/dev/null || echo "0")
  speed="—"
  [[ "$duration" != "0" && -n "$duration" ]] && \
    speed="$(echo "scale=2; $duration/$elapsed_s" | bc 2>/dev/null || echo "—")x"

  RESULTS+=("${label}|${codec_tag}|${encoder}|${preset}|${threads}|${input_tag}|${elapsed_s}s|$(numfmt --to=iec $out_size)|${ratio}:1|${speed}")
  echo -e "  ${GREEN}✓${RESET}  ${CYAN}${encoder}${RESET}  preset=${preset}  t=${threads}  (${input_tag})  →  ${YELLOW}${elapsed_s}s${RESET}  out=$(numfmt --to=iec $out_size)  ratio=${ratio}:1  speed=${speed}"
  return 0
}

# ────────────────────────────────────────────────────────────
# PHASE 3 — SINGLE CHUNK BENCHMARKS (init+chunk, ~2s of video)
# ────────────────────────────────────────────────────────────
echo -e "${BOLD}[ BENCHMARKS — SINGLE CHUNK TEST  (~2s clip) ]${RESET}"
echo ""

echo -e "  ${BOLD}${CYAN}CPU H.264 · thread sweep @ veryfast  [prod preset]${RESET}"
for t in 1 2 4 $CPU_CORES; do
  run_bench "CPU-H264" "libx264" "H.264" "veryfast" "$t" "$SINGLE_CHUNK_VALID" "chunk" "-c:v libx264"
done
echo ""

echo -e "  ${BOLD}${CYAN}CPU H.264 · preset sweep @ auto threads${RESET}"
for preset in ultrafast superfast veryfast fast medium; do
  run_bench "CPU-H264" "libx264" "H.264" "$preset" "auto" "$SINGLE_CHUNK_VALID" "chunk" "-c:v libx264"
done
echo ""

echo -e "  ${BOLD}${BLUE}CPU H.265 · preset sweep @ auto threads${RESET}"
for preset in ultrafast superfast veryfast fast; do
  run_bench "CPU-H265" "libx265" "H.265" "$preset" "auto" "$SINGLE_CHUNK_VALID" "chunk" "-c:v libx265"
done
echo ""

if $NVENC_AVAILABLE; then
  echo -e "  ${BOLD}${GREEN}GPU H.264 · h264_nvenc · preset sweep${RESET}"
  for preset in fast medium slow; do
    run_bench "GPU-H264" "h264_nvenc" "H.264" "$preset" "gpu" "$SINGLE_CHUNK_VALID" "chunk" "-c:v h264_nvenc"
  done
  echo ""
fi

if $H265_NVENC_AVAILABLE; then
  echo -e "  ${BOLD}${MAGENTA}GPU H.265 · hevc_nvenc · preset sweep${RESET}"
  for preset in fast medium slow; do
    run_bench "GPU-H265" "hevc_nvenc" "H.265" "$preset" "gpu" "$SINGLE_CHUNK_VALID" "chunk" "-c:v hevc_nvenc"
  done
  echo ""
fi

# ────────────────────────────────────────────────────────────
# PHASE 4 — MERGED FILE BENCHMARKS  (full session)
# ────────────────────────────────────────────────────────────
echo -e "${BOLD}[ BENCHMARKS — MERGED FILE  ($(numfmt --to=iec $MERGED_SIZE) · ${MERGED_DUR}s) ]${RESET}"
echo ""

echo -e "  ${BOLD}${CYAN}CPU H.264 · thread sweep @ veryfast  [prod preset]${RESET}"
for t in 1 2 4 $CPU_CORES; do
  run_bench "CPU-H264" "libx264" "H.264" "veryfast" "$t" "$MERGED_WEBM" "merged" "-c:v libx264"
done
echo ""

echo -e "  ${BOLD}${CYAN}CPU H.264 · preset sweep @ auto threads${RESET}"
for preset in ultrafast superfast veryfast fast medium; do
  run_bench "CPU-H264" "libx264" "H.264" "$preset" "auto" "$MERGED_WEBM" "merged" "-c:v libx264"
done
echo ""

echo -e "  ${BOLD}${BLUE}CPU H.265 · preset sweep @ auto threads${RESET}"
for preset in ultrafast superfast veryfast fast; do
  run_bench "CPU-H265" "libx265" "H.265" "$preset" "auto" "$MERGED_WEBM" "merged" "-c:v libx265"
done
echo ""

if $NVENC_AVAILABLE; then
  echo -e "  ${BOLD}${GREEN}GPU H.264 · h264_nvenc · preset sweep${RESET}"
  for preset in fast medium slow; do
    run_bench "GPU-H264" "h264_nvenc" "H.264" "$preset" "gpu" "$MERGED_WEBM" "merged" "-c:v h264_nvenc"
  done
  echo ""
fi

if $H265_NVENC_AVAILABLE; then
  echo -e "  ${BOLD}${MAGENTA}GPU H.265 · hevc_nvenc · preset sweep${RESET}"
  for preset in fast medium slow; do
    run_bench "GPU-H265" "hevc_nvenc" "H.265" "$preset" "gpu" "$MERGED_WEBM" "merged" "-c:v hevc_nvenc"
  done
  echo ""
fi

# ────────────────────────────────────────────────────────────
# RESULTS TABLE
# ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║                              BENCHMARK RESULTS                                          ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
printf "${BOLD}%-10s %-7s %-14s %-12s %-7s %-8s %-10s %-10s %-10s %-8s${RESET}\n" \
  "LABEL" "CODEC" "ENCODER" "PRESET" "THREADS" "INPUT" "TIME" "OUT SIZE" "RATIO" "SPEED"
echo -e "${DIM}──────────────────────────────────────────────────────────────────────────────────────────────${RESET}"

BEST_CHUNK_S="9999999"; BEST_MERGED_S="9999999"
for row in "${RESULTS[@]}"; do
  IFS='|' read -r _ _ _ _ _ input_tag elapsed _ _ _ <<< "$row"
  [[ "$elapsed" == "FAILED" ]] && continue
  t_num=$(echo "$elapsed" | tr -d 's')
  if [[ "$input_tag" == "chunk" ]]; then
    (( $(echo "$t_num < $BEST_CHUNK_S"  | bc -l) )) && BEST_CHUNK_S="$t_num"
  else
    (( $(echo "$t_num < $BEST_MERGED_S" | bc -l) )) && BEST_MERGED_S="$t_num"
  fi
done

LAST_INPUT=""
for row in "${RESULTS[@]}"; do
  IFS='|' read -r label codec_tag encoder preset threads input_tag elapsed out_size ratio speed <<< "$row"

  if [[ "$input_tag" != "$LAST_INPUT" ]]; then
    echo ""
    if [[ "$input_tag" == "chunk" ]]; then
      echo -e "  ${BOLD}${BLUE}▸ SINGLE CHUNK TEST${RESET}  ${DIM}init+${SINGLE_CHUNK_NAME}  $(numfmt --to=iec $(stat -c%s $SINGLE_CHUNK_VALID))${RESET}"
    else
      echo -e "  ${BOLD}${MAGENTA}▸ MERGED FILE${RESET}  ${DIM}${GOOD_COUNT} chunks · $(numfmt --to=iec $MERGED_SIZE) · ${MERGED_DUR}s${RESET}"
    fi
    echo -e "${DIM}──────────────────────────────────────────────────────────────────────────────────────────────${RESET}"
    LAST_INPUT="$input_tag"
  fi

  time_col="${RESET}"
  if [[ "$elapsed" == "FAILED" ]]; then
    time_col="${RED}"
  else
    t_num=$(echo "$elapsed" | tr -d 's')
    best_ref="$BEST_CHUNK_S"
    [[ "$input_tag" == "merged" ]] && best_ref="$BEST_MERGED_S"
    is_best=$(echo "$t_num <= ($best_ref * 1.10)" | bc -l)
    is_ok=$(  echo "$t_num <= ($best_ref * 1.50)" | bc -l)
    [[ "$is_best" == "1" ]]                    && time_col="${GREEN}${BOLD}"
    [[ "$is_best" != "1" && "$is_ok" == "1" ]] && time_col="${YELLOW}"
  fi

  case "$encoder" in
    libx264)    lc="${CYAN}"    ;;
    libx265)    lc="${BLUE}"    ;;
    h264_nvenc) lc="${GREEN}"   ;;
    hevc_nvenc) lc="${MAGENTA}" ;;
    *)          lc="${RESET}"   ;;
  esac

  printf "${lc}%-10s${RESET} %-7s %-14s %-12s %-7s %-8s ${time_col}%-10s${RESET} %-10s %-10s %-8s\n" \
    "$label" "$codec_tag" "$encoder" "$preset" "$threads" "$input_tag" \
    "$elapsed" "$out_size" "$ratio" "$speed"
done

echo ""
echo -e "${DIM}──────────────────────────────────────────────────────────────────────────────────────────────${RESET}"

# ── DIAGNOSTIC SUMMARY ───────────────────────────────────────
echo ""
echo -e "${BOLD}[ DIAGNOSTIC SUMMARY ]${RESET}"
echo ""

echo -e "  ${BOLD}WebM chunk format:${RESET}"
echo -e "  ${DIM}    chunk_000 = EBML init segment. chunk_001+ = Clusters with no header.${RESET}"
echo -e "  ${DIM}    Individual chunks are NOT valid standalone files — this is by design.${RESET}"
echo -e "  ${DIM}    Correct merge: cat chunk_*.webm > merged.webm  (binary concat)${RESET}"
echo -e "  ${DIM}    Production must cat-merge BEFORE calling ffmpeg — NOT per-chunk encode.${RESET}"
echo ""

if [[ $EMPTY_COUNT -gt 0 ]]; then
  echo -e "  ${YELLOW}[!] Empty/tiny chunks: ${EMPTY_COUNT}${RESET}  ${DIM}(skipped from merge)${RESET}"
  echo -e "  ${DIM}      These are normal: MediaRecorder emits a near-empty last chunk on stop.${RESET}"
  echo ""
fi

echo -e "  ${BOLD}Thread bottleneck:${RESET}"
echo -e "  ${DIM}    Compare libx264 veryfast t=1 vs t=${CPU_CORES} on merged.${RESET}"
echo -e "  ${DIM}    Same time → ffmpeg CPU-capped. Check: cat /sys/fs/cgroup/cpu.max${RESET}"
echo ""

if $NVENC_AVAILABLE; then
  echo -e "  ${BOLD}NVENC:${RESET}"
  echo -e "  ${DIM}    GPU·H264·fast vs CPU·H264·veryfast — expect 5–10× speedup on merged.${RESET}"
else
  echo -e "  ${YELLOW}[!] NVENC skipped — ffmpeg not compiled with NVENC.${RESET}"
  echo -e "  ${DIM}    libnvidia-encode IS present on this system.${RESET}"
  echo -e "  ${DIM}    Build ffmpeg from source with nv-codec-headers to enable it.${RESET}"
fi
echo ""

echo -e "  ${BOLD}Outputs:${RESET}  ${RESULTS_DIR}/"
echo -e "  ${DIM}  label_inputtype_encoder_preset_tThreads.mp4${RESET}"
echo ""
echo -e "${BOLD}${CYAN}  Completed: $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo ""