# common.sh — the paths and the psql every other script in this directory uses.
#
# THE VARIABLE NAMES ARE `OLAB_*` AND THAT IS DELIBERATE. olab is the engine inside
# elosdb, and `load`, `query`, `check`, `stop`, `data-size`, `create.sql` and
# `queries.sql` in this directory are BYTE-IDENTICAL to the ones the engine repo
# measures its other deployments with — the gate there asserts it file by file,
# because two copies of a query set that agree today is how an A/B stops being an
# A/B. Everything a deployment is allowed to change is the binary and how it is
# built. Renaming a shell variable would have made this directory a fork of the
# query set instead of a second binary under it.
#
# elosdb is ONE FILE. There is no library to place beside it, no RUNPATH to get
# right and no C++ runtime to match: libstdc++ and libgcc are linked in, and it
# imports nothing newer than GLIBC_2.38. So "fetch, verify, chmod, run" is the whole
# install, and `start` cannot tell where the binary came from — a deployment that
# behaves differently depending on how its binary arrived is two deployments.
set -eu
OLAB_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLAB_BIN="${OLAB_BIN:-$OLAB_HOME/bin/elosdb}"
OLAB_PORT="${OLAB_PORT:-5432}"
# The server reads these two: `data/olab/canonical` is where `load`'s COPY writes
# and where `start` points --data-dir, so they are the store's address, not a label.
export OLAB_TIER=canonical OLAB_DATA="$OLAB_HOME/data"
# A `command -v psql` IS NOT A WORKING psql. A psql on PATH whose libpq is not on
# LD_LIBRARY_PATH exists, answers `command -v`, and then dies on every invocation
# with `libpq.so.5: cannot open shared object file`. So the probe RUNS it.
if ! psql --version >/dev/null 2>&1; then
  echo "elosdb: no working psql on PATH — ./install installs postgresql-client" >&2
  exit 1
fi
PSQL=(psql -X -h 127.0.0.1 -p "$OLAB_PORT" -U olab -d olab)
