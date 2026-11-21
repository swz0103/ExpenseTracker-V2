"""Five years of made-up entries for 記帳本, as the app's own CSV.

As much as the app can show, so every page has something on it: salary,
bonuses and interest; rent, bills and everyday spending at real shops
from several banks, cash, e-wallets and three credit cards; card bills
paid on their due days, with phones and laptops in instalments; splits,
refunds and tags; trips paid from a yen and a dollar account; a car loan
paid each month; money lent to three people; and ten stocks bought, sold
(by lot and by average cost), paid out in cash and in shares. The same
every run (a fixed seed), from 2021-11-01 to 2026-11-15: a salary that
rises each year, breakfasts, dinners, snacks and the gym, a trip or two
a year, furniture and gadgets in instalments, and dividends on each
stock's own schedule every year.

The accounts that need more than a name (the cards' days and limits, the
foreign accounts, the loan) are made by test/tool/test_ledger_test.dart
before it imports this and keeps it as the test backup, which opens with
test1234; it also adds budgets and recurring items.

    python3 tool/test_ledger.py out.csv
"""
import csv
import datetime as dt
import random
import sys

random.seed(20261115)
HEAD = ['日期', '類型', '金額', '帳戶', '轉入帳戶', '分類', '商家', '標籤', '備註',
        '代號', '股數', '手續費', '稅', '分期', '轉入金額', '台幣金額', '成本算法']
rows = []


def add(day, kind, amount, account, category='', merchant='', tags='', note='',
        to='', code='', shares='', fee='', tax='', inst='', received='', home='',
        method=''):
    rows.append({'日期': day.isoformat(), '類型': kind, '金額': str(amount), '帳戶': account,
                 '轉入帳戶': to, '分類': category, '商家': merchant, '標籤': tags, '備註': note,
                 '代號': code, '股數': str(shares) if shares else '',
                 '手續費': str(fee) if fee else '', '稅': str(tax) if tax else '',
                 '分期': str(inst) if inst else '', '轉入金額': str(received),
                 '台幣金額': str(home), '成本算法': method})


# Accounts. The test makes these first (see the docstring):
SALARY, MAIN, POST, DIGITAL, OLD = '台新銀行', '國泰世華', '郵局儲蓄', 'Richart 數位帳戶', '舊薪轉帳戶'
BROKER, CASH, JAR = '證券戶', '現金', '零錢罐'
LINE, JKO, EASY = 'LINE Pay', '街口支付', '悠遊卡'
CATHAY, ESUN, TAISHIN = '國泰信用卡', '玉山信用卡', '台新信用卡'
USD, JPY, LOAN = '美元帳戶', '日圓帳戶', '車貸'
ZHE, MEI, MOM = '代墊-阿哲', '代墊-小美', '借給媽媽'
CARDS = {CATHAY: (5, 20, MAIN), ESUN: (15, 3, SALARY), TAISHIN: (25, 13, SALARY)}

start, today = dt.date(2021, 11, 1), dt.date(2026, 11, 15)
FIRST_PAY = dt.date(2021, 11, 30)  # salary lands on SALARY after this


def days():
    d = start
    while d <= today:
        yield d
        d += dt.timedelta(days=1)


# Opening balances
for account, amount in [(SALARY, 220000), (MAIN, 152000), (POST, 240000), (DIGITAL, 45000),
                        (OLD, 23000), (CASH, 6000), (JAR, 860), (LINE, 1500), (EASY, 500), (BROKER, 400000)]:
    add(start, '收入', amount, account, '其他收入', note='期初餘額')
# The old salary account, emptied and then left (the test archives it)
add(dt.date(2021, 11, 5), '收入', 68000, OLD, '薪資收入', '公司', note='11月薪資')
add(dt.date(2021, 11, 30), '轉帳', 91000, OLD, to=SALARY, note='舊帳戶結清')

