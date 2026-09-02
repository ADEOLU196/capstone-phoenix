# Cost

## Monthly cost breakdown (us-east-1, on-demand)

| Item | Qty | Unit cost | Monthly |
|---|---|---|---|
| EC2 t3.small (control plane) | 1 | $0.0208/hr (~$15.18/mo) | $15.18 |
| EC2 t3.small (workers) | 2 | $0.0208/hr (~$15.18/mo) | $30.36 |
| EBS gp3 root volumes (~8GB default) | 3 | ~$0.64/mo per 8GB | ~$1.92 |
| EBS gp3 (Postgres PVC, 2Gi via local-path) | 1 | included in node's root volume (local-path provisioner uses node disk, not a separate EBS volume) | $0.00 |
| Data transfer (out, low volume) | - | first 100GB/mo free tier eligible on many accounts | ~$0-2 |
| S3 (Terraform remote state) | 1 bucket | negligible at this size | ~$0.02 |
| DynamoDB (Terraform state lock) | 1 table | on-demand, negligible at this usage | ~$0.01 |
| Route53 / domain | 0 | using nip.io (free) instead of a registered domain | $0.00 |
| Let's Encrypt certificate | - | free | $0.00 |

**Estimated total: ~$47-50/month**

## How to cut this in half

The single biggest line item is compute (3× t3.small ≈ $45.54/mo, ~95% of total spend). The most effective lever is compute, not storage or networking:

1. **Switch to Spot Instances for workers** (not the control plane, to avoid losing the API server to reclamation). Worker spot pricing for t3.small runs ~$0.0075/hr vs ~$0.0208/hr on-demand — roughly a 64% discount on 2 of the 3 nodes. Estimated saving: ~$19/month.
2. **1-year Reserved Instance / Savings Plan on the control plane** (the one node that must stay up continuously and isn't a spot candidate): ~$8.92/mo vs $15.18/mo on-demand — saves ~$6/month with no upfront, or more with partial/full upfront.
3. **Combined**, these two changes bring the ~$45.54/mo compute cost down to roughly ~$20/mo, cutting total infrastructure cost by more than half, with the trade-off that spot workers can be reclaimed with 2 minutes' notice — acceptable here since the app already tolerates node loss (PodDisruptionBudgets, anti-affinity, HPA), which is exactly the capability this capstone builds.

A smaller additional saving: downsizing the two workers back toward `t3.micro` once CPU-credit exhaustion is mitigated (e.g. via `t3.micro` reserved concurrency limits or unlimited burst mode with a cost cap) — not pursued here after the CPU starvation issue this build hit firsthand (see `RUNBOOK.md`), but viable for lower-traffic workloads with careful monitoring.
