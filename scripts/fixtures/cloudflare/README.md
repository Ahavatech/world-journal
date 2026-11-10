# Cloudflare range fixtures

TEST DATA for `scripts/test-cloudflare-ips.sh`. The `good` ranges are a snapshot used only to exercise the parser and are **not authoritative**: `scripts/update-cloudflare-ips.sh` fetches the live lists from `https://www.cloudflare.com/ips-v4` and `/ips-v6` at provision time and weekly. The other directories hold deliberately broken content (empty, an HTML error page, an invalid address, too few lines, a `/0` range).