breakfasts = ['美而美', '麥味登', '拉亞漢堡', '弘爺漢堡', '晨間廚房', '7-ELEVEN']
suppers = ['巷口麵店', '滷味', '鹽酥雞', '牛肉麵', '自助餐', '水餃店', '便當店', 'Uber Eats', 'foodpanda']
snacks = ['路邊攤', '雞蛋糕', '豆花', '剉冰', '烤地瓜', '臭豆腐']
lunch = ['八方雲集', '麥當勞', '池上便當', '鼎泰豐', '摩斯漢堡', '吉野家', '自助餐', '爭鮮', '四海遊龍']
drinks = ['星巴克', '路易莎', '50嵐', '可不可熟成紅茶', '85度C', 'CAMA', '清心福全']
marts = ['7-ELEVEN', '全家', '萊爾富']
groceries = ['全聯福利中心', '家樂福', '美廉社', '頂好']
dinners = ['瓦城', '饗食天堂', '王品', '築間', '石二鍋', '欣葉', '海底撈']
shops = ['蝦皮購物', 'PChome', 'momo購物網', 'UNIQLO', '誠品', '無印良品', 'IKEA', 'NET']
fun = [('威秀影城', '電影'), ('KTV 好樂迪', '唱歌'), ('Steam', '遊戲'), ('任天堂 eShop', '遊戲')]
wallets = [CASH, LINE, JKO, CASH, LINE]

