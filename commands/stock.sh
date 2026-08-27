#!/usr/bin/env bash
#
# Catalogue of GPU types, CPU flavours, and datacentres.
#
# Read-only lookups against the API v2 catalogue: what hardware exists, what it
# costs, and where it is in stock right now. The ids printed here are the ones
# `rp pod create` takes for --gpu, --cpu-flavor and --dc. Every column is v2
# REST bar the S3-API column of `rp stock dc`, which has no v2 field and stays
# on GraphQL.
#
# Usage: rp stock <verb> [flags]
#

_stock_gpu() {
  local product cloud cuda count q data vram stock_f cuda_f sort
  product="$(rp::args_get product "$RP_DEFAULT_PRODUCT")"
  product="${product^^}"
  cloud="$(rp::args_get cloud)"
  cloud="${cloud^^}"
  case "$cloud" in '' | SECURE | COMMUNITY) ;; *) rp::usage "invalid --cloud '$cloud' (expected SECURE|COMMUNITY)" ;; esac
  cuda="$(rp::args_get min-cuda)"
  [[ -z "$cuda" || "$cuda" =~ ^[0-9]+(\.[0-9]+)?$ ]] || rp::usage "invalid --min-cuda '$cuda' (expected major or major.minor, e.g. 12 or 12.1)"
  # Read raw and validate directly — not via rp::args_get_uint, which wraps
  # rp::require_uint inside $() and so swallows the usage exit when errexit is
  # off in tests. The direct call lets a non-integer / negative --min-count fail
  # fast and stay testable (the -ge 1 floor below already runs direct for that
  # reason). Mirrors the rp::require_* nameref-family rule in lib/args.sh.
  count="$(rp::args_get min-count)"
  rp::require_uint "$count" min-count
  [[ -z "$count" || "$count" -ge "$RP_STOCK_COUNT_MIN" ]] || rp::usage "--min-count must be >= $RP_STOCK_COUNT_MIN (got $count)"
  # Client-side display filters (the v2 catalogue does not filter rows on these).
  vram="$(rp::args_get vram-gb)"
  [[ -z "$vram" ]] && vram="$(rp::args_get vram)"
  [[ -z "$vram" ]] || rp::require_uint "$vram" vram-gb
  stock_f="$(rp::args_get stock)"
  if [[ -n "$stock_f" ]]; then
    stock_f="${stock_f^^}"
    case "$stock_f" in NONE | LOW | MEDIUM | HIGH) ;; *) rp::usage "invalid --stock '$stock_f' (expected NONE|LOW|MEDIUM|HIGH)" ;; esac
  fi
  cuda_f="$(rp::args_get cuda)"
  sort="$(rp::args_get sort)"
  if [[ -n "$sort" ]]; then
    sort="${sort^^}"
    case "$sort" in
    VRAM) sort=VRAM_GB ;;
    esac
    case "$sort" in
    ID | DISPLAY | VRAM_GB | CLOUD | SECURE_PRICE | COMMUNITY_PRICE | STOCK | CUDA) ;;
    *) rp::usage "invalid --sort '$sort' (expected one of ID, DISPLAY, VRAM_GB, CLOUD, SECURE_PRICE, COMMUNITY_PRICE, STOCK, CUDA)" ;;
    esac
  fi
  q="$(rp::query_params include AVAILABILITY product "$product" cloud "$cloud" minCudaVersion "$cuda" count "$count")"
  data="$(rp::http GET "/catalog/gpus$q" | rp::unwrap gpus)"
  # Drop junk rows the catalogue occasionally returns (e.g. id "unknown", 0 VRAM).
  data="$(printf '%s' "$data" | jq -c 'map(select(((.id // "") | ascii_upcase) != "UNKNOWN" and (.memory // 0) > 0))')"
  # --cloud filters rows (the API leaves the full set, so do it here).
  [[ -z "$cloud" ]] || data="$(printf '%s' "$data" | jq -c --arg c "$cloud" 'map(select(if $c == "SECURE" then .secure else .community end))')"
  [[ -z "$vram" ]] || data="$(printf '%s' "$data" | jq -c --argjson v "$vram" 'map(select(.memory >= $v))')"
  [[ -z "$stock_f" ]] || data="$(printf '%s' "$data" | jq -c --arg s "$stock_f" 'map(select((.availability // "") | ascii_upcase == $s))')"
  [[ -z "$cuda_f" ]] || data="$(printf '%s' "$data" | jq -c --arg c "$cuda_f" 'map(select(([.cudaVersions // [] | .[] | select(type == "object" and (.available // false))] | map(.version)) | index($c)))')"
  [[ -z "$sort" ]] || data="$(printf '%s' "$data" | jq -c --arg s "$sort" 'sort_by(
    if $s == "VRAM_GB" then (.memory // 0)
    elif $s == "SECURE_PRICE" then (.price.secure // 0)
    elif $s == "COMMUNITY_PRICE" then (.price.community // 0)
    elif $s == "STOCK" then ({NONE:0,LOW:1,MEDIUM:2,HIGH:3}[.availability] // 0)
    elif $s == "CUDA" then (([.cudaVersions // [] | .[] | select(type == "object" and (.available // false))] | map(.version | tostring | split(".") | map(tonumber))) | if length == 0 then [0] else max end)
    elif $s == "CLOUD" then (if .secure and .community then "SECURE, COMMUNITY" elif .secure then "SECURE" elif .community then "COMMUNITY" else "-" end)
    elif $s == "DISPLAY" then (.name // "")
    else (.id // "") end
  )')"
  # Display-only column hiding: --hide drops named columns from the table view
  # (it never filters rows or the --json payload). Comma-separated, case-insensitive.
  local -a cols hide_set kept c h hide_raw
  cols=(ID DISPLAY VRAM_GB CLOUD SECURE_PRICE COMMUNITY_PRICE STOCK CUDA DATACENTERS)
  hide_raw="$(rp::args_get hide)"
  if [[ -n "$hide_raw" ]]; then
    hide_set=()
    while IFS= read -r h; do
      h="${h// /}"
      [[ -n "$h" ]] || continue
      h="${h^^}"
      case "$h" in
      ID | DISPLAY | VRAM_GB | CLOUD | SECURE_PRICE | COMMUNITY_PRICE | STOCK | CUDA | DATACENTERS) hide_set+=("$h") ;;
      *) rp::usage "invalid --hide '$h' (expected one of ID, DISPLAY, VRAM_GB, CLOUD, SECURE_PRICE, COMMUNITY_PRICE, STOCK, CUDA, DATACENTERS)" ;;
      esac
    done < <(printf '%s\n' "$hide_raw" | tr ',' '\n')
    kept=()
    for c in "${cols[@]}"; do
      [[ " ${hide_set[*]} " == *" $c "* ]] && continue
      kept+=("$c")
    done
    ((${#kept[@]})) || rp::usage "cannot --hide every column"
    cols=("${kept[@]}")
  fi
  rp::emit_json_or "$data" rp::table "$data" \
    --reshape 'map({ID:.id, DISPLAY:.name, VRAM_GB:(.memory//0), CLOUD:(if .secure and .community then "SECURE, COMMUNITY" elif .secure then "SECURE" elif .community then "COMMUNITY" else "-" end), SECURE_PRICE:(if .secure then (.price.secure // "") else "-" end), COMMUNITY_PRICE:(if .community then (.price.community // "") else "-" end), STOCK:(.availability//""), CUDA:((( .cudaVersions // [] ) | map(if type == "object" then (if .available then (.version | tostring) else empty end) else empty end)) as $cv | if ($cv | length) == 0 then "-" elif ($cv | length) <= 2 then ($cv | join(", ")) else (($cv[0:2] | join(", ")) + " +" + (($cv | length) - 2 | tostring) + " more") end), DATACENTERS:((.dataCenters // [] | map(select((.availability // "") | ascii_upcase != "NONE")) | map(.id) | sort) as $dcs | if ($dcs | length) == 0 then "-" elif ($dcs | length) <= 2 then ($dcs | join(", ")) else (($dcs[0:2] | join(", ")) + " +" + (($dcs | length) - 2 | tostring) + " more") end)})' \
    "${cols[@]}"
}

_stock_cpus() {
  local data dc compact vcpu vcpu_jq product tier show_secure show_serverless
  compact="$(rp::args_has compact && printf true || printf false)"
  vcpu="$(rp::args_get vcpu)"
  if [[ -n "$vcpu" ]]; then
    vcpu="$(rp::args_get_uint vcpu)"
    ((vcpu >= 2)) || rp::usage "--vcpu must be >= 2"
    (((vcpu & (vcpu - 1)) == 0)) || rp::usage "--vcpu must be a power of two (2, 4, 8, …)"
  fi
  product="$(rp::args_get product)"
  if [[ -n "$product" ]]; then
    # The API is case-sensitive (product=serverless -> HTTP 422), so validate
    # each comma-separated token then send the uppercased value.
    local p_upper="${product^^}" tok ok=true
    local IFS=','
    for tok in $p_upper; do
      case "$tok" in POD | SERVERLESS | CLUSTER) ;; *)
        ok=false
        break
        ;;
      esac
    done
    [[ "$ok" == true ]] || rp::usage "invalid --product '$product' (expected POD|SERVERLESS|CLUSTER, comma-separated)"
    product="$p_upper"
    case "$p_upper" in
    SERVERLESS) tier=serverless ;;
    POD,SERVERLESS | SERVERLESS,POD) tier="" ;;
    *) tier=secure ;;
    esac
  else
    product="$RP_DEFAULT_PRODUCT"
    tier=""
  fi
  # Which price tier(s) to show. With --product the other tier is irrelevant, so
  # it is dropped (column and any flavour not offered on that tier).
  show_secure=true
  show_serverless=true
  [[ "$tier" == secure ]] && show_serverless=false
  [[ "$tier" == serverless ]] && show_secure=false

  data="$(rp::http GET "/catalog/cpus$(rp::query_params include AVAILABILITY product "$product")" | rp::unwrap cpus)"
  dc="$(rp::args_get dc)"
  if [[ -n "$dc" ]]; then
    data="$(printf '%s' "$data" | jq -c --arg dc "${dc^^}" 'map(select(([.dataCenters // [] | .[].id | ascii_upcase] | index($dc))))')"
  fi

  local dc_upper="${dc^^}"
  local common_reshape='
    def money($v): (($v * 1000 | round) / 1000 | tostring);
    def dcq: "'"$dc_upper"'";
    def keep($raw): (if ($raw == null or $raw == 0) then null else $raw end);
    def dcs_of: (.dataCenters // []);
    def stock_of($f): (if (dcq == "") then ($f.availability // "")
        else ((dcs_of | map(select(.id | ascii_upcase == dcq)) | .[0].availability) // ($f.availability // "")) end);
    def tier_filter($sr; $sl): (if ('$show_secure' == true and '$show_serverless' == false and $sr == null) then empty
        elif ('$show_serverless' == true and '$show_secure' == false and $sl == null) then empty
        else . end);
  '

  local cols=() full_reshape final
  if [[ "$compact" == true ]]; then
    cols=(ID NAME GROUP VCPU RAM_GB_VCPU)
    [[ "$show_secure" == true ]] && cols+=(SECURE_PRICE_VCPU)
    [[ "$show_serverless" == true ]] && cols+=(SERVERLESS_PRICE_VCPU)
    [[ -n "$dc" ]] && cols+=(STOCK)
    cols+=(DATACENTERS)
    full_reshape="$common_reshape"'
        [ .[] | . as $f
          | (keep($f.price.securePerVcpu // null)) as $sr
          | (keep($f.price.serverlessPerVcpu // null)) as $sl
          | (stock_of($f)) as $stock
          | tier_filter($sr; $sl)
          | {
              ID: $f.id,
              NAME: $f.name,
              GROUP: $f.group,
              VCPU: (($f.vcpu.min|tostring)+"-"+($f.vcpu.max|tostring)),
              RAM_GB_VCPU: ($f.ramGbPerVcpu // ""),
              SECURE_PRICE_VCPU: (if $sr == null then "-" else (money($sr) + "/vCPU") end),
              SERVERLESS_PRICE_VCPU: (if $sl == null then "-" else (money($sl) + "/vCPU") end),
              STOCK: $stock,
              DATACENTERS: ((dcs_of | map(.id) | sort) as $ids | if ($ids | length) == 0 then "-" elif ($ids | length) <= 2 then ($ids | join(", ")) else (($ids[0:2] | join(", ")) + " +" + (($ids | length) - 2 | tostring) + " more") end)
            }
        ]'
  else
    # Expanded view (default): one row per power-of-two vCPU size within each
    # flavour's valid range. RAM_GB and the price column(s) scale with the size
    # actually chosen by `rp pod create --cpu-flavor <ID> --vcpu <n>`.
    # STOCK is shown only with --dc (region-accurate); without it the global
    # aggregate is omitted to keep the table focused on reservable instances.
    vcpu_jq="${vcpu:-null}"
    cols=(FLAVOUR NAME GROUP VCPU RAM_GB)
    [[ "$show_secure" == true ]] && cols+=(SECURE_PRICE)
    [[ "$show_serverless" == true ]] && cols+=(SERVERLESS_PRICE)
    [[ -n "$dc" ]] && cols+=(STOCK)
    cols+=(DATACENTERS)
    full_reshape="$common_reshape"'
      [ .[] | . as $f
        | (keep($f.price.securePerVcpu // null)) as $sr
        | (keep($f.price.serverlessPerVcpu // null)) as $sl
        | (stock_of($f)) as $stock
        | tier_filter($sr; $sl)
        | ([2,4,8,16,32,64] | map(select(. >= ($f.vcpu.min // 2) and . <= ($f.vcpu.max // 32)))) as $sz
        | $sz[] as $s
        | {
            FLAVOUR: $f.id,
            NAME: $f.name,
            GROUP: $f.group,
            VCPU: $s,
            RAM_GB: ($s * ($f.ramGbPerVcpu // 0)),
            SECURE_PRICE: (if $sr == null then "-" else (money($s * $sr) + " (" + money($sr) + "/vCPU)") end),
            SERVERLESS_PRICE: (if $sl == null then "-" else (money($s * $sl) + " (" + money($sl) + "/vCPU)") end),
            STOCK: $stock,
            DATACENTERS: ((dcs_of | map(.id) | sort) as $ids | if ($ids | length) == 0 then "-" elif ($ids | length) <= 2 then ($ids | join(", ")) else (($ids[0:2] | join(", ")) + " +" + (($ids | length) - 2 | tostring) + " more") end)
          }
      ]
      | (if ('"$vcpu_jq"' != null) then map(select(.VCPU == '"$vcpu_jq"')) else . end)'
  fi

  # --json prints the raw flavour objects unchanged.
  if rp::args_has json; then
    printf '%s\n' "$data"
    return 0
  fi
  # A filtered-out set would otherwise render as a bare header; say so instead.
  final="$(printf '%s' "$data" | jq -c "$full_reshape")" || return 1
  if [[ "$(printf '%s' "$final" | jq 'length')" -eq 0 ]]; then
    rp::info "no CPU instances match the current filters (--dc/--product/--vcpu); try widening them"
    return 0
  fi
  rp::table "$final" --reshape '.' "${cols[@]}"
}

_stock_dc() {
  local dcs s3set filt shaped
  dcs="$(rp::http GET '/catalog/datacenters?include=GPU_AVAILABILITY,CPU_AVAILABILITY' | rp::unwrap dataCenters)"
  s3set="$(printf '%s\n' "$(_s3_dcs)" | jq -R 'select(length>0)' | jq -sc 'map(ascii_upcase)')"

  # Filter flags. --s3 / --global-network are bare bools; --volume-type and
  # --compliance are comma-separated allow-lists (keep a DC if it carries at least
  # one listed item, case-insensitive). The SAME filtered set feeds both the
  # --json payload and the reshaped table, so the two views never diverge.
  local s3f globalf vols comps regions
  s3f="$(rp::args_has s3 && printf true || printf false)"
  globalf="$(rp::args_has global-network && printf true || printf false)"
  vols="$(rp::split_csv "$(rp::args_get volume-type)" | jq -R 'select(length>0)' | jq -sc 'map(ascii_upcase)')"
  comps="$(rp::split_csv "$(rp::args_get compliance)" | jq -R 'select(length>0)' | jq -sc 'map(ascii_upcase)')"
  regions="$(rp::split_csv "$(rp::args_get region)" | jq -R 'select(length>0)' | jq -sc '
    map(ascii_upcase) |
    map(. as $t | (
      {NA:"NORTH_AMERICA", EU:"EUROPE", AS:"ASIA", SA:"SOUTH_AMERICA", ME:"MIDDLE_EAST", OC:"OCEANIA", AF:"AFRICA"}[$t] // $t
    ))')"

  filt="$(printf '%s' "$dcs" | jq -c \
    --argjson s3 "$s3set" --argjson s3f "$s3f" --argjson globalf "$globalf" \
    --argjson vols "$vols" --argjson comps "$comps" --argjson regions "$regions" '
    map(select(
      (.id | ascii_upcase) as $dc |
      ((.region // "") | ascii_upcase) as $reg |
      (($s3f | not) or ($s3 | index($dc))) and
      (($globalf | not) or .globalNetwork) and
      (($vols | length) == 0 or ((.networkVolumeTypes // []) | map(ascii_upcase) | any(. as $t | $vols | index($t)))) and
      (($comps | length) == 0 or ((.compliance // []) | map(ascii_upcase) | any(. as $t | $comps | index($t)))) and
      (($regions | length) == 0 or ($regions | index($reg)))
    ))')"

  # rp::table takes no jq args, so pre-shape (joining the S3 set) then table it.
  shaped="$(printf '%s' "$filt" | jq -c --argjson s3 "$s3set" '
    map((.id | ascii_upcase) as $dc | {
      DATACENTER:    .id,
      REGION:        .region,
      GLOBAL_NETWORK: (if .globalNetwork then "yes" else "" end),
      COMPLIANCE:    ((.compliance // []) | join(", ")),
      NETWORK_VOLUME_TYPES: ((.networkVolumeTypes // []) | join(", ")),
      GPUS:          ((.gpuAvailability // []) | map(select(.availability != "NONE")) | length),
      S3_API:        (if ($s3 | index($dc)) then "yes" else "" end)
    }) | sort_by(.DATACENTER)')"
  rp::emit_json_or "$filt" rp::table "$shaped" DATACENTER REGION GPUS S3_API GLOBAL_NETWORK COMPLIANCE NETWORK_VOLUME_TYPES
}

###
### :::: documentation (rp doc stock) :::: ####################################
###

# doc: gpu
# List GPU types with price and live availability.
#
# Usage: rp stock gpu [--product <p,…>] [--min-count N]
#                     [--cloud SECURE|COMMUNITY] [--min-cuda <ver>]
#                     [--vram-gb N] [--stock NONE|LOW|MEDIUM|HIGH]
#                     [--cuda <ver>] [--sort <column>] [--json]
#
# Options:
#   --product <p,…>           POD, CLUSTER or SERVERLESS, comma-separated
#                             (default: POD,SERVERLESS)
#   --min-count N             only types with at least N GPUs free on one host
#                             (minimum 1)
#   --cloud SECURE|COMMUNITY  keep only types offered on that tier
#   --min-cuda <ver>          minimum CUDA version, major or major.minor
#   --vram-gb N               keep only types with at least N GB of VRAM
#                             (--vram is accepted as an alias)
#   --stock <level>           keep only types whose STOCK is that level
#   --cuda <ver>              keep only types with that CUDA version available
#   --sort <column>           order rows by ID, DISPLAY, VRAM_GB, CLOUD,
#                             SECURE_PRICE, COMMUNITY_PRICE, STOCK or CUDA
#                             (VRAM is accepted as an alias for VRAM_GB)
#   --hide <cols>             drop columns from the table (display-only; never
#                             filters rows or --json). Comma-separated,
#                             case-insensitive: any of ID, DISPLAY, VRAM_GB,
#                             CLOUD, SECURE_PRICE, COMMUNITY_PRICE, STOCK, CUDA,
#                             DATACENTERS (e.g. --hide DISPLAY,SECURE_PRICE)
#   --json                    print the raw API response
#
# Notes:
#   The ID column is the value `rp pod create --gpu` and
#   `rp serverless create --gpu` take. Ids are display names containing
#   spaces, so quote them.
#   STOCK is availability for the product and cloud you asked about, so one
#   card can read differently under --product POD and --product SERVERLESS.
#   CLOUD lists the tiers a type is offered on: "SECURE, COMMUNITY" when both,
#   or just "SECURE" / "COMMUNITY"; a dash means neither.
#   SECURE_PRICE and COMMUNITY_PRICE are the per-GPU hourly rates for each
#   tier; a dash ("-") means that tier is not offered (gated on the
#   secure/community flags, not on the price value — the API can return a
#   non-zero price for an unoffered tier).
#   CUDA lists the available CUDA versions (truncated to two plus "+N more");
#   a dash means none are advertised. It is the same ceiling --min-cuda filters
#   against.
#   DATACENTERS lists the datacentres that offer this GPU with stock
#   (availability != NONE), sorted by id and truncated to two ids plus "+N
#   more"; a dash means none are stocked. It is the same per-datacentre
#   availability the API returns under include=AVAILABILITY, so it already
#   honours --product, --cloud and --min-count.
#   --vram-gb / --vram is a minimum: a type with more VRAM than N still passes.
#   --hide is display-only: it removes columns from the table but leaves the row
#   set and the --json payload untouched, so it is unrelated to filtering.
#   All filters and --sort apply to BOTH the table and --json, so the two views
#   always show the same types.
#   --min-count is per host: it asks for N of that GPU in one machine, not N
#   across the fleet. The floor is 1, so 0 or a negative is a usage error.
#   --min-cuda takes 12 or 12.1; any other shape is rejected before the call.
#
# Examples:
# # Show secure-cloud GPUs with at least two in stock
# $ rp stock gpu --cloud SECURE --min-count 2
# # Show serverless GPUs with CUDA 12.4 or newer
# $ rp stock gpu --product SERVERLESS --min-cuda 12.4
#
# API: GET /v2/catalog/gpus  (include=AVAILABILITY)

# doc: cpus
# List reservable CPU instances with price and availability.
#
# Usage: rp stock cpus [--dc <id>] [--vcpu N] [--product POD|SERVERLESS|CLUSTER] [--compact] [--json]
#
# Options:
#   --dc <id>       keep only flavours stocked in this datacentre (case-insensitive)
#   --vcpu N        keep only instances of N vCPUs (a power of two, minimum 2)
#   --product <p>   POD, SERVERLESS or CLUSTER; show only that tier's price column
#                   and drop flavours not offered on it (default: POD,SERVERLESS,
#                   both columns)
#   --compact       show one row per flavour (the old vcpu-range table) instead of
#                   one row per power-of-two size
#   --json          print the raw API response (the flavour objects, not expanded)
#
# Notes:
#   By default this verb EXPANDS each flavour into one row per deployable size:
#   every power-of-two vCPU count inside the flavour's valid range (2, 4, 8,
#   16, 32, …). That is exactly the set `rp pod create --cpu-flavor <ID>
#   --vcpu <n>` accepts, so each row is a real instance you can reserve.
#   FLAVOUR is the flavour id `rp pod create --cpu-flavor` takes; VCPU and
#   RAM_GB are that instance's size and total RAM (= VCPU × RAM_GB_VCPU).
#   SECURE_PRICE and SERVERLESS_PRICE are the hourly rates for that instance
#   size: the total (VCPU × per-vCPU rate) with the per-vCPU rate in
#   parentheses. With --product the OTHER tier's column is dropped entirely, and
#   any flavour not offered on that product (e.g. Memory-Optimized on
#   SERVERLESS, whose serverless price is 0) is omitted from the table. A dash
#   in the remaining price column means that tier is not offered.
#   STOCK is shown only with --dc: it then reflects that datacentre's own
#   availability (region-accurate). Without --dc the column is hidden, since the
#   flavour-level value is only a global "available somewhere" aggregate.
#   --vcpu N narrows the expanded rows to one size (validated: power of two,
#   >= 2); --compact collapses back to one row per flavour (VCPU shown as a
#   min-max range, RAM_GB_VCPU and the tier price as per-vCPU values).
#   DATACENTERS lists every datacentre the flavour is stocked in, but the
#   table column is truncated to the first two ids followed by "+N more"
#   (e.g. "EU-CZ-1, EU-NL-1 +12 more") to keep the row readable; the full
#   list is always in --json. Because filtering matches the underlying
#   dataCenters array, --dc still finds a flavour even when its datacentre
#   is hidden behind "+N more".
#   --dc and --product apply to BOTH the table and --json so the two views
#   always show the same flavours.
#
# API: GET /v2/catalog/cpus  (include=AVAILABILITY, product=<selected>)

# doc: dc
# List datacentres with GPU stock and S3-API support.
#
# Usage: rp stock dc [--json] [--s3] [--global-network] [--volume-type <t,…>]
#                     [--compliance <c,…>] [--region <r,…>]
#
# Options:
#   --json          print the raw v2 datacentre records (post-filter)
#   --s3            keep only S3-API-enabled datacentres
#   --global-network  keep only datacentres on Runpod's global network
#   --volume-type <t,…>  keep only datacentres supporting at least one listed
#                        network-volume tier (e.g. STANDARD,HIGH_PERFORMANCE)
#   --compliance <c,…>   keep only datacentres carrying at least one listed
#                        certification (e.g. SOC_2_TYPE_2)
#   --region <r,…>       keep only datacentres in at least one listed region
#                        (e.g. EU,NA,AS) — the REGION column, case-insensitive.
#                        Accepts abbreviations (eg: NA, EU) or the full names
#                        (eg: NORTH_AMERICA, ASIA)
#
# Notes:
#   Filters combine as a logical AND; within a comma list they are OR. All flags
#   apply to BOTH the table and --json, so the two views always show the same
#   datacentres (--json omits the S3_API column, which is a CLI-side join).
#   The DATACENTER column is the id `rp pod create --dc` and
#   `rp volume create --dc` take. (The v2 `name` field is the same value in
#   practice and is not shown as a separate column.)
#   GPUS counts how many GPU types have any stock there, not how many cards
#   are free.
#   GLOBAL_NETWORK marks datacentres that support global networking — Runpod's
#   private, cross-datacenter pod-to-pod network (pods reach each other over
#   *.runpod.internal without opening ports to the public internet). It is
#   unrelated to the S3_API column.
#   COMPLIANCE lists the certifications the datacentre carries (e.g.
#   SOC_2_TYPE_2), comma-separated; blank where none are advertised.
#   NETWORK_VOLUME_TYPES lists the network-volume tiers the datacentre supports
#   (e.g. STANDARD, HIGH_PERFORMANCE), comma-separated; blank where none are
#   advertised. The tier constrains the kind of volume `rp volume create` can
#   place there.
#   S3_API marks the datacentres whose network volumes expose the
#   S3-compatible API — the ones `rp volume sync` can reach.
#   That column is NO-V2-EQUIVALENT: v2 carries no S3 field anywhere, so it is
#   joined in from the GraphQL dataCenters query — the same resolver
#   `rp volume create` guards on — with an offline snapshot behind it. The
#   column therefore stays live where GraphQL is reachable and still renders
#   when it is not.
#   --json prints the v2 datacentre records alone: S3_API is a CLI-side join
#   and is absent from that payload.
#
# Examples:
# # Datacentres that are BOTH S3-API enabled AND on the global network
# $ rp stock dc --s3 --global-network
# # Datacentres that support the HIGH_PERFORMANCE volume tier
# $ rp stock dc --volume-type HIGH_PERFORMANCE
#
# API: GET /v2/catalog/datacenters  (include=GPU_AVAILABILITY,CPU_AVAILABILITY)

rp::cmd_stock() {
  local verb="${1:-help}"
  shift || true
  rp::args_parse "$@"
  rp::args_has help && verb=help
  case "$verb" in
  gpu) _stock_gpu ;;
  cpus) _stock_cpus ;;
  dc) _stock_dc ;;
  -h | --help | help | "")
    echo "Usage: rp stock gpu [--product POD,CLUSTER,SERVERLESS] [--min-count N] [--cloud SECURE|COMMUNITY] [--min-cuda <ver>] [--vram-gb N] [--stock NONE|LOW|MEDIUM|HIGH] [--cuda <ver>] [--sort <column>] [--hide <cols>] | rp stock cpus [--dc <id>] [--vcpu N] [--product POD|SERVERLESS|CLUSTER] [--compact] | rp stock dc [--json] [--s3] [--global-network] [--volume-type <t,…>] [--compliance <c,…>] [--region <r,…>]   (dc list via v2; --region takes EU/NA/AS… or full names; filters apply to both table and --json)"
    ;;
  *) rp::usage "unknown stock verb: '$verb'" ;;
  esac
}
