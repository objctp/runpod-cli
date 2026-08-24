# rp hub
Search the Hub marketplace and read a listing.
The Hub is the catalogue of ready-made repositories that deploy as serverless
endpoints. Both verbs are read-only and GraphQL-backed — API v2 has no
marketplace path. The write half already moved: pass a listing id to
`rp serverless create --hub-id` and the deploy goes over v2.

```
rp hub <verb> [flags]
```

## Commands

- [`rp hub search`](hub-search.md) — Search Hub listings by keyword.
- [`rp hub list`](hub-list.md) — Browse all Hub listings, filtered and ordered.
- [`rp hub get`](hub-get.md) — Show one Hub listing: release, image and config.
