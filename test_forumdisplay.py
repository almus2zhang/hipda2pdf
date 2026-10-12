import urllib.request
import urllib.parse
import http.cookiejar
import re
from bs4 import BeautifulSoup

cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'}

req = urllib.request.Request('https://www.4d4y.com/forum/logging.php?action=login', headers=headers)
html = opener.open(req).read().decode('gbk', errors='ignore')
formhash = re.search(r'name="formhash" value="([^"]+)"', html).group(1)
sid = re.search(r'name="sid" value="([^"]+)"', html).group(1)

post_data = urllib.parse.urlencode({
    'sid': sid,
    'formhash': formhash,
    'referer': 'index.php',
    'loginfield': 'username',
    'username': 'helloearth',
    'password': 'xCxoYREojL6OoW',
    'questionid': '0',
    'answer': '',
    'cookietime': '315360000',
}, encoding='gbk').encode('gbk')

opener.open(urllib.request.Request('https://www.4d4y.com/forum/logging.php?action=login&loginsubmit=yes', data=post_data, headers=headers))

forum_url = 'https://www.4d4y.com/forum/forumdisplay.php?fid=2'
req_f = urllib.request.Request(forum_url, headers=headers)
f_html = opener.open(req_f).read().decode('gbk', errors='ignore')

soup = BeautifulSoup(f_html, 'html.parser')
tbodys = soup.find_all('tbody', id=re.compile(r'^(?:normalthread|stickthread)_\d+'))
print('Found threads:', len(tbodys))
for tb in tbodys[:5]:
    subject = tb.find('span', id=re.compile(r'^thread_\d+'))
    link = subject.find('a') if subject else None
    author = tb.find('td', class_='author')
    author_cite = author.find('cite') if author else None
    nums = tb.find('td', class_='nums')
    replies = nums.find('strong').text.strip() if (nums and nums.find('strong')) else ''
    views = nums.find('em').text.strip() if (nums and nums.find('em')) else ''
    print('Title:', subject.text.strip() if subject else 'none')
    print('Link:', link['href'] if link else 'none')
    print('Author:', author_cite.text.strip() if author_cite else (author.text.strip() if author else 'none'))
    print('Replies/Views:', f"{replies}/{views}" if replies else (nums.text.strip() if nums else 'none'))
    print('---')

# check pagination on forumdisplay
pages_div = soup.find('div', class_='pages')
if pages_div:
    print('Pages div found:')
    print(pages_div.text.strip())
    # find all page numbers
    page_links = re.findall(r'page=(\d+)', str(pages_div))
    print('Page links in forumdisplay:', set(page_links))
