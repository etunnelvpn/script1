#!/bin/bash
# ================================================================
#  E-TUNNEL VPN — Build Script
#  Compiles etunnel-v1.0.0.sh into a binary using shc
#  Run this on a Ubuntu 22.04 x86_64 machine (your build server)
#  Output: etunnel-binary (upload this to GitHub, keep source private)
# ================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

SOURCE="etunnel-v1.0.0.sh"
OUTPUT="etunnel"
EXPIRY_DAYS=36500   # Set to e.g. 365 for 1-year expiry

echo -e "${CYAN}"
echo "  +-------------------------------------------------+"
echo "  |   E-TUNNEL VPN — SHC Build Tool                |"
echo "  |   By EMMKASH TECH                              |"
echo "  +-------------------------------------------------+"
echo -e "${NC}"

# ── 1. Check source file exists ──────────────────────────────
if [ ! -f "$SOURCE" ]; then
    echo -e "${RED}[!] Source file not found: $SOURCE${NC}"
    echo -e "    Place this script in the same folder as $SOURCE"
    exit 1
fi
echo -e "${GREEN}[✓]${NC} Source: $SOURCE"

# ── 2. Install shc if missing ────────────────────────────────
if ! command -v shc >/dev/null 2>&1; then
    echo -e "${YELLOW}[~]${NC} Installing shc..."
    apt-get update -qq && apt-get install -y shc 2>/dev/null || \
    yum install -y shc 2>/dev/null || \
    { echo -e "${RED}[!] Could not install shc. Install manually: apt-get install shc${NC}"; exit 1; }
fi
echo -e "${GREEN}[✓]${NC} shc is available: $(shc -v 2>&1 | head -1)"

# ── 3. Compile with shc ──────────────────────────────────────
echo -e "${YELLOW}[~]${NC} Compiling..."

# -f = source file
# -o = output binary name
# -r = allow to run on a different host than the host it was compiled on
# -T = allow binary to be traceable (remove for extra security, but causes issues on some VPS)
# -e = expiry date (optional)
EXPIRY_DATE=$(date -d "+${EXPIRY_DAYS} days" +%d/%m/%Y 2>/dev/null || \
              date -v "+${EXPIRY_DAYS}d"      +%d/%m/%Y 2>/dev/null || \
              echo "")

if [ -n "$EXPIRY_DATE" ]; then
    echo -e "  Expiry set to: ${YELLOW}${EXPIRY_DATE}${NC}"
    shc -r -f "$SOURCE" -o "$OUTPUT" -e "$EXPIRY_DATE" 2>/dev/null
else
    shc -r -f "$SOURCE" -o "$OUTPUT" 2>/dev/null
fi

# shc also creates a .x.c file (C source) — remove it
rm -f "${SOURCE}.x.c" 2>/dev/null

# ── 4. Verify output ─────────────────────────────────────────
if [ ! -f "$OUTPUT" ]; then
    echo -e "${RED}[!] Compilation failed — binary not created${NC}"
    echo -e "    Try: shc -r -f $SOURCE -o $OUTPUT"
    exit 1
fi

chmod +x "$OUTPUT"
SIZE=$(du -sh "$OUTPUT" | cut -f1)
echo -e "${GREEN}[✓]${NC} Binary created: ${CYAN}$OUTPUT${NC} (${SIZE})"

# ── 5. Test the binary runs ───────────────────────────────────
echo -e "${YELLOW}[~]${NC} Testing binary..."
if ./"$OUTPUT" --version 2>/dev/null | grep -q "E-TUNNEL" || \
   file "$OUTPUT" | grep -q "ELF"; then
    echo -e "${GREEN}[✓]${NC} Binary is valid ELF executable"
else
    echo -e "${YELLOW}[~]${NC} Binary created (run test: ./$OUTPUT)"
fi

# ── 6. Summary ───────────────────────────────────────────────
echo ""
echo -e "${GREEN}  +-------------------------------------------------+"
echo -e "  |   BUILD COMPLETE                                |"
echo -e "  +-------------------------------------------------+${NC}"
echo ""
echo -e "  Binary    : ${CYAN}./$OUTPUT${NC}"
echo -e "  Upload to : ${CYAN}GitHub repo (etunnelvpn/script1)${NC}"
echo -e "  Keep private: ${YELLOW}$SOURCE${NC} — do NOT upload the source"
echo ""
echo -e "  Users install with:"
echo -e "  ${CYAN}curl -fsSL https://raw.githubusercontent.com/etunnelvpn/script1/main/etunnel -o /tmp/etunnel && bash /tmp/etunnel${NC}"
echo ""
echo -e "${YELLOW}  NOTE: This binary runs on Ubuntu/Debian x86_64.${NC}"
echo -e "${YELLOW}        Recompile on ARM64 if needed for ARM VPS.${NC}"
echo ""