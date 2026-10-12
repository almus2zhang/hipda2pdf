import re
from test_forumdisplay import f_html

def test_dart_regex(html):
    tbodyRegex = re.compile(r'<tbody[^>]*id="(?:normalthread|stickthread)_(\d+)"[^>]*>(.*?)</tbody>', re.DOTALL | re.IGNORECASE)
    matches = tbodyRegex.findall(html)
    print("Matches count:", len(matches))
    for tid, content in matches[:5]:
        titleMatch = re.search(r'<span[^>]*id="thread_\d+"[^>]*>.*?<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>', content, re.DOTALL)
        if titleMatch:
            t = re.sub(r'<[^>]+>', '', titleMatch.group(2)).strip()
            print(f"TID {tid}: {t}")
        else:
            print(f"TID {tid}: titleMatch is None! Content snippet: {content[:200]}")

test_dart_regex(f_html)
