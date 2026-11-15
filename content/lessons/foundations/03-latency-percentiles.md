---
id: fnd-latency-percentiles
title: Latency distributions and percentiles
module: foundations
order: 3
minutes: 9
objective: Describe a service's latency with percentiles instead of an average, and predict how tail latency grows when one request fans out to many backends.
prereqs: []
concepts:
  - id: fnd-percentile-latency
    name: Latency percentiles
    def: The pth percentile latency is the response time that p percent of requests finish within; p50 is the median and p99 describes the slowest 1 percent.
  - id: fnd-tail-amplification
    name: Tail amplification under fan-out
    def: When one user request waits for many backend calls, the chance that at least one of them is slow grows with the number of calls, so backend tail latency becomes typical user latency.
sources:
  - ref: sre-book
    section: "Ch. 4 Service Level Objectives — Indicators in Practice (Aggregation)"
    url: https://sre.google/sre-book/service-level-objectives/
  - ref: sre-book
    section: "Ch. 6 Monitoring Distributed Systems — Worrying About Your Tail"
    url: https://sre.google/sre-book/monitoring-distributed-systems/
  - ref: tail-at-scale
    section: "Why Variability Exists; Component-Level Variability Amplified By Scale"
---
## Intuition

Ask ten people how long their commute takes and nine say "about twenty minutes" while one says "two hours, the bridge was closed". The average is thirty minutes — a number that describes nobody's morning. Request latency behaves the same way. Most requests are fast and a few are very slow, and the slow few are the ones users remember.

A percentile answers a more useful question than an average: *how long does it take for most requests to finish?* "p99 = 800 ms" means 99 out of 100 requests finished within 800 ms and one took longer.

## How it works

Take every request in a time window, sort by duration, and read off positions. The value halfway through is the **median (p50)**. The value 95% of the way through is **p95**, and so on. The upper percentiles — p99, p99.9 — are called the **tail**.

Latency distributions are usually *right-skewed*: there is a hard floor (a request cannot take less than zero time, and in practice not less than the network round trip) but no ceiling. Garbage-collection pauses, lock contention, a cold cache, a retransmitted packet, or a queue that briefly backed up all push individual requests far to the right. That long right tail drags the mean upward without telling you how many requests were affected.

Two properties of percentiles matter in practice:

- **You cannot average percentiles.** The p99 of two servers is not the average of their p99s; the slow server's requests dominate the combined tail. To combine, you need the underlying histograms (bucket counts add; percentiles do not).
- **Percentiles need enough samples.** With 200 requests in a window, p99.9 is not defined in any meaningful way, and p99 rests on two data points.

### Fan-out amplifies the tail

Suppose a page load calls *n* backends in parallel and must wait for all of them. If each backend independently has probability *q* of being slower than some threshold, the page is slow whenever *at least one* is slow:

`P(page slow) = 1 − (1 − q)^n`

With q = 1% and n = 100, that is 1 − 0.99^100 ≈ 63%. A latency that only 1 request in 100 experiences at each backend is experienced by most users of the page.

```diagram
flow
User request -> Frontend
Frontend -> Backend 1
Frontend -> Backend 2
Frontend -> Backend 3
Backend 1 --> Slowest wins: 12 ms
Backend 2 --> Slowest wins: 15 ms
Backend 3 --> Slowest wins: 900 ms
```

## Example

A hypothetical service handles 1,000 requests in one minute: 950 take about 20 ms, 40 take about 200 ms, and 10 take about 3,000 ms.

- Mean: (950×20 + 40×200 + 10×3000) / 1000 = 57 ms.
- p50: 20 ms. p95: 20 ms (the 950th request is still in the fast group). p99: 200 ms. p99.9: 3,000 ms.

The mean (57 ms) is nearly three times what a typical request sees and tells you nothing about the ten requests that took three seconds. The percentiles show the shape: most are fast, one in a hundred is ten times slower, one in a thousand is terrible.

## Why it matters

- **Objectives are written in percentiles.** A latency SLO has the form "99% of requests complete within 300 ms", because that is a statement about how many users are affected.
- **Heavy users hit the tail more often.** Someone who makes 100 requests in a session will probably see a p99 event at least once, and the heaviest users are often the most valuable ones.
- **Design decisions change tail behaviour.** Adding a fan-out step, a synchronous dependency, or a retry changes the tail much more than the median. Reasoning in percentiles lets you predict that before building it.

## Tradeoffs and limits

