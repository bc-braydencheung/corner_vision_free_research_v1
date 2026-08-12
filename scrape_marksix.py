"""HKJC Mark Six scraper - downloads ALL draws from 1993 to present.
Run from YOUR computer (not cloud) to pass IP whitelist.
"""
import json, urllib.request, gzip, time, datetime

Q = (
    'fragment lotteryDrawsFragment on LotteryDraw {'
    ' id year no openDate closeDate drawDate status'
    ' snowballCode snowballName_en snowballName_ch'
    ' lotteryPool { sell status totalInvestment jackpot unitBet'
    '   estimatedPrize derivedFirstPrizeDiv'
    '   lotteryPrizes { type winningUnit dividend } }'
    ' drawResult { drawnNo xDrawnNo } }'
    ' query marksixResult($lastNDraw: Int, $startDate: String,'
    ' $endDate: String, $drawType: LotteryDrawType) {'
    ' lotteryDraws(lastNDraw: $lastNDraw, startDate: $startDate,'
    '   endDate: $endDate, drawType: $drawType) {'
    '   ...lotteryDrawsFragment } }'
)

def call(variables):
    body = json.dumps({"query": Q, "variables": variables}).encode()
    req = urllib.request.Request(
        "https://info.cld.hkjc.com/graphql/base/", data=body,
        headers={"Content-Type": "application/json",
                 "Origin": "https://bet.hkjc.com",
                 "Referer": "https://bet.hkjc.com/",
                 "User-Agent": "Mozilla/5.0"})
    for attempt in range(6):
        try:
            r = urllib.request.urlopen(req, timeout=60)
            raw = r.read()
            if r.headers.get("Content-Encoding") == "gzip":
                raw = gzip.decompress(raw)
            return json.loads(raw)
        except Exception as e:
            print(f"  retry {attempt}: {e}", flush=True)
            time.sleep(3)
    raise SystemExit("Failed")

def add_months(d, n):
    m = d.month - 1 + n
    return datetime.date(d.year + m // 12, m % 12 + 1, 1)

print("Starting scrape from 1993 to today...")
draws, cur, end = {}, datetime.date(1993, 1, 1), datetime.date.today()
while cur <= end:
    nxt = add_months(cur, 2)
    e = min(nxt - datetime.timedelta(days=1), end)
    data = call({"startDate": cur.strftime("%Y%m%d"),
                 "endDate": e.strftime("%Y%m%d"),
                 "drawType": "All"})
    items = (data.get("data") or {}).get("lotteryDraws") or []
    for x in items:
        draws[x["id"]] = x
    print(f"{cur} ~ {e} : +{len(items)} = {len(draws)} total", flush=True)
    cur = nxt
    time.sleep(0.3)

out = sorted(draws.values(), key=lambda x: (x.get("drawDate") or "", x.get("no") or 0))
json.dump(out, open("marksix_draws.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print(f"\nDONE! {len(out)} draws saved to marksix_draws.json")
