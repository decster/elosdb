# elosdb — ClickBench submission

`elosdb` is a single-node analytical database: a C++ storage and execution engine
with its own column format, behind a server that speaks the PostgreSQL v3 wire
protocol. All 43 ClickBench queries are answered by the engine.

> It is a personal research / hobby / experiments project, published so this
> result can be reproduced — **not for production use**.

    c8g.4xlarge (Graviton4, 16 vCPU, 32 GiB), 100M rows, ClickBench's own driver

    combined  1.388    rank 1 of 77     (next: Umbra 1.838)
    hot       1.008    rank 1 of 81     (next: Umbra 1.253)
    cold      1.477    rank 1 of 77     (next: Umbra 1.942)
    load      59.8 s   data size 8.03 GB   concurrent QPS 3.822

`hot`, `cold` and `combined` are the relative metrics ClickBench's own `index.html`
computes — a geomean of per-query ratios against the best result in the field,
`combined` weighting 10% load + 10% size + 20% cold + 60% hot — quoted against the
c8g.4xlarge board this result is on.

## Running it

Copy this directory into a checkout of
[ClickHouse/ClickBench](https://github.com/ClickHouse/ClickBench) as `elosdb/`, then:

    ./install        # downloads one file, verifies its sha256, installs psql
    ./benchmark.sh   # ClickBench's own driver

`install` compiles nothing. It fetches one statically-linked executable from
[this repository's releases](https://github.com/decster/elosdb/releases); the URL and
its sha256 are pinned in `install` itself and a mismatch is a refusal. Set
`ELOSDB_URL` (with `ELOSDB_SHA256`) to run a different build.

**aarch64 only**, and the artifact names its core: it is built `-mcpu=neoverse-v2`
and refuses to start where SVE2 is absent. It needs `glibc >= 2.38` and nothing
else — libstdc++ and libgcc are linked in, there is no shared library to place
beside it, and it exports no global dynamic symbols. The other requirement is a
`psql`, which `install` apt-gets.

## The scripts

| | |
|---|---|
| `install` | fetch + verify the binary; make sure there is a working psql |
| `start` | one server on 127.0.0.1:5432 — no tuning flags |
| `load` | `create.sql`, then one `COPY hits FROM 'hits.parquet'` |
| `query` | a statement in on stdin, psql's `\timing` out on stderr |
| `data-size` | `du -bs` of the store directory |
| `stop` | SIGTERM, then wait, so `drop_caches` finds nothing holding the store mapped |

`tuned: no` is a claim `start` has to keep, so its only flags are the port and the
data directory; every other setting is the binary's own default. `create.sql` is
[umbra's](https://github.com/ClickHouse/ClickBench/blob/main/umbra/create.sql) file
plus four `ENCODING` clauses, and `queries.sql` is umbra's unchanged. The store is
built inside the timed load window — nothing is cached or pre-computed.