- Higher percentiles cost more to measure accurately (more samples, finer histogram buckets) and are noisier. Alerting on p99.99 of a low-traffic endpoint produces noise, not insight.
- A percentile hides everything beyond it. p99 = 200 ms is compatible with the remaining 1% taking 201 ms or 30 s. Track more than one percentile, or a histogram.
- Percentiles measured at the server miss time spent in client queues, connection setup, and retries. What the user feels can be much worse than the server's own numbers.
- The fan-out formula assumes independence. Real slowness is often correlated (a shared database is slow for everyone), which makes things better in some cases and worse in others; treat the formula as intuition, not a forecast.
- Chasing the tail has diminishing returns. Techniques such as hedged requests reduce it at the cost of extra load.

## Common misconceptions

- **"Average latency is 50 ms, so users see about 50 ms."** With a skewed distribution almost nobody sees the mean; most see less and a few see far more.
- **"p99 only matters to 1% of users."** It matters to 1% of *requests*. Users who make many requests, and any request that fans out, meet the tail far more often.
- **"Average the per-server p99s to get the fleet p99."** Percentiles do not average. Merge histograms, then compute the percentile.
- **"If p50 improved, the service got faster."** The median can improve while the tail gets worse, for example when a cache speeds up common requests but misses are slower.

## Worked scenario

A search frontend sends each query to 40 index shards in parallel and waits for all of them. Each shard answers within 50 ms for 99.5% of requests. The team's target is that 95% of user queries finish within 50 ms plus a small frontend overhead. Will it hold?

1. Per-shard probability of exceeding 50 ms: q = 0.005.
2. Probability all 40 are fast: 0.995^40 ≈ 0.818.
3. So about 18% of queries wait for at least one slow shard, and only about 82% meet the target — well short of 95%.
4. What per-shard tail would be needed? Solve (1 − q)^40 ≥ 0.95 → 1 − q ≥ 0.95^(1/40) ≈ 0.99872, so each shard must answer within 50 ms for about 99.87% of requests.
5. Options, each with a cost: improve the shard tail (hard), reduce fan-out (fewer, larger shards), return partial results after a deadline (lower quality for some queries), or send a duplicate request to another replica when one shard is slow (extra load).

The conclusion to carry forward: under fan-out, the backend percentile you must care about is much higher than the user-facing percentile you promise.

=== items ===
- id: fnd-percentile-latency-p1
  concept: fnd-percentile-latency
  pool: practice
  skill: recall
  format: free
  difficulty: 1
  prompt: |
    In your own words, what does "p99 latency is 400 ms" say about a service's requests — and what does it *not* tell you?
  hints:
    - Think about what fraction of requests is on each side of 400 ms.
    - What could the slowest 1% look like?
  model: |
    99% of requests in the measurement window completed within 400 ms; 1% took longer. It does not say how much longer that last 1% took (it could be 401 ms or 30 s), and it does not describe the typical request — that is what the median is for.
  rubric:
    - States that 99% of requests finished within 400 ms (or that 1% took longer)
    - Notes that nothing is known about how slow the remaining 1% are
  explanation: |
    A percentile is a position in the sorted list of durations. Everything beyond that position is invisible, which is why several percentiles or a histogram are tracked together.
- id: fnd-percentile-latency-p2
  concept: fnd-percentile-latency
  pool: practice
  skill: estimate
  format: numeric
  difficulty: 2
  prompt: |
    In one minute a service handles 2,000 requests: 1,900 take 10 ms, 80 take 100 ms, and 20 take 2,000 ms. What is the **mean** latency in milliseconds?
  assumptions: Hypothetical numbers chosen for easy arithmetic.
  hints:
    - Total time divided by number of requests.
    - 1900×10 + 80×100 + 20×2000, then divide by 2,000.
  answer: 33.5
  unit: ms
  tolerance: 0.03
  calc: "(1900*10 + 80*100 + 20*2000) / 2000"
  explanation: |
    (19,000 + 8,000 + 40,000) / 2,000 = 33.5 ms. The 20 slowest requests (1% of traffic) contribute 40,000 of the 67,000 total milliseconds, so the mean is more than three times the 10 ms that 95% of requests experience.
- id: fnd-percentile-latency-p3
  concept: fnd-percentile-latency
  pool: practice
  skill: diagnose
  format: mcq
  difficulty: 2
  prompt: |
    A dashboard shows per-server p99 latency for three servers: 80 ms, 90 ms and 900 ms. Each server takes one third of the traffic. A colleague reports the fleet p99 as "about 357 ms, the average". What is wrong with that?
  choices:
    - Percentiles cannot be averaged; with a third of traffic on the slow server, far more than 1% of all requests may exceed 357 ms, so the fleet p99 has to be computed from merged histograms.
    - Nothing; averaging is correct because the servers receive equal traffic.
    - The fleet p99 is always the maximum of the per-server p99s, so it is exactly 900 ms.
    - The fleet p99 is always the median of the per-server p99s, so it is 90 ms.
  answer: 0
  hints:
    - What does the slow server's distribution look like *below* its own p99?
  explanation: |
    A percentile summarises one distribution and discards the rest. The slow server might have 30% of its requests above 357 ms, in which case 10% of fleet traffic exceeds that value and the true fleet p99 is far higher. It is not necessarily 900 ms either — only the merged distribution can say. Histogram bucket counts can be added across servers; percentiles cannot.
