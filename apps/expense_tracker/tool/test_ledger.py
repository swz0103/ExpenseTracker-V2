"""Six months of made-up entries for 記帳本, as the app's own CSV.

Salary, rent and bills, everyday spending at real shops, a card paid off
each month and a laptop in 12 instalments, transfers, money lent, and
stocks bought, sold and paid out. The same every run (a fixed seed), up
to 2026-11-03. test/tool/test_ledger_test.dart imports it and keeps it as
the test backup, which opens with test1234.

    python3 tool/test_ledger.py out.csv
"""
import csv
import datetime as dt
import random
import sys

random.seed(20261103)
HEAD = ['日期', '類型', '金額', '帳戶', '轉入帳戶', '分類', '商家', '標籤', '備註',
        '代號', '股數', '手續費', '稅', '分期', '轉入金額', '台幣金額', '成本算法']
rows = []


def add(day, kind, amount, account, category='', merchant='', tags='', note='',
        to='', code='', shares='', fee='', tax='', inst=''):
    rows.append({'日期': day.isoformat(), '類型': kind, '金額': str(amount), '帳戶': account,
                 '轉入帳戶': to, '分類': category, '商家': merchant, '標籤': tags, '備註': note,
                 '代號': code, '股數': str(shares) if shares else '', '手續費': str(fee) if fee else '',
                 '稅': str(tax) if tax else '', '分期': str(inst) if inst else ''})


BANK, CASH, CARD, PAY, BROKER, LENT = '銀行帳戶', '現金', '國泰信用卡', 'LINE Pay', '證券戶', '代墊-阿哲'
start, today = dt.date(2026, 5, 1), dt.date(2026, 11, 3)

# Opening balances
add(start, '收入', 85000, BANK, '其他收入', note='期初餘額')
add(start, '收入', 3200, CASH, '其他收入', note='期初餘額')
add(start, '收入', 220000, BROKER, '其他收入', note='期初餘額')

lunch = ['八方雲集', '麥當勞', '池上便當', '鼎泰豐', '摩斯漢堡', '吉野家', '自助餐']
drinks = ['星巴克', '路易莎', '50嵐', '可不可熟成紅茶', '85度C']
stores = ['7-ELEVEN', '全家', '全聯', '家樂福']
shopping = [('蝦皮', 'PChome'), ('MOMO', 'UNIQLO'), ('誠品', '無印良品')]
card_by_month = {}

d = start
while d <= today:
    m = (d.year, d.month)
    # Monthly fixed items
    if d.day == 1:
        add(d, '支出', 12500, BANK, '居家生活', note=f'{d.month}月房租')
    if d.day == 5:
        add(d, '收入', 52000, BANK, '薪資收入', note=f'{d.month}月薪資')
    if d.day == 8:
        add(d, '支出', 390, CARD, '訂閱服務', 'Netflix', note='Netflix')
    if d.day == 12:
        add(d, '支出', 149, CARD, '訂閱服務', 'Spotify', note='Spotify')
    if d.day == 18:
        add(d, '支出', 699, BANK, '居家生活', '中華電信', note='網路費')
    if d.day == 20:
        add(d, '支出', random.randint(780, 1450), BANK, '居家生活', '台電', note='電費')
    if d.day == 3:
        add(d, '轉帳', 3000, BANK, to=PAY, note='LINE Pay 儲值')
    if d.day == 2:
        add(d, '轉帳', 3000, BANK, to=CASH, note='ATM 提款')
    if d.day == 10:
        add(d, '支出', 1280, BANK, '交通通勤', '台北捷運', note='定期票')
    # Pay last month's card bill on the 15th
    if d.day == 15:
        prev = (d.year, d.month - 1) if d.month > 1 else (d.year - 1, 12)
        bill = card_by_month.get(prev, 0)
        if bill:
            add(d, '轉帳', bill, BANK, to=CARD, note=f'繳 {prev[1]} 月卡費')
    # Daily spending
    if d.weekday() < 5:
        p = random.choice(lunch)
        add(d, '支出', random.choice([85, 95, 110, 120, 135, 150, 180]), random.choice([CASH, PAY, CASH]),
            '飲食日常', p, note='午餐')
    if random.random() < 0.45:
        p = random.choice(drinks)
        add(d, '支出', random.choice([55, 65, 75, 120, 135, 155]), PAY, '飲食日常', p, note='飲料')
    if random.random() < 0.35:
        p = random.choice(stores)
        amt = random.randint(60, 420) if p in ('7-ELEVEN', '全家') else random.randint(380, 1650)
        cat = '飲食日常' if p in ('7-ELEVEN', '全家') else '居家生活'
        add(d, '支出', amt, CARD if amt > 300 else CASH, cat, p, note='日用品' if cat == '居家生活' else '零食')
    if d.weekday() == 5 and random.random() < 0.7:
        amt = random.choice([680, 920, 1180, 1560, 2280])
        add(d, '支出', amt, CARD, '飲食日常', random.choice(['瓦城', '饗食天堂', '王品', '築間']), note='週末聚餐')
        card_by_month[m] = card_by_month.get(m, 0) + amt
    if random.random() < 0.08:
        site = random.choice(random.choice(shopping))
        amt = random.randint(450, 3200)
        add(d, '支出', amt, CARD, '購物休閒', site, note='網購')
        card_by_month[m] = card_by_month.get(m, 0) + amt
    if random.random() < 0.12:
        add(d, '支出', random.choice([120, 180, 250, 320]), PAY, '交通通勤', 'Uber', note='叫車')
    d += dt.timedelta(days=1)