for d in days():
    y, m, day, wd = d.year, d.month, d.day, d.weekday()
    raise_ = {2021: 68000, 2022: 70000, 2023: 73000, 2024: 76000, 2025: 79000}.get(y, 82000)
    # Monthly income and fixed items
    if day == 5 and d > FIRST_PAY:
        add(d, '收入', raise_, SALARY, '薪資收入', '公司', note=f'{m}月薪資')
    if (m, day) == (2, 6):
        add(d, '收入', raise_ * 2, SALARY, '獎金', '公司', note='年終獎金')
    if (m, day) == (9, 6):
        add(d, '收入', 15000, SALARY, '獎金', '公司', note='中秋獎金')
    if day == 21:
        add(d, '收入', random.randint(40, 95), DIGITAL, '利息收入', 'Richart', note='活存利息')
    if day == 25 and m in (1, 3, 5, 7, 9, 11):
        prize = random.choice([0, 0, 0, 200, 200, 500, 1000])
        if prize:
            add(d, '收入', prize, CASH, '發票中獎', '財政部', note='統一發票中獎')
    if day == 1:
        add(d, '支出', 12500, SALARY, '居家生活', '房東', '固定', f'{m}月房租')
    if day == 6 and d > FIRST_PAY:
        add(d, '轉帳', 3000, SALARY, to=DIGITAL, note='每月存錢')
        add(d, '轉帳', 1500, SALARY, to=POST, note='緊急預備金')
        add(d, '轉帳', 6000, SALARY, to=BROKER, note='定期定額入金')
    if day == 10:
        add(d, '支出', 1200, EASY, '交通通勤', '台北捷運', note='TPASS 月票')
    if day == 8:
        add(d, '支出', 390, CATHAY, '訂閱服務', 'Netflix', '固定', 'Netflix')
    if day == 12:
        add(d, '支出', 149, ESUN, '訂閱服務', 'Spotify', '固定', 'Spotify')
    if day == 14:
        add(d, '支出', 90, TAISHIN, '訂閱服務', 'Apple', '固定', 'iCloud+')
    if day == 20:
        add(d, '支出', 199, CATHAY, '訂閱服務', 'YouTube', '固定', 'YouTube Premium')
    if day == 18:
        add(d, '支出', 699, MAIN, '居家生活', '中華電信', '固定', '網路費')
        add(d, '支出', 599, MAIN, '居家生活', '台灣大哥大', '固定', '手機費')
    if day == 20 and m % 2 == 1:
        summer = m in (5, 7, 9)
        add(d, '支出', random.randint(1800, 3200) if summer else random.randint(900, 1500),
            SALARY, '居家生活', '台電', note='電費')
    if day == 22 and m % 2 == 0:
        add(d, '支出', random.randint(320, 520), SALARY, '居家生活', '台北自來水', note='水費')
    if day == 16:
        add(d, '支出', random.randint(350, 620), CASH, '居家生活', '欣欣瓦斯', note='瓦斯費')
    if day == 25:
        add(d, '轉帳', 7900, SALARY, to=LOAN, note='車貸月付')
    if day == 15 and d >= dt.date(2023, 1, 15):
        add(d, '支出', 1200, LINE, '寵物', '毛孩市集', '毛孩', '飼料')
    if day == 27:
        add(d, '支出', random.choice([350, 400, 450]), CASH, '購物休閒', '百元剪髮', note='剪頭髮')
    if (m, day) == (3, 15):
        add(d, '支出', 12800, MAIN, '保險', '富邦產險', '固定', '汽車保險')
    if (m, day) == (7, 10):
        add(d, '支出', 24000, SALARY, '保險', '國泰人壽', '固定', '壽險年繳')
    if (m, day) == (5, 31):
        add(d, '支出', 7120, MAIN, '其他支出', '監理站', note='牌照稅')
    if day == 7 and d >= dt.date(2023, 3, 7):
        add(d, '支出', 1288, TAISHIN, '醫療保健', 'World Gym', '固定', '健身房月費')
    if day == 23:
        add(d, '支出', 500, MAIN, '人情社交', '家扶基金會', '固定', '每月捐款')
    if (m, day) in ((4, 12), (10, 12)):
        add(d, '支出', random.choice([2800, 3600, 4200, 6800]), ESUN, '交通通勤', 'Toyota 保養廠',
            '車子', '定期保養')
    if (m, day) in ((1, 18), (7, 18)):
        add(d, '支出', random.choice([200, 350, 800]), CASH, '醫療保健', '牙醫診所', note='洗牙')
    if (m, day) == (11, 9):
        add(d, '支出', 3500, MAIN, '醫療保健', '健康管理中心', note='年度健檢')
    if (m, day) in ((5, 9), (8, 8), (1, 28)):
        add(d, '支出', random.choice([1800, 2600, 3600, 6600]), random.choice([CASH, CATHAY]),
            '人情社交', random.choice(['母親節', '父親節', '過年紅包']), '家人', '家人')
    if day == 28 and m in (3, 9):
        add(d, '支出', random.randint(1800, 5200), random.choice([CATHAY, ESUN]), '購物休閒',
            random.choice(['UNIQLO', 'NET', 'GU', 'ZARA']), '換季', '換季衣服')
    # Everyday spending
    if wd < 5 and random.random() < 0.6:
        add(d, '支出', random.choice([45, 55, 65, 70, 85]), random.choice([CASH, CASH, LINE]),
            '飲食日常', random.choice(breakfasts), note='早餐')
    if wd < 5 and random.random() < 0.45:
        add(d, '支出', random.choice([90, 110, 130, 160, 220]), random.choice(wallets),
            '飲食日常', random.choice(suppers), note='晚餐')
    if random.random() < 0.08:
        add(d, '支出', random.choice([35, 50, 60, 80]), CASH, '飲食日常', random.choice(snacks),
            note='點心')
    if random.random() < 0.1:
        add(d, '支出', random.choice([30, 40, 60, 100]), EASY, '交通通勤', '停車場', '車子', '停車費')
    if wd < 5:
        add(d, '支出', random.choice([85, 95, 110, 120, 135, 150, 180]), random.choice(wallets),
            '飲食日常', random.choice(lunch), note='午餐')
    if random.random() < 0.5:
        add(d, '支出', random.choice([55, 65, 75, 120, 135, 155]), random.choice([LINE, JKO, EASY]),
            '飲食日常', random.choice(drinks), note='飲料')
    if random.random() < 0.4:
        add(d, '支出', random.randint(45, 260), random.choice([CASH, EASY, LINE]), '飲食日常',
            random.choice(marts), note='便利商店')
    if wd == 6 or random.random() < 0.08:
        add(d, '支出', random.randint(480, 2600), random.choice([CATHAY, TAISHIN]), '居家生活',
            random.choice(groceries), '家用', '採買')
    if wd == 5 and random.random() < 0.75:
        tags = random.choice(['', '', '聚餐', '約會'])
        add(d, '支出', random.choice([680, 920, 1180, 1560, 2280, 3400]), random.choice([CATHAY, ESUN]),
            '飲食日常', random.choice(dinners), tags, '週末晚餐')
    if random.random() < 0.09:
        add(d, '支出', random.randint(390, 4200), random.choice([CATHAY, ESUN, TAISHIN]), '購物休閒',
            random.choice(shops), note='網購')
    if random.random() < 0.12:
        add(d, '支出', random.choice([120, 180, 250, 320]), LINE, '交通通勤', 'Uber', note='叫車')
    if wd == 4 and random.random() < 0.6:
        add(d, '支出', random.randint(900, 1500), ESUN, '交通通勤', '台灣中油', '車子', '加油')
    if random.random() < 0.05:
        shop, what = random.choice(fun)
        add(d, '支出', random.choice([290, 360, 590, 990, 1490]), random.choice([CATHAY, LINE]),
            '購物休閒', shop, '娛樂', what)
    if random.random() < 0.03:
        add(d, '支出', random.choice([150, 200, 350, 480]), CASH, '醫療保健',
            random.choice(['診所', '康是美', '屈臣氏', '台大醫院']), note='看診與藥')
    if random.random() < 0.025:
        add(d, '支出', random.choice([380, 450, 520, 1200, 2980]), random.choice([TAISHIN, CATHAY]),
            '教育學習', random.choice(['博客來', 'Hahow', '誠品']), '學習', '書與課程')
    if random.random() < 0.012:
        add(d, '支出', random.choice([1600, 2000, 3600, 6600]), CASH, '人情社交', note='紅包')
    if random.random() < 0.06:
        add(d, '轉帳', random.choice([20, 50, 100]), CASH, to=JAR, note='零錢存起來')

