# BikeStressScrolly Map Layer Calibration

## Background

Commits `3aa4f31` through `a9d5f6b` added more destinations and limited origins to
points within a 12-minute bike ride of each destination. This reduced the number of
origin-destination pairs from ~23,000 to ~9,000, producing flow values roughly
2.5× smaller across all layers. The maps looked lighter than before because the
interpolation breakpoints were still calibrated to the old, larger scale.

Commit `32d113af` made partial adjustments. This document records the final
calibration applied to restore the original visual weight.

---

## Flow scale comparison (old vs new data)

| Metric | Old data | New data | Ratio |
|--------|----------|----------|-------|
| `flow_unweighted` 50th %ile | 2,698 | 992 | 2.7× |
| `flow_unweighted` max | 116,674 | 50,474 | 2.3× |
| `flow_lts` 50th %ile | 2,326 | 927 | 2.5× |
| `flow_lts` max | 178,998 | 83,832 | 2.1× |
| Unavoidable `flow_lts` max | 54,860 | 23,799 | 2.3× |
| Avoided/unavoidable score max | 116,674 | 45,650 | 2.6× |

Old data taken from commit `a9d5f6b` (git worktree). Quantiles computed in R using `sf::read_sf`.

---

## Breakpoint changes applied

| Layer | Parameter | Old value | New value | Reason |
|-------|-----------|-----------|-----------|--------|
| **unweighted-flow** | color `values` | `c(100, 3000, 50000)` | `c(100, 1500, 30000)` | 1,500 ≈ 57th %ile; 30,000 ≈ 96th %ile, matching old percentile positions |
| **unweighted-flow** | width `values` | `c(10, 50000)` | `c(100, 30000)` | Consistent start; top at 96th %ile so major corridors reach full 6 px |
| **weighted-flow** | color `values` | `c(100, 5000, 80000)` | `c(100, 2000, 40000)` | Was never updated from old data; 2.5× rescale puts mid at 43rd %ile (same relative position as old) |
| **weighted-flow** | width `values` | `c(100, 80000)` | `c(100, 40000)` | Same 2.5× rescale |
| **unavoidable-stress** | width `values` | `c(100, 80000)` | `c(100, 25000)` | New max is 23,800 — old setting limited the widest segment to ~3 px; new top ≈ max |
| **avoided-unavoidable** | color `values` | `c(4000, 10000, 50000)` | `c(4000, 12000, 32000)` | Top stop (50,000) exceeded new max (45,650) so nothing reached full dark; old 50th %ile mapped to 90% of pale→mid, new 50th (11,693) now maps to 96% — nearly identical |

---

## Calibration method

Breakpoints were chosen to preserve the **percentile positions** of each stop
relative to the active data, not to apply a flat scale factor. For each layer:

1. Quantiles (50th, 75th, 90th, 95th, 99th, max) were extracted from both old
   and new filtered data.
2. Each existing stop was located at its percentile within the old distribution.
3. The new stop was set to the value at the same percentile in the new distribution.

The `weighted-flow` layer was not changed in `32d113af` and still had breakpoints
calibrated to old data roughly 2× larger than the new max; it received the largest
correction.

The filter thresholds (`flow_lts >= 350` for unavoidable, `score >= 4000` for
avoided/unavoidable) were set in `32d113af` and produce segment counts similar to
the old thresholds (1,020 and 1,261 rows vs 1,085 and 1,120 rows respectively),
so they were left unchanged.
