# elosdb — the ClickBench submission

`elosdb` is a single-node analytical database: a C++ storage and execution engine
with its own column format, behind a Rust host that speaks the PostgreSQL v3 wire
protocol and keeps [DataFusion](https://datafusion.apache.org/) in the process as a
fallback frontend for statements the engine's own planner does not accept. All 43
ClickBench queries are answered by the engine; DataFusion answered none of the
2957 statements the published run sent it.

    c8g.4xlarge (Graviton4, 16 vCPU, 32 GiB), 100M rows, ClickBench's own driver

    combined  1.366    rank 1 of 77     (Umbra 1.838)
    hot       0.999    rank 1 of 81     (Umbra 1.253)
    cold      1.393    rank 1 of 77     (Umbra 1.942)
    load      61.0 s   data size 8,028,674,163 B (8.03 GB)   concurrent QPS 4.812

`hot`, `cold` and `combined` are the relative metrics ClickBench's own
`index.html` computes — a geomean of per-query ratios to the best result in the
field, `combined` weighting 10% load + 10% size + 20% cold + 60% hot. They are
quoted here against the c8g.4xlarge board, which is the board this result is on.
Thrown into the unfiltered submission list (every machine, every cluster size),
this run's predecessor on identical code scores `combined` 2.179, rank 3 of 947,
behind two Umbra entries on 192-vCPU metal.

## Installing it

These files are a ClickBench submission directory: copy them into a checkout of
[ClickHouse/ClickBench](https://github.com/ClickHouse/ClickBench) as `elosdb/`
(`benchmark.sh` invokes `../lib/benchmark-common.sh`, the driver every entry is
measured by), then:

    ./install        # downloads one file, verifies its sha256, installs psql
    ./benchmark.sh   # ClickBench's own driver

`install` compiles nothing. It fetches a single statically-linked executable from
[this repository's releases](https://github.com/decster/elosdb/releases) — the URL
and the sha256 are pinned in `install` itself, and a mismatch is a refusal, not a
warning. Point `ELOSDB_URL` elsewhere to run a different build; `ELOSDB_SHA256`
is then required with it.

**aarch64 only.** The published artifact is built `-mcpu=neoverse-v2` and refuses to
start on a CPU that reports no SVE2, because "built for this core" in a result
header has to mean it. `install` fails by name on any other architecture.

The binary needs `glibc >= 2.38` and nothing else — libstdc++ and libgcc are linked
in, there is no shared library to place beside it, and it exports zero global
dynamic symbols. `install` prints its `DT_NEEDED` list so you can see that:

    install: needs libgcc_s.so.1 libm.so.6 libc.so.6 ld-linux-aarch64.so.1

The other requirement is a `psql` to talk to it; `install` apt-gets
`postgresql-client` when it can and refuses by name when it cannot.

## What the scripts do

| | |
|---|---|
| `install` | fetch + verify the binary; make sure there is a psql |
| `start` | one server on 127.0.0.1:5432 — **no tuning flags**, see below |
| `load` | `create.sql`, then one `COPY hits FROM 'hits.parquet'` |
| `query` | a statement in on stdin, psql's `\timing` out on stderr — umbra's script, byte for byte |
| `data-size` | `du -bs` of the store directory |
| `stop` | SIGTERM, then wait, so the driver's `drop_caches` finds nothing holding the store mapped |

`tuned: no` is a claim `start` has to keep, so the only flags it passes are where to
listen and where the data is. Everything else the binary picks for itself: every
core, pinned `0..N-1`, 80% of what the cgroup allows the process as the memory
ceiling with 62.5% of that as the column cache.

`start` then waits for one line of the server's banner and **fails if it does not
arrive or says WARNING**. The line reports whether large allocations got 2 MB pages;
on the Ubuntu 24.04 image the answer used to be no, and twelve of the 43 queries ran
3.45x slower with nothing else in the output saying so. A run that cannot make that
claim is not a run worth publishing, and a line that never arrives must not read as
a pass.

## The load is SQL, and the store is the measurement

`create.sql` is [umbra's](https://github.com/ClickHouse/ClickBench/blob/main/umbra/create.sql)
file plus four `ENCODING DICT+BLOCK` clauses, executed by elosdb as DDL. The `COPY`
is one statement over the whole parquet file, which is what lets the string
dictionaries be global and every column's encoding be priced on that column's own
values rather than on a sample. Nothing about the load is cached or pre-built: the
43 files under `data/olab/canonical/hits` are written inside the timed window.

8.03 GB is the whole 100M-row table, below the smallest in the field. The engine
prices five layouts per column (FOR+bitpack, run-length with both halves packed,
dictionary, FSST, dictionary+FSST), picks per column, and then picks again per
1024-row granule for a dictionary column's code stream.

## Provenance

The engine's source is not public yet; the released binary is the artifact. It is
built from one commit of a private repository, reproducibly on that box: three
successive builds have produced the same sha256. The release notes carry the digest,
`install` pins it, and the file is verified before it is executed.

    elosdb v0.1.0 · aarch64 · built -mcpu=neoverse-v2 against glibc 2.43,
    runs on glibc >= 2.38 · 130 MB · DataFusion 55.0.0