# A trip with a tag, a split, a refund, an installment
add(dt.date(2026, 7, 18), '支出', 2400, BANK, '交通通勤', '台鐵', '花蓮旅行', '來回車票')
add(dt.date(2026, 7, 18), '支出', 4800, CARD, '居家生活', '花蓮民宿', '花蓮旅行', '民宿兩晚')
add(dt.date(2026, 7, 19), '支出', 1260, CASH, '飲食日常', '花蓮夜市', '花蓮旅行', '夜市')
add(dt.date(2026, 7, 20), '支出', 680, CASH, '購物休閒', '曾記麻糬', '花蓮旅行', '伴手禮')
add(dt.date(2026, 9, 6), '支出', 3580, CARD, '飲食日常=1980;居家生活=1600', '好市多', note='好市多採買')
add(dt.date(2026, 9, 20), '支出', 1990, CARD, '購物休閒', 'UNIQLO', note='外套')
add(dt.date(2026, 9, 23), '退款', 1990, CARD, merchant='UNIQLO', note='外套退貨')
add(dt.date(2026, 6, 2), '支出', 36000, CARD, '購物休閒', '燦坤', note='筆電（12 期）', inst=12)
add(dt.date(2026, 8, 12), '支出', 1200, BANK, '其他支出', '台大醫院', note='看診')
add(dt.date(2026, 10, 9), '收入', 8000, BANK, '其他收入', note='年中獎金')
# Paid for a friend, and got it back
add(dt.date(2026, 10, 17), '轉帳', 850, BANK, to=LENT, note='幫阿哲付電影票')
add(dt.date(2026, 10, 28), '轉帳', 850, LENT, to=BANK, note='阿哲還錢')
# Investments
add(dt.date(2026, 5, 6), '買進', 98500, BROKER, code='0050', shares=1000, fee=140, note='定期定額')
add(dt.date(2026, 6, 10), '買進', 1090000 // 10, BROKER, code='2330', shares=100, fee=155, note='台積電零股')
add(dt.date(2026, 7, 22), '股息', 1800, BROKER, code='0050', note='0050 配息')
add(dt.date(2026, 10, 14), '股息', 500, BROKER, code='2330', note='台積電配息')
add(dt.date(2026, 9, 2), '賣出', 52000, BROKER, code='0050', shares=500, fee=74, tax=156, note='部分賣出')

# Card spending counted from rows on the card
card_by_month = {}
for r in rows:
    if r['帳戶'] == CARD and r['類型'] in ('支出', '退款') and not r['分期']:
        y, mo = int(r['日期'][:4]), int(r['日期'][5:7])
        sign = -1 if r['類型'] == '退款' else 1
        card_by_month[(y, mo)] = card_by_month.get((y, mo), 0) + sign * int(r['金額'])
# The laptop's 12 payments of 3,000, billed from June on
for mo in range(6, 13):
    card_by_month[(2026, mo)] = card_by_month.get((2026, mo), 0) + 3000
rows = [r for r in rows if not (r['類型'] == '轉帳' and r['轉入帳戶'] == CARD)]
for (y, mo), total in sorted(card_by_month.items()):
    pay = dt.date(y + (mo == 12), mo % 12 + 1, 15)
    if pay <= today:
        add(pay, '轉帳', total, BANK, to=CARD, note=f'繳 {mo} 月卡費')

rows.sort(key=lambda r: r['日期'])
with open(sys.argv[1], 'w', encoding='utf-8-sig', newline='') as f:
    w = csv.DictWriter(f, fieldnames=HEAD)
    w.writeheader()
    w.writerows(rows)
print(len(rows), 'rows')