# Trips: Japan paid in yen, a work trip paid in dollars
add(dt.date(2025, 4, 1), '轉帳', 32000, SALARY, to=JPY, received=146000, note='換日圓')
for i, (what, cat, amount, home) in enumerate([
        ('機票', '交通通勤', 0, 0), ('飯店三晚', '居家生活', 54000, 11800), ('一蘭拉麵', '飲食日常', 2380, 520),
        ('迴轉壽司', '飲食日常', 4600, 1010), ('JR Pass', '交通通勤', 12000, 2620),
        ('唐吉訶德', '購物休閒', 18600, 4070), ('藥妝', '醫療保健', 9800, 2140),
        ('居酒屋', '飲食日常', 7200, 1580), ('伴手禮', '人情社交', 8400, 1840)]):
    day = dt.date(2025, 4, 3 + i // 2)
    if amount:
        add(day, '支出', amount, JPY, cat, what, '日本旅行', what, home=home)
add(dt.date(2025, 3, 10), '支出', 15800, CATHAY, '交通通勤', '長榮航空', '日本旅行', '東京來回機票')
add(dt.date(2026, 3, 2), '轉帳', 64000, SALARY, to=USD, received='2000.00', note='換美金')
for i, (what, cat, amount, home) in enumerate([
        ('Hotel', '居家生活', '612.40', 19600), ('Uber', '交通通勤', '38.20', 1220),
        ('Starbucks', '飲食日常', '7.85', 250), ('Steakhouse', '飲食日常', '96.00', 3070),
        ('Target', '購物休閒', '142.30', 4550), ('Lyft', '交通通勤', '27.60', 880)]):
    add(dt.date(2026, 3, 9 + i), '支出', amount, USD, cat, what, '美國出差', what, home=home)
add(dt.date(2026, 3, 20), '收入', 21000, SALARY, '其他收入', '公司', '美國出差', '出差費報銷')
add(dt.date(2026, 7, 18), '支出', 2400, MAIN, '交通通勤', '台鐵', '花蓮旅行', '來回車票')
add(dt.date(2026, 7, 18), '支出', 4800, CATHAY, '居家生活', '花蓮民宿', '花蓮旅行', '民宿兩晚')
add(dt.date(2026, 7, 19), '支出', 1260, CASH, '飲食日常', '花蓮夜市', '花蓮旅行', '夜市')
add(dt.date(2026, 7, 20), '支出', 680, CASH, '人情社交', '曾記麻糬', '花蓮旅行', '伴手禮')

# More trips: one or two a year
add(dt.date(2022, 4, 2), '支出', 5600, CATHAY, '居家生活', '墾丁民宿', '墾丁旅行', '民宿兩晚')
add(dt.date(2022, 4, 3), '支出', 1850, CASH, '飲食日常', '墾丁大街', '墾丁旅行', '海產與夜市')
add(dt.date(2022, 4, 3), '支出', 900, CASH, '交通通勤', '機車出租', '墾丁旅行', '租機車')
add(dt.date(2022, 4, 1), '支出', 2980, MAIN, '交通通勤', '台灣高鐵', '墾丁旅行', '高鐵來回')
add(dt.date(2023, 9, 25), '轉帳', 28000, SALARY, to=JPY, received=128000, note='換日圓')
for i, (what, cat, amount, home) in enumerate([
        ('京都旅館', '居家生活', 46000, 10060), ('抹茶甜點', '飲食日常', 3200, 700),
        ('伏見稻荷御守', '人情社交', 2400, 525), ('大阪燒', '飲食日常', 4800, 1050),
        ('環球影城', '購物休閒', 26000, 5690), ('關西周遊卡', '交通通勤', 5600, 1225),
        ('藥妝', '醫療保健', 8800, 1925), ('伴手禮', '人情社交', 9600, 2100)]):
    add(dt.date(2023, 10, 1 + i // 2), '支出', amount, JPY, cat, what, '關西旅行', what, home=home)
add(dt.date(2023, 8, 20), '支出', 13600, ESUN, '交通通勤', '樂桃航空', '關西旅行', '大阪來回機票')
add(dt.date(2023, 6, 17), '支出', 3200, CATHAY, '居家生活', '台南老屋民宿', '台南旅行', '民宿')
add(dt.date(2023, 6, 17), '支出', 1460, CASH, '飲食日常', '台南小吃', '台南旅行', '牛肉湯與小吃')
add(dt.date(2023, 6, 18), '支出', 640, CASH, '人情社交', '林家白糖粿', '台南旅行', '伴手禮')
for i, (what, cat, amount) in enumerate([
        ('首爾飯店', '居家生活', 14800), ('烤肉', '飲食日常', 2600), ('樂天世界', '購物休閒', 2100),
        ('明洞購物', '購物休閒', 5400), ('T-money', '交通通勤', 1200), ('炸雞啤酒', '飲食日常', 980)]):
    add(dt.date(2024, 5, 10 + i // 2), '支出', amount, ESUN, cat, what, '首爾旅行', f'{what}（海外刷卡）')
add(dt.date(2024, 3, 2), '支出', 9800, ESUN, '交通通勤', '台灣虎航', '首爾旅行', '首爾來回機票')
add(dt.date(2024, 10, 12), '支出', 4200, CATHAY, '居家生活', '礁溪溫泉飯店', '宜蘭旅行', '溫泉一晚')
add(dt.date(2024, 10, 13), '支出', 860, CASH, '飲食日常', '羅東夜市', '宜蘭旅行', '夜市')

# Splits, refunds and instalments
for day in [dt.date(y, mo, 8) for y in range(2022, 2027) for mo in (1, 4, 7, 10)
            if dt.date(y, mo, 8) <= today]:
    food, home_ = random.randint(1200, 2600), random.randint(800, 2200)
    add(day, '支出', food + home_, TAISHIN, f'飲食日常={food};居家生活={home_}', '好市多',
        '家用', '好市多採買')
add(dt.date(2025, 6, 14), '支出', 6800, CATHAY, '購物休閒=4200;人情社交=2600', '新光三越',
    note='衣服與送禮')
add(dt.date(2025, 11, 20), '支出', 1990, ESUN, '購物休閒', 'UNIQLO', note='外套')
add(dt.date(2025, 11, 23), '退款', 1990, ESUN, merchant='UNIQLO', note='外套退貨')
add(dt.date(2026, 5, 2), '支出', 2380, CATHAY, '購物休閒', '蝦皮購物', note='耳機')
add(dt.date(2026, 5, 9), '退款', 2380, CATHAY, merchant='蝦皮購物', note='耳機退貨')
add(dt.date(2025, 10, 3), '支出', 39900, ESUN, '購物休閒', 'Apple', note='iPhone（24 期）', inst=24)
add(dt.date(2026, 6, 2), '支出', 36000, CATHAY, '購物休閒', '燦坤', note='筆電（12 期）', inst=12)
add(dt.date(2026, 8, 28), '支出', 24900, TAISHIN, '居家生活', '大同3C', note='冷氣（6 期）', inst=6)
add(dt.date(2025, 8, 12), '支出', 4600, MAIN, '醫療保健', '台大醫院', note='牙齒治療')
add(dt.date(2022, 3, 6), '支出', 32000, CATHAY, '居家生活', 'IKEA', note='沙發（12 期）', inst=12)
add(dt.date(2022, 11, 11), '支出', 18900, ESUN, '居家生活', '燦坤', note='洗衣機（6 期）', inst=6)
add(dt.date(2023, 7, 3), '支出', 42900, TAISHIN, '購物休閒', 'Sony', note='相機（12 期）', inst=12)
add(dt.date(2024, 1, 20), '支出', 9900, CATHAY, '購物休閒', 'Dyson', note='吸塵器（3 期）', inst=3)
for day, amount, shop, what in [((2022, 6, 3), 1290, 'momo購物網', '藍牙喇叭'),
                                ((2023, 2, 14), 2680, 'PChome', '電鍋'),
                                ((2024, 8, 20), 3490, '蝦皮購物', '機械鍵盤')]:
    add(dt.date(*day), '支出', amount, CATHAY, '購物休閒', shop, note=what)
    add(dt.date(*day) + dt.timedelta(days=6), '退款', amount, CATHAY, merchant=shop, note=f'{what}退貨')

# Money lent: paid back, part paid back, still owed
for y in range(2022, 2026):
    lent = random.choice([600, 900, 1400])
    add(dt.date(y, 3, 12), '轉帳', lent, LINE, to=ZHE, note='幫阿哲代墊')
    add(dt.date(y, 3, 26), '轉帳', lent, ZHE, to=LINE, note='阿哲還錢')
    lent = random.choice([450, 780])
    add(dt.date(y, 11, 4), '轉帳', lent, CASH, to=MEI, note='幫小美代墊午餐')
    add(dt.date(y, 11, 18), '轉帳', lent, MEI, to=CASH, note='小美還錢')
add(dt.date(2025, 5, 17), '轉帳', 850, SALARY, to=ZHE, note='幫阿哲付電影票')
add(dt.date(2025, 5, 28), '轉帳', 850, ZHE, to=SALARY, note='阿哲還錢')
add(dt.date(2026, 10, 17), '轉帳', 1600, LINE, to=ZHE, note='幫阿哲付演唱會票')
add(dt.date(2026, 9, 12), '轉帳', 1200, CASH, to=MEI, note='幫小美代墊晚餐')
add(dt.date(2026, 2, 1), '轉帳', 20000, POST, to=MOM, note='借媽媽')
add(dt.date(2026, 5, 1), '轉帳', 5000, MOM, to=POST, note='媽媽還一部分')
add(dt.date(2026, 8, 1), '轉帳', 5000, MOM, to=POST, note='媽媽還一部分')

# Investments: prices that drift, monthly buys of 0050, a few other stocks
prices = {'0050': 140.0, '2330': 600.0, '0056': 32.0, '00878': 18.0, '2317': 105.0,
          '2454': 950.0, '2881': 65.0, '2412': 118.0, '2884': 27.0, '006208': 80.0}
held = {code: 0 for code in prices}


def price(code, d):
    months = (d.year - start.year) * 12 + d.month - start.month
    drift = {'2330': 0.012, '0050': 0.007, '006208': 0.007, '2454': 0.005,
             '2317': 0.009}.get(code, 0.002)
    return round(prices[code] * (1 + drift) ** months * random.uniform(0.96, 1.04), 2)


def buy(d, code, shares, note):
    value = round(price(code, d) * shares)
    fee = max(1 if shares < 1000 else 20, round(value * 0.001425 * 0.6))
    add(d, '買進', value, BROKER, code=code, shares=shares, fee=fee, note=note)
    held[code] += shares


def sell(d, code, shares, note, average=False):
    value = round(price(code, d) * shares)
    fee = max(1, round(value * 0.001425 * 0.6))
    rate = 0.001 if code.startswith('00') else 0.003
    add(d, '賣出', value, BROKER, code=code, shares=shares, fee=fee, tax=round(value * rate),
        note=note, method='平均成本' if average else '')
    held[code] -= shares


d = dt.date(2021, 11, 8)
while d <= today:
    buy(d, '0050', 30, '定期定額')
    if d.month % 3 == 0:
        buy(d + dt.timedelta(days=1), '006208', 20, '定期定額')
    d = dt.date(d.year + (d.month == 12), d.month % 12 + 1, 8)
for day, code, shares, note in [
        ((2021, 11, 16), '2330', 40, '台積電零股'), ((2022, 1, 12), '0056', 2000, '高股息'),
        ((2022, 5, 18), '00878', 3000, '高股息'), ((2022, 10, 26), '2330', 30, '跌深加碼'),
        ((2023, 2, 15), '2317', 200, '鴻海'), ((2023, 3, 22), '2454', 20, '聯發科零股'),
        ((2023, 5, 17), '2881', 500, '金融股'), ((2023, 6, 14), '2412', 300, '存股'),
        ((2023, 9, 13), '2884', 1000, '金融股'), ((2024, 1, 10), '0056', 1000, '加碼'),
        ((2024, 4, 17), '2330', 20, '加碼'), ((2024, 8, 7), '00878', 2000, '加碼'),
        ((2025, 4, 9), '2330', 30, '跌深加碼'), ((2025, 10, 15), '0056', 1000, '加碼'),
        ((2026, 1, 13), '2330', 20, '加碼'), ((2026, 4, 7), '00878', 2000, '加碼')]:
    buy(dt.date(*day), code, shares, note)
sell(dt.date(2024, 7, 10), '2317', 100, '鴻海賣一半')
sell(dt.date(2025, 2, 24), '2330', 30, '台積電獲利了結', average=True)
sell(dt.date(2026, 6, 11), '2454', 20, '聯發科出清')
sell(dt.date(2026, 9, 2), '0050', 120, '部分賣出')
# Dividends on each stock's own schedule, a little more each year.
schedule = {'0056': ([(1, 18), (4, 18), (7, 17), (10, 18)], 0.85),
            '00878': ([(2, 20), (5, 19), (8, 18), (11, 13)], 0.38),
            '2330': ([(1, 9), (4, 10), (7, 10), (10, 16)], 3.0),
            '0050': ([(1, 22), (7, 16)], 0.9),
            '006208': ([(7, 23)], 1.6),
            '2881': ([(8, 7)], 2.6), '2412': ([(7, 24)], 4.6),
            '2884': ([(8, 21)], 0.8), '2317': ([(7, 30)], 5.0)}
for code, (days_, per) in schedule.items():
    for y in range(2022, 2027):
        for mo, dd in days_:
            day = dt.date(y, mo, dd)
            if day > today:
                continue
            shares_then = sum(int(r['股數']) * (1 if r['類型'] == '買進' else -1) for r in rows
                              if r['代號'] == code and r['類型'] in ('買進', '賣出')
                              and r['日期'] < day.isoformat())
            if shares_then > 0:
                cash = round(shares_then * per * (1 + 0.06 * (y - 2022)))
                add(day, '股息', cash, BROKER, code=code, note=f'{code} 配息')
# A dividend paid in shares
for y in range(2024, 2027):
    add(dt.date(y, 8, 21), '配股', 0, BROKER, code='2884', shares=30, note='玉山金配股')

# Card bills: each card's statement closes on its day; the bill, with the
# instalments due on it, is paid in full on the due day after.
bills = {}
for r in list(rows):
    card = r['帳戶']
    if card not in CARDS or r['類型'] not in ('支出', '退款'):
        continue
    close, _, _ = CARDS[card]
    day = dt.date.fromisoformat(r['日期'])
    first = (day.year, day.month) if day.day <= close else \
        (day.year + (day.month == 12), day.month % 12 + 1)
    amount = int(r['金額']) * (-1 if r['類型'] == '退款' else 1)
    count = int(r['分期'] or 1)
    for i in range(count):
        y, mo = first[0] + (first[1] - 1 + i) // 12, (first[1] - 1 + i) % 12 + 1
        share = amount // count + (amount % count if i == 0 else 0)
        bills[(card, y, mo)] = bills.get((card, y, mo), 0) + share
for (card, y, mo), total in sorted(bills.items()):
    close, due, payer = CARDS[card]
    closed = dt.date(y, mo, close)
    paid = dt.date(y, mo, due) if due > close else \
        dt.date(y + (mo == 12), mo % 12 + 1, due)
    if paid <= today and total > 0:
        add(paid, '轉帳', total, payer, to=card, note=f'繳{card[:2]} {closed.month} 月帳單')

# Money moved where it is spent: at the start of each month the salary
# account fills the wallets and 國泰世華 (which pays its card's bills) with
# what they will spend that month, so no account runs dry.
TOP_UPS = {CASH: 'ATM 提款', LINE: 'LINE Pay 儲值', JKO: '街口儲值', EASY: '悠遊卡加值',
           MAIN: '轉帳到國泰世華'}
net = {}
for r in rows:
    month = r['日期'][:7]
    amount = float(r['金額'] or 0)
    if r['類型'] in ('支出', '買進'):
        net[(r['帳戶'], month)] = net.get((r['帳戶'], month), 0) - amount
    elif r['類型'] in ('收入', '退款'):
        net[(r['帳戶'], month)] = net.get((r['帳戶'], month), 0) + amount
    elif r['類型'] == '轉帳':
        net[(r['帳戶'], month)] = net.get((r['帳戶'], month), 0) - amount
        to = r['轉入帳戶']
        net[(to, month)] = net.get((to, month), 0) + float(r['轉入金額'] or amount)
d = start
while d <= today:
    month = d.isoformat()[:7]
    for account, note in TOP_UPS.items():
        short = -net.get((account, month), 0)
        if short > 0:
            add(d, '轉帳', -(-int(short) // 500) * 500, SALARY, to=account, note=note)
    d = dt.date(d.year + (d.month == 12), d.month % 12 + 1, 1)

rows.sort(key=lambda r: r['日期'])


# Checks, so the ledger can be changed without reading it through: the
# script stops, saying what is wrong, before writing a ledger that would
# look wrong in the app. The Dart test that packs it runs this, so a
# change that breaks one fails CI before the backup is published.
LOAN_PRINCIPAL = 600000  # the 車貸 test_ledger_test.dart sets up
OWED = {LOAN} | set(CARDS)  # may stand below zero
faults = []
balance, shares = {}, {}
for r in rows:
    day, kind, account = r['日期'], r['類型'], r['帳戶']
    amount = float(r['金額'] or 0)
    if not start.isoformat() <= day <= today.isoformat():
        faults.append(f'{day} {kind} {r["備註"]}: outside {start} to {today}')
    fee, tax = float(r['手續費'] or 0), float(r['稅'] or 0)
    moves = {'收入': [(account, amount)], '退款': [(account, amount)],
             '股息': [(account, amount)], '支出': [(account, -amount)],
             '買進': [(account, -amount - fee)], '賣出': [(account, amount - fee - tax)],
             '轉帳': [(account, -amount), (r['轉入帳戶'], float(r['轉入金額'] or amount))],
             '配股': []}[kind]
    for name, change in moves:
        balance[name] = balance.get(name, 0) + change
        if name not in OWED and balance[name] < -0.005:
            faults.append(f'{day} {name} falls to {balance[name]:,.0f} ({kind} {r["備註"]})')
    code = r['代號']
    if kind in ('買進', '賣出', '配股'):
        shares[code] = shares.get(code, 0) + int(r['股數']) * (-1 if kind == '賣出' else 1)
        if shares[code] < 0:
            faults.append(f'{day} sells {r["股數"]} of {code}, more than held')
    if kind == '股息' and shares.get(code, 0) <= 0:
        faults.append(f'{day} a dividend on {code}, none held')
if balance.get(LOAN, 0) > LOAN_PRINCIPAL:
    faults.append(f'{LOAN} repaid {balance[LOAN]:,.0f}, more than its {LOAN_PRINCIPAL:,}')
for card in CARDS:
    # What a card still owes is the bills not yet due, instalments to come
    # included: every bill due by today was paid.
    unpaid = sum(total for (c, y, mo), total in bills.items() if c == card and total > 0
                 and (dt.date(y, mo, CARDS[c][1]) if CARDS[c][1] > CARDS[c][0]
                      else dt.date(y + (mo == 12), mo % 12 + 1, CARDS[c][1])) > today)
    if round(-balance.get(card, 0)) != round(unpaid):
        faults.append(f'{card} owes {-balance.get(card, 0):,.0f}, its unpaid bills {unpaid:,.0f}')
if faults:
    sys.exit('The test ledger is not right:\n' + '\n'.join(faults[:20]))

with open(sys.argv[1], 'w', encoding='utf-8-sig', newline='') as f:
    w = csv.DictWriter(f, fieldnames=HEAD)
    w.writeheader()
    w.writerows(rows)
print(len(rows), 'rows')
