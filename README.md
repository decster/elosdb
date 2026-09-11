# elosdb

A single-node analytical database: a C++ storage and execution engine with its own
column format, behind a Rust host that speaks the PostgreSQL v3 wire protocol.
[DataFusion](https://datafusion.apache.org/) sits in the same process as a fallback
frontend for statements the engine's own planner does not accept.

This repository publishes the **binary** and the **ClickBench submission**. The
engine source is not public yet.

## ClickBench

`c8g.4xlarge` (Graviton4, 16 vCPU, 32 GiB), 100M rows, ClickBench's own driver:

| | elosdb | rank | next |
|---|---|---|---|
| `combined` | **1.376** | **1 of 77** | Umbra 1.838 |
| hot | **1.004** | **1 of 81** | Umbra 1.253 |
| cold | **1.431** | **1 of 77** | Umbra 1.942 |
| load | 60.1 s | | |
| data size | 8,028,674,163 B | smallest in the field | Umbra 8.30 GB |
| concurrent QPS | 3.208 | | |

Rank 1 on all three scored columns at once. The metrics are the relative geomeans
ClickBench's own `index.html` computes, against the c8g.4xlarge board.

Against the *unfiltered* submission list — every machine, every cluster size, tuned
and untuned — the same run scores `combined` **2.179, rank 3 of 947**, behind two
Umbra entries on 192-vCPU metal instances.

See [`clickbench/`](clickbench/) for the submission and how to run it yourself.

## Running it

    curl -fsSLO https://github.com/decster/elosdb/releases/download/v0.1.0/elosdb-v0.1.0-linux-aarch64
    sha256sum elosdb-v0.1.0-linux-aarch64      # compare against the release notes
    chmod +x elosdb-v0.1.0-linux-aarch64
    ./elosdb-v0.1.0-linux-aarch64 --data-dir /path/to/store --port 5432
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

- **Its own column store.** One directory per table, one mmap'd file per column,
  1024-row granules carrying the zone map, 65 536-row segments as the parallel grid.
  Per-column scheme selection over FOR+bitpack, packed run-length, dictionary, FSST
  and dictionary+FSST, and then a per-granule layout menu for a dictionary column's
  code stream. ClickBench's `hits` is 8.03 GB.
- **A scan that declines to read.** Zone maps prune both ways (a block that cannot
  match is skipped; a block that must match skips the filter), a top-N sink
  publishes its k-th key back to the scan as a bound, and a segment nothing will
  read is never decoded — so pruning is an I/O saving and not just a CPU one.
- **Aggregation without a merge phase.** Partitioned aggregation with the key in the
  record, a shared ticket table where that wins instead, COUNT(DISTINCT) as a radix
  partition, and a bounded per-worker preaggregation cache in front of the partition
  write, admitted by the store's exact distinct counts.
- **PostgreSQL wire, simple and extended.** `psql`, psycopg3 and pgjdbc all connect;
  bound parameters are rendered into the statement text, so a prepared statement
  takes the identical path a literal one does.

## Releases

Each release is one file plus its `.sha256`. The digest is also pinned inside
`clickbench/install`, which verifies it before the file is ever executed — a digest
fetched from the same place as the file it describes proves nothing.