- id: fnd-tail-amplification-p1
  concept: fnd-tail-amplification
  pool: practice
  skill: estimate
  format: numeric
  difficulty: 2
  prompt: |
    A request fans out to 20 backends in parallel and waits for all of them. Each backend independently exceeds 100 ms on 1% of calls. What percentage of requests wait longer than 100 ms because of at least one slow backend?
  assumptions: Assumes backend latencies are independent, which real systems only approximate.
  hints:
    - Compute the probability that all 20 are fast, then subtract from 1.
    - 0.99 raised to the power 20.
  answer: 18.2
  unit: "%"
  tolerance: 0.06
  calc: "(1 - pow(0.99, 20)) * 100"
  explanation: |
    P(all fast) = 0.99^20 ≈ 0.818, so about 18.2% of requests see at least one slow backend. A 1-in-100 event at the backend has become a nearly 1-in-5 event for users.
- id: fnd-tail-amplification-p2
  concept: fnd-tail-amplification
  pool: practice
  skill: explain
  format: free
  difficulty: 2
  prompt: |
    Explain why adding more parallel backend calls to a request tends to leave its median latency almost unchanged at first but makes its tail latency much worse.
  hints:
    - The request finishes when the *slowest* call finishes.
    - How does the chance of drawing at least one slow call change as you draw more?
  model: |
    A request that waits for all calls takes as long as its slowest call. Each call is usually fast, but each one is another chance to hit a rare slow response. With n independent calls the chance that at least one is slow is 1 − (1 − q)^n, which grows quickly with n. So rare backend slowness becomes common request slowness, while the common case (all calls fast) still looks like a single fast call.
  rubric:
    - Says the request's latency is set by the slowest of the parallel calls
    - Explains that each extra call adds another independent chance of a slow response, so the probability of at least one grows with n
    - Connects this to the tail growing while the typical case stays fast
  explanation: |
    Taking a maximum over many samples pulls the result toward the tail of the underlying distribution. This is the mechanism behind "tail at scale".
- id: fnd-percentile-latency-a1
  concept: fnd-percentile-latency
  pool: assess
  skill: diagnose
  format: free
  difficulty: 3
  prompt: |
    After a release that added a result cache, the team reports: "median latency fell from 40 ms to 8 ms, so the release is a success." Support tickets about slow pages went *up*. Give a plausible explanation and say which measurements you would look at to confirm it.
  model: |
    The cache made the common (hit) path much faster, which moved the median, but requests that miss now do extra work (cache lookup, then the original path, then a cache write) or hit a backend that is slower when cold, so the tail got worse. Users who hit misses — or pages that make several requests, one of which misses — see slower responses than before. To confirm: compare p95/p99/p99.9 before and after, split latency by cache hit versus miss, and look at the hit ratio and the latency histogram rather than a single number.
  rubric:
    - Recognises that the median can improve while the tail gets worse
    - Gives a mechanism tied to the change (misses are slower or do extra work)
    - Proposes looking at high percentiles or the full distribution
    - Proposes splitting by hit versus miss (or another dimension that isolates the slow group)
  explanation: |
    One percentile cannot describe a distribution. A change that helps the common case and hurts the rare case shows up as an improved median and a degraded tail.
- id: fnd-tail-amplification-a1
  concept: fnd-tail-amplification
  pool: assess
  skill: estimate
  format: numeric
  difficulty: 3
  prompt: |
    A checkout page calls 5 services in parallel and needs all 5 answers. The page must load within the services' latency budget for at least 99% of loads. Assuming independence, what percentage of calls must each service complete within budget? Give the percentage to one decimal place.
  assumptions: Independence between services is assumed for the estimate.
  answer: 99.8
  unit: "%"
  tolAbs: 0.06
  calc: "pow(0.99, 1/5) * 100"
  explanation: |
    All five must be fast: p^5 ≥ 0.99, so p ≥ 0.99^(1/5) ≈ 0.99799, about 99.8%. Each dependency needs a tighter percentile than the page promises; a per-service "99%" would give only 0.99^5 ≈ 95.1% for the page.
