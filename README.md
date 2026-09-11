# elosdb

A single-node analytical database: a C++ storage and execution engine with its own
column format, behind a Rust host that speaks the PostgreSQL v3 wire protocol.
[DataFusion](https://datafusion.apache.org/) sits in the same process as a fallback
frontend for statements the engine's own planner does not accept.

This repository publishes the **binary** and the **ClickBench submission**. The
engine source is not public yet.

> **This is a personal research / hobby / experiments project. Do not use it in
> production.** It is published so the ClickBench result can be reproduced by
> anyone who wants to check it — not as a supported product. There is no
> stability guarantee, no upgrade path, no backups, no security review and no
> support; it holds one node's worth of data, in a format that may change
> without notice.

## ClickBench

`c8g.4xlarge` (Graviton4, 16 vCPU, 32 GiB), 100M rows, ClickBench's own driver:

| | elosdb | rank | next |
|---|---|---|---|
| `combined` | **1.388** | **1 of 77** | Umbra 1.838 |
| hot | **1.025** | **1 of 81** | Umbra 1.253 |
| cold | **1.431** | **1 of 77** | Umbra 1.942 |
| load | 58.0 s | | |
| data size | 8,028,674,586 B | smallest in the field | Umbra 8.30 GB |
| concurrent QPS | 3.638 | | |

Rank 1 on all three scored columns at once. The metrics are the relative geomeans
ClickBench's own `index.html` computes, against the c8g.4xlarge board.

The run that produced these numbers installed the `v0.1.3` release from this
repository's releases page on a fresh instance and compiled nothing. Five instances
of this engine have scored `combined` 1.376, 1.366, 1.388, 1.380 and 1.388 on
identical data — that ~0.02 band is the instance, not the engine — and the number
published here is the run of the scripts and the binary in this repository, not the
best of the five.

See [`clickbench/`](clickbench/) for the submission and how to run it yourself.

## Running it

    curl -fsSLO https://github.com/decster/elosdb/releases/download/v0.1.3/elosdb-v0.1.3-linux-aarch64
    sha256sum elosdb-v0.1.3-linux-aarch64      # compare against the release notes
    chmod +x elosdb-v0.1.3-linux-aarch64
    ./elosdb-v0.1.3-linux-aarch64 --data-dir /path/to/store --port 5432
    psql -h 127.0.0.1 -p 5432 -U elosdb -d elosdb

One statically-linked file. It needs `glibc >= 2.38`, `libm`, `libgcc_s` and the
loader — nothing else — and it exports zero global dynamic symbols. **aarch64 with
SVE2 only**: it is built `-mcpu=neoverse-v2` and refuses to start on a core that
does not report SVE2, because "built for this core" in a published result header
has to mean it.

Tables are created and loaded in SQL:

```sql
CREATE TABLE hits (WatchID BIGINT NOT NULL, ..., URL TEXT NOT NULL ENCODING DICT+BLOCK, ...);
COPY hits FROM '/path/to/hits.parquet' (FORMAT PARQUET);
```

`ENCODING` is a declaration, not a hint: the encoder otherwise prices five layouts
per column against that column's own values and picks the cheapest.

## What is in the box

- **Its own column store.** One directory per table, one file per column, with the
  per-column layout chosen by pricing several encodings against that column's own
  values. ClickBench's 100M-row `hits` is 8.03 GB.
- **A scan that declines to read.** Block-level statistics prune both ways, and a
  block nothing will read is never decoded — so pruning is an I/O saving, not just
  a CPU one.
- **Aggregation built for many cores.** Group-by and COUNT(DISTINCT) run without a
  global merge phase, which is where a parallel aggregation usually spends its time.
- **PostgreSQL wire, simple and extended.** `psql`, psycopg3 and pgjdbc all connect.

## Releases

Each release is one file plus its `.sha256`. The digest is also pinned inside
`clickbench/install`, which verifies it before the file is ever executed — a digest
fetched from the same place as the file it describes proves nothing.
