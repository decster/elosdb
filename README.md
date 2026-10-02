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

100M rows of `hits`, ClickBench's own driver and scripts, `elosdb v0.1.9` installed
from this repository's releases page on a fresh instance (nothing is compiled there;
the venue verifies the download's sha256 before the first timing):

| machine | load | data size | cold (sum of 43) | hot (sum of 43) | concurrent QPS |
|---|---:|---:|---:|---:|---:|
| c8g.4xlarge (Graviton4, 16 vCPU, 32 GiB) | 45.25 s | 7,668,470,504 B | 29.38 s | 2.00 s | 12.07 |
| c8g.metal-48xl (Graviton4, 192 vCPU, 384 GiB) † | 35.14 s | 7,668,470,469 B | 28.56 s | 0.89 s | 37.02 |
| c6a.4xlarge (AMD EPYC Zen 3, x86_64, 16 vCPU, 32 GiB) † | 82.71 s | 7,668,470,506 B | 37.09 s | 6.19 s | 4.21 |
| c6a.xlarge (AMD EPYC Zen 3, x86_64, 4 vCPU, 8 GiB) | 263.61 s | 7,668,470,712 B | 48.55 s | 16.58 s | 0.64 |
| c6a.large (AMD EPYC Zen 3, x86_64, 2 vCPU, 4 GiB) | 2,965.26 s | 7,668,470,802 B | 258.56 s | 222.32 s | 0.13 |
| GCP c4a-standard-32 (Axion, 32 vCPU, 128 GB, 2 TB Hyperdisk Balanced), in a 64 GB cgroup † | 34.03 s | 7,668,470,496 B | 14.12 s | 1.20 s | 28.81 |

The v0.1.9 assets were rebuilt from a newer revision on 2026-10-02 and replaced under
the same tag (aarch64 sha256 `928f2812…`, x86_64 `40981ca6…`). Rows marked † were
measured with the previous build (`0f69fac7…` / `1ec9f68b…`) and have not been re-run.
On c6a.large the 7.7 GB store does not fit in memory, so it is read from disk again
and again, which is why load and query times are much longer there.

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
parquet (35.7 GB snappy) in **71.1 s** including `sync`; the store is
**16,470,323,216 B**.

Each query: server restarted and OS page cache dropped, then three tries. Seconds:

| query | cold (first try) | hot (best of tries 2–3) |
|---|---:|---:|
| Q01 | 6.992 | 0.413 |
| Q02 | 0.603 | 0.030 |
| Q03 | 5.674 | 0.296 |
| Q04 | 4.813 | 0.266 |
| Q05 | 6.326 | 0.392 |
| Q06 | 4.784 | 0.045 |
| Q07 | 7.869 | 0.284 |
| Q08 | 7.884 | 0.184 |
| Q09 | 9.101 | 0.943 |
| Q10 | 5.792 | 0.385 |
| Q11 | 0.637 | 0.059 |
| Q12 | 7.443 | 0.144 |
| Q13 | 1.590 | 0.814 |
| Q14 | 5.418 | 0.110 |
| Q15 | 5.429 | 0.173 |
| Q16 | 0.446 | 0.188 |
| Q17 | 4.616 | 0.120 |
| Q18 | 3.212 | 0.311 |
| Q19 | 6.458 | 0.069 |
| Q20 | 5.910 | 0.292 |
| Q21 | 6.310 | 0.643 |
| Q22 | 0.758 | 0.156 |
| **sum** | **108.06** | **6.32** |

Q11 returns no rows: its `0.0001` fraction is the SF1 parameter (the spec scales it
to `0.0001 / SF`), and at SF100 no part passes it. The query still runs in full.

## Running it

    a=$(uname -m)                              # aarch64 or x86_64
    curl -fsSLO https://github.com/decster/elosdb/releases/download/v0.1.9/elosdb-v0.1.9-linux-$a
    sha256sum elosdb-v0.1.9-linux-$a           # compare against clickbench/install
    chmod +x elosdb-v0.1.9-linux-$a
    ./elosdb-v0.1.9-linux-$a --data-dir /path/to/store --port 5432
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
fetched from the same place as the file it describes proves nothing. v0.1.9's two
assets were rebuilt once, on 2026-10-01, before any result above was taken; the
digests pinned in `clickbench/install` are the current ones.
