# elosdb

A single-node analytical database: a C++ storage and execution engine with its own
column format, behind a Rust host that speaks the PostgreSQL v3 wire protocol.
[DataFusion](https://datafusion.apache.org/) sits in the same process as a fallback
frontend for statements the engine's own planner does not accept.

This repository publishes the **binary** and the **ClickBench submission**. The
engine source is not public yet.

> **This is a personal research / hobby / experiments project. Do not use it in
> production.** It is published so its benchmark results can be reproduced by
> anyone who wants to check it — not as a supported product. There is no
> stability guarantee, no upgrade path, no backups, no security review and no
> support; it holds one node's worth of data, in a format that may change
> without notice.
>
> Current limitations, among others:
>
> - **Single node only.** No distributed execution: no shuffle, no repartitioned or
>   broadcast joins across machines, no replication.
> - **A simple rule-based planner.** No cost model and no cardinality estimates; join
>   strategy and order come from fixed rules (a join whose build side has a unique key
>   becomes a lookup), not from statistics.
> - **Joins are the weak spot.** Key-to-unique-key joins are fast; other join shapes
>   take a slow materializing path, and statements the engine's planner does not
>   accept fall back to the embedded DataFusion, which is correct but much slower.
> - **No spilling.** Joins and aggregations run in memory; a query whose working set
>   exceeds the memory limit fails instead of spilling to disk.
> - **Load-and-query only.** Tables are created from Parquet (`CREATE TABLE … FROM
>   PARQUET`, `COPY … (FORMAT PARQUET)`) and are then read-only: no `INSERT`,
>   `UPDATE` or `DELETE`, no transactions, no CSV or other input formats.
> - **No authentication and no TLS.** Any client that can reach the port can query
>   it; run it on localhost or a trusted network.
> - **aarch64 with SVE2 only** (Graviton4 / Axion / Neoverse V2 class cores).

## ClickBench

100M rows of `hits`, ClickBench's own driver and scripts, `elosdb v0.1.7` installed
from this repository's releases page on a fresh instance (nothing is compiled there;
the venue verifies the download's sha256 before the first timing):

| machine | load | data size | cold (sum of 43) | hot (sum of 43) | concurrent QPS |
|---|---:|---:|---:|---:|---:|
| c8g.4xlarge (Graviton4, 16 vCPU, 32 GiB) | 43.85 s | 7,668,470,465 B | 30.08 s | 2.31 s | 8.15 |
| c8g.metal-48xl (Graviton4, 192 vCPU, 384 GiB) | 34.73 s | 7,668,470,465 B | 29.68 s | 1.00 s | 31.17 |
| GCP c4a-standard-32 (Axion, 32 vCPU, 128 GB, 2 TB Hyperdisk Balanced), in a 64 GB cgroup | 27.30 s | 7,668,470,487 B | 14.65 s | 1.42 s | 17.97 |

The c4a row is not a ClickBench-provisioned VM: the same scripts and ClickBench's own
driver, run by hand on a Google Cloud c4a-standard-32 with the whole run capped at
64 GB by a memory cgroup (the server sizes itself from the cgroup, not from the box).
On the two-socket 48xl the server defaults to one NUMA node's 96 cores.
Cold is each query's first try after a server restart and a dropped OS page cache;
hot is the best of the remaining two tries. Per-query times are in
[`clickbench/results/`](clickbench/results/), in ClickBench's JSON format. Cold
varies noticeably between instances of one machine type; hot much less.

See [`clickbench/`](clickbench/) for the submission and how to run it yourself.

## TPC-H

Scale factor 100 (600M `lineitem` rows), the 22 queries with the standard validation
parameters (DuckDB's `tpch_queries()` text), through `psql`/psycopg against one server
started with only `--port --data-dir --log`. The same GCP c4a-standard-32 (Axion,
32 vCPU, 128 GB, 2 TB Hyperdisk Balanced), run inside a 64 GB memory cgroup.

**Load**: eight `CREATE TABLE <t> FROM PARQUET '<t>.parquet'` statements from dbgen's
parquet (35.7 GB snappy) in **71.7 s** including `sync`; the store is
**16,470,323,216 B**.

Each query: server restarted and OS page cache dropped, then three tries. Seconds:

| query | cold (first try) | hot (best of tries 2–3) |
|---|---:|---:|
| Q01 | 6.463 | 0.411 |
| Q02 | 0.578 | 0.051 |
| Q03 | 6.238 | 0.287 |
| Q04 | 4.852 | 0.284 |
| Q05 | 6.307 | 0.397 |
| Q06 | 4.785 | 0.045 |
| Q07 | 7.754 | 0.287 |
| Q08 | 7.783 | 0.241 |
| Q09 | 10.313 | 0.936 |
| Q10 | 5.435 | 0.349 |
| Q11 | 0.630 | 0.057 |
| Q12 | 7.287 | 0.135 |
| Q13 | 1.588 | 0.829 |
| Q14 | 5.458 | 0.105 |
| Q15 | 5.323 | 0.168 |
| Q16 | 0.455 | 0.187 |
| Q17 | 4.550 | 0.337 |
| Q18 | 3.122 | 0.321 |
| Q19 | 6.547 | 0.072 |
| Q20 | 5.903 | 0.289 |
| Q21 | 6.464 | 0.961 |
| Q22 | 0.937 | 0.330 |
| **sum** | **108.77** | **7.08** |

Q11 returns no rows: its `0.0001` fraction is the SF1 parameter (the spec scales it
to `0.0001 / SF`), and at SF100 no part passes it. The query still runs in full.

## Running it

    curl -fsSLO https://github.com/decster/elosdb/releases/download/v0.1.7/elosdb-v0.1.7-linux-aarch64
    sha256sum elosdb-v0.1.7-linux-aarch64      # compare against the release notes
    chmod +x elosdb-v0.1.7-linux-aarch64
    ./elosdb-v0.1.7-linux-aarch64 --data-dir /path/to/store --port 5432
    psql -h 127.0.0.1 -p 5432 -U elosdb -d elosdb

One statically-linked file. It needs `glibc >= 2.38`, `libm`, `libgcc_s` and the
loader — nothing else — and it exports zero global dynamic symbols. **aarch64 with
SVE2 only**: it is built `-mcpu=neoverse-v2` and refuses to start on a core that
does not report SVE2, because "built for this core" in a published result header
has to mean it.

Tables are created and loaded in SQL:

```sql
CREATE TABLE hits (WatchID BIGINT NOT NULL, ..., URL TEXT NOT NULL, ...);
COPY hits FROM '/path/to/hits.parquet' (FORMAT PARQUET);
```

The encoder prices several layouts per column against that column's own values and
picks the cheapest. The ClickBench `create.sql` declares no per-column encoding.

## What is in the box

- **Its own column store.** One directory per table, one file per column, with the
  per-column layout chosen by pricing several encodings against that column's own
  values. ClickBench's 100M-row `hits` is 7.67 GB.
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
