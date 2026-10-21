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
> - **Two CPU targets only**: aarch64 with SVE2 (Graviton4 / Axion / Neoverse V2 class
>   cores) and x86_64 with AVX2/FMA/BMI2 (x86-64-v3: AMD Zen 3 / Intel Haswell and newer).

## ClickBench

100M rows of `hits`, ClickBench's own driver, scripts and VM image, `elosdb v0.1.12`
(the release `clickbench/install` pins) installed from this repository's releases page
on a fresh instance (nothing is compiled there; the download's sha256 is verified before
the first timing):

| machine | load | data size | cold (sum of 43) | hot (sum of 43) | concurrent QPS |
|---|---:|---:|---:|---:|---:|
| c8g.4xlarge (Graviton4, 16 vCPU, 32 GiB) | 47.73 s | 6,691,609,545 B | 27.07 s | 1.57 s | 12.11 |
| c8g.metal-48xl (Graviton4, 192 vCPU, 384 GiB) | 27.41 s | 6,691,609,506 B | 25.80 s | 0.59 s | 75.56 |

Cold is each query's first try after a server restart and a dropped OS page cache;
hot is the best of the remaining two tries. Cold varies noticeably between instances
of one machine type; hot much less. The server executes up to four statements at once,
each on at least 32 worker threads (the whole pool on a machine with 32 cores or fewer);
on the two-socket 48xl it uses one NUMA node's 96 cores. Per-query times are in
[`clickbench/results/20261021/`](clickbench/results/20261021/), in ClickBench's JSON format.

See [`clickbench/`](clickbench/) for the submission and how to run it yourself.

## TPC-H

Scale factor 100 (600M `lineitem` rows), the 22 queries with the standard validation
parameters (DuckDB's `tpch_queries()` text), through `psql`/psycopg against one elosdb
v0.1.12 server started with only `--port --data-dir --log`. The same GCP c4a-standard-32
(Axion, 32 vCPU, 128 GB, 2 TB Hyperdisk Balanced), run inside a 64 GB memory cgroup.

**Load**: eight `CREATE TABLE <t> FROM PARQUET '<t>.parquet'` statements from dbgen's
parquet (35.7 GB snappy) in **76.8 s** including `sync`; the store is
**15,066,989,019 B**.

Each query: server restarted and OS page cache dropped, then three tries. Seconds:

| query | cold (first try) | hot (best of tries 2–3) |
|---|---:|---:|
| Q01 | 6.482 | 0.152 |
| Q02 | 0.298 | 0.030 |
| Q03 | 4.053 | 0.273 |
| Q04 | 3.030 | 0.256 |
| Q05 | 4.624 | 0.378 |
| Q06 | 4.775 | 0.044 |
| Q07 | 7.690 | 0.291 |
| Q08 | 6.688 | 0.167 |
| Q09 | 8.419 | 0.833 |
| Q10 | 3.892 | 0.384 |
| Q11 | 0.380 | 0.056 |
| Q12 | 5.579 | 0.132 |
| Q13 | 1.318 | 0.807 |
| Q14 | 5.241 | 0.071 |
| Q15 | 4.857 | 0.117 |
| Q16 | 0.336 | 0.170 |
| Q17 | 4.458 | 0.115 |
| Q18 | 1.959 | 0.296 |
| Q19 | 5.438 | 0.069 |
| Q20 | 5.607 | 0.216 |
| Q21 | 4.597 | 0.624 |
| Q22 | 0.751 | 0.188 |
| **sum** | **90.47** | **5.67** |

Q11 returns no rows: its `0.0001` fraction is the SF1 parameter (the spec scales it
to `0.0001 / SF`), and at SF100 no part passes it. The query still runs in full.

## Running it

    a=$(uname -m)                              # aarch64 or x86_64
    curl -fsSLO https://github.com/decster/elosdb/releases/download/v0.1.12/elosdb-v0.1.12-linux-$a
    sha256sum elosdb-v0.1.12-linux-$a          # compare against clickbench/install
    chmod +x elosdb-v0.1.12-linux-$a
    ./elosdb-v0.1.12-linux-$a --data-dir /path/to/store --port 5432
    psql -h 127.0.0.1 -p 5432 -U elosdb -d elosdb

One statically-linked file. It needs `glibc >= 2.38`, `libm`, `libgcc_s` and the
loader — nothing else — and it exports zero global dynamic symbols. Each asset names
its core: the aarch64 one is built `-mcpu=neoverse-v2` and refuses to start on a core
that does not report SVE2; the x86_64 one is built `-march=x86-64-v3` and refuses on a
CPU without AVX2/FMA/BMI2 — because "built for this core" in a published result header
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
  values. ClickBench's 100M-row `hits` is 6.69 GB.
- **A scan that declines to read.** Block-level statistics prune both ways, and a
  block nothing will read is never decoded — so pruning is an I/O saving, not just
  a CPU one.
- **Aggregation built for many cores.** Group-by and COUNT(DISTINCT) run without a
  global merge phase, which is where a parallel aggregation usually spends its time.
- **PostgreSQL wire, simple and extended.** `psql`, psycopg3 and pgjdbc all connect.

## Releases

Each release is one file plus its `.sha256`. The digest is also pinned inside
`clickbench/install`, which verifies it before the file is ever executed — a digest
fetched from the same place as the file it describes proves nothing. The current
release is v0.1.12: aarch64 `ece4fca4…`, x86_64 `d9b49a7e…`.
