# Runbook — AWS Route 53 / Registrar decommission

**Date authored:** 2026-05-03
**Discipline:** [`dev_framework_exceptions.md`](../framework_exceptions/dev_framework_exceptions.md) EX-001 §rule #2 (runbook-before-action). This runbook lands on `main` BEFORE the destructive operations execute.
**Operator:** David Strom (the user) — Claude executes the AWS CLI in this session under the user's `~/.aws/credentials`.

## Goal

Remove orphan + unused Route 53 hosted zones; stop auto-renewal on three Amazon Registrar domains being decommissioned. Keep `wordpressapis.com` fully intact — its MX record routes mail to `my.draglabs.com` (this Cloudron instance), which is in active use.

## Pre-state (snapshot)

Full record sets for every R53 hosted zone are captured at [`docs/snapshots/r53-2026-05-03/`](../snapshots/r53-2026-05-03/) — eight JSON files, one per zone, complete enough to recreate any zone if rollback is needed.

| Domain | Zone ID | Records | Live NS | Disposition |
|---|---|---:|---|---|
| draglabs.com | Z10301161KF5UPPHPL8MW | 38 | Cloudflare (live elsewhere) | **Delete** R53 zone (orphan; GoDaddy → Cloudflare is the actual chain) |
| conectatec.co | Z0223193SUM5L6FZ4I4N | 11 | (none — domain unreachable) | **Delete** R53 zone |
| clickgrande.com | Z10177892074NQBVRCL5J | 15 | (none — domain unreachable) | **Delete** R53 zone |
| dongatotienda.com | Z01118842YFJURRB4EDLO | 4 | (none — domain unreachable) | **Delete** R53 zone |
| micajitadeamor.com | Z01627001DYJW6EDR24LM | 11 | R53 (live) | **Delete** R53 zone + disable auto-renew at Amazon Registrar |
| tantratimer.com | Z016834810LMS98Q352VL | 7 | R53 (live) | **Delete** R53 zone + disable auto-renew at Amazon Registrar |
| micajita.co | Z037774026MRZ63QX60EI | 9 | R53 (live) | **Delete** R53 zone + disable auto-renew at Amazon Registrar |
| **wordpressapis.com** | **Z02862042VX34QNBFIVDR** | **8** | **R53 (live)** | **KEEP** — MX → `my.draglabs.com`, mail in use |

## Action set

### A — Disable auto-renew on Amazon Registrar (3 domains)

Reversible. The domain stays registered until expiry; auto-renew can be re-enabled before the expiry date.

```bash
for d in micajita.co micajitadeamor.com tantratimer.com; do
  aws route53domains disable-domain-auto-renew --region us-east-1 --domain-name "$d"
done
```

**DO NOT include `wordpressapis.com`** in this loop.

### B — Delete records (non-NS / non-SOA) and the hosted zones (7 zones)

R53 requires zones to contain only the apex NS + SOA before `delete-hosted-zone` will succeed. For each zone in the kill list, build a change-batch from its snapshot file that deletes every non-NS, non-SOA record, apply it, wait for propagation, then delete the zone.

```bash
zone_pairs=(
  "conectatec.co=Z0223193SUM5L6FZ4I4N"
  "clickgrande.com=Z10177892074NQBVRCL5J"
  "draglabs.com=Z10301161KF5UPPHPL8MW"
  "dongatotienda.com=Z01118842YFJURRB4EDLO"
  "micajitadeamor.com=Z01627001DYJW6EDR24LM"
  "tantratimer.com=Z016834810LMS98Q352VL"
  "micajita.co=Z037774026MRZ63QX60EI"
)
for pair in "${zone_pairs[@]}"; do
  domain="${pair%%=*}"
  zid="${pair##*=}"
  snap="docs/snapshots/r53-2026-05-03/${domain}.json"
  batch_file=$(mktemp)
  jq '{Changes: [.ResourceRecordSets[] | select(.Type != "NS" and .Type != "SOA") | {Action:"DELETE", ResourceRecordSet: .}]}' "$snap" > "$batch_file"
  count=$(jq '.Changes | length' "$batch_file")
  if [ "$count" -gt 0 ]; then
    change_id=$(aws route53 change-resource-record-sets --hosted-zone-id "$zid" --change-batch "file://$batch_file" --query 'ChangeInfo.Id' --output text)
    aws route53 wait resource-record-sets-changed --id "$change_id"
  fi
  rm "$batch_file"
  aws route53 delete-hosted-zone --id "$zid"
done
```

**`wordpressapis.com` (Z02862042VX34QNBFIVDR) is NOT in `zone_pairs`.**

### C — Verify

```bash
aws route53 list-hosted-zones --output json | jq '.HostedZones[] | {Name, Id}'
# Expect: only wordpressapis.com
aws route53domains list-domains --region us-east-1 --output json | jq '.Domains[] | {DomainName, AutoRenew}'
# Expect: AutoRenew=true only on wordpressapis.com
for d in conectatec.co clickgrande.com draglabs.com dongatotienda.com micajitadeamor.com tantratimer.com micajita.co; do
  echo "$d: $(dig @8.8.8.8 NS $d +short | tr '\n' ' ')"
done
# Expect: no awsdns nameservers in any answer
```

## Rollback

- **Zones:** recreate from snapshot JSON. Procedure: `aws route53 create-hosted-zone --name <domain> --caller-reference <uuid>`, then build a change-batch UPSERTing every record from the snapshot. Slow and manual but the data is preserved.
- **Auto-renew:** `aws route53domains enable-domain-auto-renew --domain-name <domain> --region us-east-1`. Re-enable before the domain's expiry date (in `aws route53domains list-domains` output).
- **DNS propagation:** zone deletion takes effect at R53 immediately; world-side caches expire per the prior records' TTLs (typically minutes to hours).

## Out of scope (handle separately)

- **Other registrars.** `conectatec.co`, `clickgrande.com`, `dongatotienda.com` are not in Amazon Registrar — they're at GoDaddy or other third parties (or already lapsed). User must cancel renewal at the actual registrar separately if any are still active.
- **`draglabs.com` registration + Cloudflare DNS.** Untouched by this runbook. We are deleting only the orphan R53 hosted zone.
- **S3 bucket cleanup.** Five buckets remain on AWS; only `sellersshield-cloudron-backup` is unambiguously a backup destination. Disposition for the other four (`cloudron-extended-storage`, `aws-cloudtrail-logs-...`, `ethos-dl`, `remote-public-sync`) requires separate per-bucket investigation.
- **Contabo backup migration.** Tracked under separate effort; user is mid-wizard at runbook-author time.
- **Cloudron mail audit.** Whether `wordpressapis.com` aliases on Cloudron are actually being used is a separate question.

## Expected post-state cost effect

| Item | Before | After |
|---|---|---|
| R53 hosted zones | 8 × $0.50/mo = $4/mo | 1 × $0.50/mo = $0.50/mo |
| Amazon Registrar renewals (next 12 mo) | 4 × ~$15 = ~$60 | 1 × ~$15 = ~$15 (`wordpressapis.com` only, due Aug 2026) |
| Annualized savings | — | ~$87/year once lapses complete (Jan 2027 / Apr 2027) |
