#!/bin/sh
# RUNROLL - the "JCL" for the nightly rollup on finance-batch-01.
#
# On a mainframe this would be a JOB card + EXEC PGM=ROLLUP with DD statements.
# Here the DD names map to environment variables that GnuCOBOL's runtime reads
# (dialect: -fimplicit-external), and the steps run in sequence with a
# condition check between them (the COBOL equivalent of COND=(0,NE)).
set -e

BASE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-/var/batch/scoreboard}"
COBC="${COBC:-cobc}"

export SCOREIN="${WORK}/in/scores.dat"
export TEAMOUT="${WORK}/out/team-totals.dat"
export RPTOUT="${WORK}/out/rollup-report.txt"

echo "STEP010 COMPILE"
"$COBC" -x -std=default -fixed \
    -I "${BASE}/copybooks" \
    -o "${WORK}/ROLLUP" \
    "${BASE}/src/ROLLUP.cbl"

echo "STEP020 STAGE INPUT"
mkdir -p "${WORK}/in" "${WORK}/out"
if [ ! -f "${SCOREIN}" ]; then
    cp "${BASE}/data/scores.dat" "${SCOREIN}"
fi

echo "STEP030 RUN ROLLUP"
"${WORK}/ROLLUP"
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "STEP030 FAILED RC=${RC} - skipping publish"
    exit "$RC"
fi

echo "STEP040 PUBLISH"
aws s3 cp "${TEAMOUT}" "s3://fbctf-demo-artifacts-337058058699-use1/batch/team-totals-$(date -u +%Y%m%d).dat" || true
cat "${RPTOUT}"
