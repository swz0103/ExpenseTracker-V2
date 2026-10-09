"""The app's icons, defined once.

Writes lib/src/look/glyphs.dart (the painter the app uses) and, with
--sheet PATH, a PNG contact sheet for review. Run from the package root:

    python3 tool/glyphs.py [--sheet glyphs.png]

Each icon sits on a 24-unit grid and has up to three layers:
  tint  filled with the icon colour at low opacity (a soft body)
  line  stroked at one weight, round caps and joins
  solid filled with the full colour (dots)

Shapes:
  ("poly", [x, y, ...], closed)
  ("box", l, t, r, b, radius)
  ("ring", cx, cy, r)
  ("arc", cx, cy, r, from_deg, sweep_deg)      angles clockwise from +x
  ("path", [("M", x, y), ("L", x, y), ("Q", cx, cy, x, y),
            ("A", cx, cy, r, from_deg, sweep_deg), ("Z",)])
"""

import math
import sys

T, L, S = "tint", "line", "solid"


def poly(*xy, closed=False):
    return ("poly", list(xy), closed)


def box(l, t, r, b, radius):
    return ("box", l, t, r, b, radius)


def ring(cx, cy, r):
    return ("ring", cx, cy, r)


def arc(cx, cy, r, start, sweep):
    return ("arc", cx, cy, r, start, sweep)


def path(*cmds):
    return ("path", list(cmds))


TRAY_TINT = box(4, 14.5, 20, 19.5, 0)
TRAY = [
    poly(4, 12.5, 4, 19.5, 20, 19.5, 20, 12.5),
    poly(4, 14.5, 9, 14.5, 10, 16.5, 14, 16.5, 15, 14.5, 20, 14.5),
]
CALENDAR = [
    box(4, 5.5, 20, 20, 2.5),
    poly(4, 10, 20, 10),
    poly(8.5, 3.5, 8.5, 7),
    poly(15.5, 3.5, 15.5, 7),
]

ICONS = {
    # Categories.
    "home": {
        T: [poly(6, 10, 12, 5, 18, 10, 18, 19.5, 6, 19.5, closed=True)],
        L: [
            poly(3.5, 11.5, 12, 4.2, 20.5, 11.5),
            poly(6, 9.8, 6, 19.5, 18, 19.5, 18, 9.8),
            poly(10, 19.5, 10, 14.5, 14, 14.5, 14, 19.5),
        ],
    },
    "food": {
        T: [path(("M", 4, 12), ("L", 20, 12), ("A", 12, 12, 8, 0, 180),
                 ("Z",))],
        L: [
            path(("M", 4, 12), ("L", 20, 12), ("A", 12, 12, 8, 0, 180),
                 ("Z",)),
            poly(13.5, 9.5, 19, 3.5),
            poly(10.5, 9.5, 15, 3.5),
        ],
    },
    "travel": {
        T: [box(5, 4, 19, 17, 3)],
        L: [
            box(5, 4, 19, 17, 3),
            poly(5, 10.5, 19, 10.5),
            poly(9.5, 6.8, 14.5, 6.8),
            poly(8, 17, 8, 20),
            poly(16, 17, 16, 20),
        ],
        S: [ring(8.5, 13.8, 1.1), ring(15.5, 13.8, 1.1)],
    },
    "bag": {
        T: [box(4.5, 8, 19.5, 20.5, 2.5)],
        L: [
            box(4.5, 8, 19.5, 20.5, 2.5),
            path(("M", 8.5, 11), ("L", 8.5, 7), ("A", 12, 7, 3.5, 180, 180),
                 ("L", 15.5, 11)),
        ],
    },
    "subscription": {
        T: [box(4, 5.5, 20, 10, 2.5)],
        L: CALENDAR + [poly(9, 15, 11, 17, 15, 13)],
    },
    "other": {S: [ring(6, 12, 1.5), ring(12, 12, 1.5), ring(18, 12, 1.5)]},
    "salary": {
        T: [box(3, 8.5, 18.5, 18, 2)],
        L: [
            poly(6.5, 8.5, 6.5, 5.5, 21, 5.5, 21, 15, 18.5, 15),
            box(3, 8.5, 18.5, 18, 2),
            ring(10.75, 13.25, 2.3),
        ],
        S: [ring(6.2, 13.25, 0.9), ring(15.3, 13.25, 0.9)],
    },
    "payout": {
        T: [path(("M", 6, 3.5), ("L", 18, 3.5), ("L", 18, 20.5), ("L", 16, 19),
                 ("L", 14, 20.5), ("L", 12, 19), ("L", 10, 20.5), ("L", 8, 19),
                 ("L", 6, 20.5), ("Z",))],
        L: [
            path(("M", 6, 3.5), ("L", 18, 3.5), ("L", 18, 20.5), ("L", 16, 19),
                 ("L", 14, 20.5), ("L", 12, 19), ("L", 10, 20.5), ("L", 8, 19),
                 ("L", 6, 20.5), ("Z",)),
            poly(9, 8, 15, 8),
            poly(9, 11.5, 15, 11.5),
            poly(9, 15, 12.5, 15),
        ],
    },
    "income": {
        T: [path(("M", 9, 9), ("Q", 4, 12.5, 4.5, 16.5), ("Q", 5, 20.5, 12, 20.5),
                 ("Q", 19, 20.5, 19.5, 16.5), ("Q", 20, 12.5, 15, 9), ("Z",))],
        L: [
            path(("M", 9, 9), ("Q", 4, 12.5, 4.5, 16.5), ("Q", 5, 20.5, 12, 20.5),
                 ("Q", 19, 20.5, 19.5, 16.5), ("Q", 20, 12.5, 15, 9), ("Z",)),
            path(("M", 9, 9), ("L", 7.5, 4.5), ("Q", 12, 6, 16.5, 4.5),
                 ("L", 15, 9)),
            poly(12, 12.5, 12, 17.5),
            poly(9.5, 15, 14.5, 15),
        ],
    },
    "dividend": {
        T: [
            ("disc", 12, 15.5, 5),
            path(("M", 12, 8), ("Q", 7.5, 8.3, 7, 4), ("Q", 11.5, 4, 12, 8),
                 ("Z",)),
        ],
        L: [
            ring(12, 15.5, 5),
            poly(12, 10.5, 12, 7.5),
            path(("M", 12, 8), ("Q", 7.5, 8.3, 7, 4), ("Q", 11.5, 4, 12, 8)),
            path(("M", 12, 7.5), ("Q", 15.2, 7.3, 16.5, 4.5),
                 ("Q", 13, 4.3, 12, 7.5)),
        ],
        S: [ring(12, 15.5, 1.3)],
    },
    "cup": {
        T: [path(("M", 5, 8), ("L", 16, 8), ("L", 15, 18), ("Q", 14.8, 20, 13, 20),
                 ("L", 8, 20), ("Q", 6.2, 20, 6, 18), ("Z",))],
        L: [
            path(("M", 5, 8), ("L", 16, 8), ("L", 15, 18), ("Q", 14.8, 20, 13, 20),
                 ("L", 8, 20), ("Q", 6.2, 20, 6, 18), ("Z",)),
            path(("M", 15.8, 10), ("Q", 19.5, 9.8, 19.3, 12.6),
                 ("Q", 19, 15.3, 15.3, 15.3)),
            poly(9, 5.5, 9, 3.5),
            poly(12.5, 5.5, 12.5, 3.5),
        ],
    },
    "shirt": {
        T: [poly(8, 4, 4, 6.5, 5.5, 10.5, 7.5, 9.5, 7.5, 20, 16.5, 20, 16.5, 9.5,
                 18.5, 10.5, 20, 6.5, 16, 4, closed=True)],
        L: [path(("M", 8, 4), ("L", 4, 6.5), ("L", 5.5, 10.5), ("L", 7.5, 9.5),
                 ("L", 7.5, 20), ("L", 16.5, 20), ("L", 16.5, 9.5),
                 ("L", 18.5, 10.5), ("L", 20, 6.5), ("L", 16, 4),
                 ("Q", 14.5, 6.5, 12, 6.5), ("Q", 9.5, 6.5, 8, 4), ("Z",))],
    },
    "gift": {
        T: [box(5, 10.5, 19, 20, 1.5)],
        L: [
            box(3.5, 7, 20.5, 10.5, 1.5),
            poly(5, 10.5, 5, 20, 19, 20, 19, 10.5),
            poly(12, 7, 12, 20),
            path(("M", 12, 7), ("Q", 8, 2.5, 7.5, 5.3), ("Q", 7.5, 7, 12, 7)),
            path(("M", 12, 7), ("Q", 16, 2.5, 16.5, 5.3), ("Q", 16.5, 7, 12, 7)),
        ],
    },
    "book": {
        T: [path(("M", 12, 6.5), ("Q", 8, 4.5, 4, 5.5), ("L", 4, 18.5),
                 ("Q", 8, 17.5, 12, 19.5), ("Q", 16, 17.5, 20, 18.5),
                 ("L", 20, 5.5), ("Q", 16, 4.5, 12, 6.5), ("Z",))],
        L: [
            path(("M", 12, 6.5), ("Q", 8, 4.5, 4, 5.5), ("L", 4, 18.5),
                 ("Q", 8, 17.5, 12, 19.5), ("Q", 16, 17.5, 20, 18.5),
                 ("L", 20, 5.5), ("Q", 16, 4.5, 12, 6.5), ("Z",)),
            poly(12, 6.5, 12, 19.5),
        ],
    },
    "health": {
        T: [path(("M", 12, 19.5), ("Q", 4, 14, 4, 9.5), ("Q", 4, 5.5, 8, 5.5),
                 ("Q", 10.5, 5.5, 12, 8), ("Q", 13.5, 5.5, 16, 5.5),
                 ("Q", 20, 5.5, 20, 9.5), ("Q", 20, 14, 12, 19.5), ("Z",))],
        L: [
            path(("M", 12, 19.5), ("Q", 4, 14, 4, 9.5), ("Q", 4, 5.5, 8, 5.5),
                 ("Q", 10.5, 5.5, 12, 8), ("Q", 13.5, 5.5, 16, 5.5),
                 ("Q", 20, 5.5, 20, 9.5), ("Q", 20, 14, 12, 19.5), ("Z",)),
            poly(12, 10, 12, 15),
            poly(9.5, 12.5, 14.5, 12.5),
        ],
    },
    "pet": {
        T: [("disc", 12, 15.5, 4.2)],
        L: [ring(12, 15.5, 4.2)],
        S: [ring(6, 11, 1.9), ring(9.3, 6.8, 1.9), ring(14.7, 6.8, 1.9),
            ring(18, 11, 1.9)],
    },
    "car": {
        T: [poly(3.5, 16, 3.5, 11.5, 6.5, 11.5, 8.5, 6.5, 15.5, 6.5, 17.5, 11.5,
                 20.5, 11.5, 20.5, 16, closed=True)],
        L: [
            path(("M", 3.5, 16), ("L", 3.5, 12.5), ("Q", 3.5, 11.5, 4.5, 11.5),
                 ("L", 6.5, 11.5), ("L", 8.5, 6.5), ("L", 15.5, 6.5),
                 ("L", 17.5, 11.5), ("L", 19.5, 11.5), ("Q", 20.5, 11.5, 20.5, 12.5),
                 ("L", 20.5, 16), ("Z",)),
            poly(12, 6.5, 12, 11.5),
        ],
        S: [ring(7.5, 18, 2), ring(16.5, 18, 2)],
    },
    "game": {
        T: [box(3, 8, 21, 17, 4.5)],
        L: [box(3, 8, 21, 17, 4.5), poly(7.5, 10.8, 7.5, 14.2),
            poly(5.8, 12.5, 9.2, 12.5)],
        S: [ring(15.3, 11.3, 1.1), ring(17.5, 13.6, 1.1)],
    },
    "transfer": {
        L: [
            poly(5, 8.5, 19, 8.5),
            poly(15.5, 5, 19, 8.5, 15.5, 12),
            poly(19, 15.5, 5, 15.5),
            poly(8.5, 12, 5, 15.5, 8.5, 19),
        ],
    },
    "investment": {
        T: [poly(4, 17, 9, 12, 13, 15, 20, 7.5, 20, 20, 4, 20, closed=True)],
        L: [
            poly(4, 17, 9, 12, 13, 15, 20, 7.5),
            poly(15.5, 7.5, 20, 7.5, 20, 12),
        ],
    },
    # Accounts.
    "cash": {
        T: [box(3, 6.5, 21, 17.5, 2.5)],
        L: [box(3, 6.5, 21, 17.5, 2.5), ring(12, 12, 2.7)],
        S: [ring(6.5, 12, 1), ring(17.5, 12, 1)],
    },
    "bank": {
        T: [poly(3.5, 9.5, 12, 4.5, 20.5, 9.5, closed=True)],
        L: [
            poly(3.5, 9.5, 12, 4.5, 20.5, 9.5, closed=True),
            poly(7, 12.5, 7, 17),
            poly(12, 12.5, 12, 17),
            poly(17, 12.5, 17, 17),
            poly(4, 20, 20, 20),
        ],
    },
    "phone": {
        T: [box(7, 3, 17, 21, 2.5)],
        L: [box(7, 3, 17, 21, 2.5), poly(10.5, 18, 13.5, 18)],
    },
    "card": {
        T: [box(3, 6, 21, 10, 2.5)],
        L: [box(3, 6, 21, 18, 2.5), poly(3, 10, 21, 10),
            poly(6.5, 14.5, 10, 14.5)],
    },
    "coins": {
        T: [("disc", 8.5, 9, 4.5), box(10.5, 14.5, 20.5, 21, 1.75)],
        L: [ring(8.5, 9, 4.5), box(10.5, 14.5, 20.5, 17.75, 1.6),
            box(10.5, 17.75, 20.5, 21, 1.6)],
    },
    "safe": {
        T: [box(4, 4, 20, 19, 2.5)],
        L: [box(4, 4, 20, 19, 2.5), ring(12, 11.5, 3.5),
            poly(7.5, 19, 7.5, 21), poly(16.5, 19, 16.5, 21)],
        S: [ring(12, 11.5, 1)],
    },
    "suitcase": {
        T: [box(5, 7, 19, 20, 2.5)],
        L: [
            box(5, 7, 19, 20, 2.5),
            poly(9.5, 7, 9.5, 4.5, 14.5, 4.5, 14.5, 7),
            poly(9, 10.5, 9, 16.5),
            poly(15, 10.5, 15, 16.5),
        ],
    },
    "briefcase": {
        T: [box(3.5, 8, 20.5, 19.5, 2.5)],
        L: [box(3.5, 8, 20.5, 19.5, 2.5), poly(9, 8, 9, 5, 15, 5, 15, 8),
            poly(3.5, 13, 20.5, 13)],
    },
    "chat": {
        T: [box(4, 5, 20, 16.5, 3)],
        L: [box(4, 5, 20, 16.5, 3), poly(8, 16.5, 8, 20, 12, 16.5)],
        S: [ring(9, 10.75, 1), ring(12, 10.75, 1), ring(15, 10.75, 1)],
    },
    "store": {
        T: [poly(4, 9.5, 5.5, 4.5, 18.5, 4.5, 20, 9.5, closed=True)],
        L: [
            poly(4, 9.5, 5.5, 4.5, 18.5, 4.5, 20, 9.5, closed=True),
            poly(5.5, 9.5, 5.5, 19.5, 18.5, 19.5, 18.5, 9.5),
            poly(10, 19.5, 10, 15, 14, 15, 14, 19.5),
        ],
    },
    "scan": {
        T: [box(7.5, 7.5, 16.5, 16.5, 2)],
        L: [
            poly(4, 8, 4, 4, 8, 4),
            poly(16, 4, 20, 4, 20, 8),
            poly(20, 16, 20, 20, 16, 20),
            poly(8, 20, 4, 20, 4, 16),
            poly(6.5, 12, 17.5, 12),
        ],
    },
    "ticket": {
        T: [box(3.5, 6.5, 20.5, 17.5, 2.5)],
        L: [box(3.5, 6.5, 20.5, 17.5, 2.5), poly(14.5, 9, 14.5, 10.3),
            poly(14.5, 11.4, 14.5, 12.7), poly(14.5, 13.8, 14.5, 15)],
    },
    # Tabs and tools.
    "overview": {
        T: [box(4, 4, 10.5, 12, 1.8)],
        L: [box(4, 4, 10.5, 12, 1.8), box(13.5, 4, 20, 8.5, 1.8),
            box(13.5, 11.5, 20, 20, 1.8), box(4, 15, 10.5, 20, 1.8)],
    },
    "records": {
        T: [box(5, 3.5, 19, 20.5, 2.5)],
        L: [box(5, 3.5, 19, 20.5, 2.5), poly(8.5, 8.5, 15.5, 8.5),
            poly(8.5, 12, 15.5, 12), poly(8.5, 15.5, 12.5, 15.5)],
    },
    "wallet": {
        T: [box(3.5, 6.5, 20.5, 19.5, 2.5)],
        L: [box(3.5, 6.5, 20.5, 19.5, 2.5), poly(6, 6.5, 15, 3.8, 16, 6.5),
            box(14, 10.5, 20.5, 15, 1.6)],
        S: [ring(16.6, 12.75, 0.95)],
    },
    "reports": {
        T: [box(5.5, 12, 8.5, 19, 1), box(10.5, 6, 13.5, 19, 1),
            box(15.5, 9.5, 18.5, 19, 1)],
        L: [box(5.5, 12, 8.5, 19, 1), box(10.5, 6, 13.5, 19, 1),
            box(15.5, 9.5, 18.5, 19, 1), poly(3.5, 20.5, 20.5, 20.5)],
    },
    "budget": {
        T: [path(("M", 12, 12), ("L", 12, 4), ("A", 12, 12, 8, 270, 120),
                 ("Z",))],
        L: [ring(12, 12, 8), poly(12, 4, 12, 12, 18.93, 16)],
    },
    "recurring": {
        L: [
            arc(12, 12, 7, 200, 130),
            poly(18.4, 4.9, 18.1, 8.5, 14.6, 8.1),
            arc(12, 12, 7, 20, 130),
            poly(5.6, 19.1, 5.9, 15.5, 9.4, 15.9),
        ],
    },
    "categories": {
        T: [box(4, 4, 10.5, 10.5, 1.8)],
        L: [box(4, 4, 10.5, 10.5, 1.8), box(13.5, 4, 20, 10.5, 1.8),
            box(4, 13.5, 10.5, 20, 1.8), ring(16.75, 16.75, 3.25)],
    },
    "sliders": {
        L: [
            poly(4, 7.5, 6.8, 7.5), poly(11.2, 7.5, 20, 7.5),
            ring(9, 7.5, 2.2),
            poly(4, 16.5, 12.8, 16.5), poly(17.2, 16.5, 20, 16.5),
            ring(15, 16.5, 2.2),
        ],
    },
    # Controls: line only.
    "add": {L: [poly(12, 5, 12, 19), poly(5, 12, 19, 12)]},
    "back": {L: [poly(14.5, 5.5, 8, 12, 14.5, 18.5)]},
    "next": {L: [poly(9.5, 5.5, 16, 12, 9.5, 18.5)]},
    "arrow": {L: [poly(5, 12, 19, 12), poly(14, 7, 19, 12, 14, 17)]},
    "close": {L: [poly(6.5, 6.5, 17.5, 17.5), poly(17.5, 6.5, 6.5, 17.5)]},
    "search": {L: [ring(10.5, 10.5, 6), poly(15, 15, 19.5, 19.5)]},
    "download": {
        L: [poly(12, 4, 12, 14.5), poly(7.5, 10, 12, 14.5, 16.5, 10),
            poly(4.5, 15, 4.5, 19.5, 19.5, 19.5, 19.5, 15)],
    },
    "edit": {
        L: [poly(5, 19, 5, 15.5, 15.5, 5, 19, 8.5, 8.5, 19, closed=True),
            poly(13, 7.5, 16.5, 11)],
    },
    "calendar": {
        T: [box(4, 5.5, 20, 10, 2.5)],
        L: CALENDAR,
        S: [ring(8.5, 14.5, 1), ring(12, 14.5, 1), ring(15.5, 14.5, 1)],
    },
    "note": {L: [poly(5, 7, 19, 7), poly(5, 12, 19, 12), poly(5, 17, 13, 17)]},
    "eye": {
        L: [path(("M", 2.5, 12), ("Q", 12, 3, 21.5, 12), ("Q", 12, 21, 2.5, 12)),
            ring(12, 12, 3)],
    },
    "eyeOff": {
        L: [path(("M", 2.5, 12), ("Q", 12, 3, 21.5, 12), ("Q", 12, 21, 2.5, 12)),
            ring(12, 12, 3), poly(4.5, 4.5, 19.5, 19.5)],
    },
    "calculator": {
        T: [box(8, 6, 16, 9.5, 1)],
        L: [box(5, 3, 19, 21, 2.5), box(8, 6, 16, 9.5, 1)],
        S: [ring(x, y, 0.95) for y in (13.5, 17.5) for x in (9, 12, 15)],
    },
    "backspace": {
        L: [poly(8.5, 6, 20, 6, 20, 18, 8.5, 18, 3.5, 12, closed=True),
            poly(11.5, 9.5, 16.5, 14.5), poly(16.5, 9.5, 11.5, 14.5)],
    },
    "reset": {
        L: [arc(12, 12, 7, 210, 290), poly(5.5, 4.4, 5.9, 8.5, 9.9, 8)],
    },
}


# Dart output.

def num(v):
    s = ("%.2f" % v).rstrip("0").rstrip(".")
    return s if s not in ("-0",) else "0"


def dart_shape(var, shape):
    kind = shape[0]
    if kind == "poly":
        pts = ", ".join(num(v) for v in shape[1])
        close = ", close: true" if shape[2] else ""
        return f"_poly({var}, [{pts}]{close});"
    if kind == "box":
        return "_box(%s, %s);" % (var, ", ".join(num(v) for v in shape[1:]))
    if kind in ("ring", "disc"):
        return "_ring(%s, %s);" % (var, ", ".join(num(v) for v in shape[1:]))
    if kind == "arc":
        return "_arc(%s, %s);" % (var, ", ".join(num(v) for v in shape[1:]))
    if kind == "path":
        out = []
        for c in shape[1]:
            op = c[0]
            a = [num(v) for v in c[1:]]
            if op == "M":
                out.append(f"{var}.moveTo({a[0]}, {a[1]});")
            elif op == "L":
                out.append(f"{var}.lineTo({a[0]}, {a[1]});")
            elif op == "Q":
                out.append(f"{var}.quadraticBezierTo({', '.join(a)});")
            elif op == "A":
                out.append(f"_arcTo({var}, {', '.join(a)});")
            elif op == "Z":
                out.append(f"{var}.close();")
        return out
    raise ValueError(kind)


def wrap_call(line, indent):
    """Breaks a call over lines the way dart format does when too long."""
    if len(indent) + len(line) <= 80:
        return [indent + line]
    head, rest = line.split("(", 1)
    args = rest[:-2]  # drop ");"
    if args.endswith("]") or "[" in args:
        var, lst = args.split(", [", 1)
        lst, tail = lst.rsplit("]", 1)
        items = lst.split(", ")
        out = [f"{indent}{head}({var}, ["]
        row = ""
        for it in items:
            piece = it + ","
            if row and len(indent) + 2 + len(row) + 1 + len(piece) > 80:
                out.append(indent + "  " + row)
                row = piece
            else:
                row = (row + " " + piece).strip()
        out.append(indent + "  " + row)
        out.append(f"{indent}]{tail});")
        return out
    parts = args.split(", ")
    return ([f"{indent}{head}("] + [f"{indent}  {p}," for p in parts]
            + [f"{indent});"])


def dart():
    names = list(ICONS)
    cases = []
    for name, layers in ICONS.items():
        cases.append(f"    case Glyph.{name}:")
        for layer, var in ((T, "t"), (L, "p"), (S, "f")):
            for shape in layers.get(layer, []):
                stmts = dart_shape(var, shape)
                for st in stmts if isinstance(stmts, list) else [stmts]:
                    cases.extend(wrap_call(st, "      "))
    enum = "\n".join(f"  {n}," for n in names)
    return DART.replace("%ENUM%", enum).replace("%CASES%", "\n".join(cases))


DART = '''// Generated by tool/glyphs.py; edit the icons there and run it again.

import 'dart:math';

import 'package:flutter/widgets.dart';

/// The app's own icons, drawn on a 24-unit grid: a soft tinted body, one
/// stroke weight and solid dots, so they read as one set. Painted on the
/// canvas, never loaded as images.
enum Glyph {
%ENUM%
}

/// A [Glyph] at [size], in [color] or the surrounding icon colour. With
/// [tinted] off only the strokes and dots are drawn.
class GlyphIcon extends StatelessWidget {
  const GlyphIcon(
    this.glyph, {
    super.key,
    this.size = 22,
    this.color,
    this.weight = 1.6,
    this.tinted = true,
  });

  final Glyph glyph;
  final double size;
  final Color? color;

  /// Stroke width in logical pixels.
  final double weight;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? IconTheme.of(context).color ?? const Color(0xFF344638);
    // Like Icon, keep the drawn size when the parent asks for more room.
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: GlyphPainter(glyph, ink, weight, tinted: tinted),
        ),
      ),
    );
  }
}

class GlyphPainter extends CustomPainter {
  const GlyphPainter(this.glyph, this.color, this.weight, {this.tinted = true});

  final Glyph glyph;
  final Color color;
  final double weight;
  final bool tinted;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    if (scale <= 0) return;
    final (tint, line, solid) = _paths[glyph] ??= _build(glyph);
    canvas
      ..save()
      ..translate((size.width - 24 * scale) / 2, (size.height - 24 * scale) / 2)
      ..scale(scale);
    if (tinted) {
      canvas.drawPath(tint, Paint()..color = color.withValues(alpha: 0.28));
    }
    canvas
      ..drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = weight / scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      )
      ..drawPath(solid, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(GlyphPainter old) =>
      old.glyph != glyph ||
      old.color != color ||
      old.weight != weight ||
      old.tinted != tinted;
}

/// Each glyph's paths, built once on the 24-unit grid and reused by every
/// icon that shows it.
final _paths = <Glyph, (Path, Path, Path)>{};

(Path, Path, Path) _build(Glyph glyph) {
  final tint = Path();
  final line = Path();
  final solid = Path();
  _draw(glyph, tint, line, solid);
  return (tint, line, solid);
}

void _poly(Path p, List<double> xy, {bool close = false}) {
  p.moveTo(xy[0], xy[1]);
  for (var i = 2; i < xy.length; i += 2) {
    p.lineTo(xy[i], xy[i + 1]);
  }
  if (close) p.close();
}

void _box(Path p, double l, double t, double r, double b, double radius) {
  p.addRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(radius)));
}

void _ring(Path p, double x, double y, double r) {
  p.addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
}

void _arc(Path p, double x, double y, double r, double from, double sweep) {
  p.addArc(
    Rect.fromCircle(center: Offset(x, y), radius: r),
    from * pi / 180,
    sweep * pi / 180,
  );
}

void _arcTo(Path p, double x, double y, double r, double from, double sweep) {
  p.arcTo(
    Rect.fromCircle(center: Offset(x, y), radius: r),
    from * pi / 180,
    sweep * pi / 180,
    false,
  );
}

void _draw(Glyph glyph, Path t, Path p, Path f) {
  switch (glyph) {
%CASES%
  }
}
'''


# Contact sheet.

def flatten(shape):
    """Polylines (list of (points, closed)) for one shape, in grid units."""
    kind = shape[0]
    if kind == "poly":
        xy = shape[1]
        return [([(xy[i], xy[i + 1]) for i in range(0, len(xy), 2)], shape[2])]
    if kind == "box":
        l, t, r, b, rad = shape[1:]
        pts = []
        for cx, cy, a0 in ((r - rad, t + rad, 270), (r - rad, b - rad, 0),
                           (l + rad, b - rad, 90), (l + rad, t + rad, 180)):
            for k in range(9):
                a = math.radians(a0 + k * 90 / 8)
                pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))
        return [(pts, True)]
    if kind in ("ring", "disc"):
        cx, cy, r = shape[1:]
        return [([(cx + r * math.cos(a / 40 * 2 * math.pi),
                   cy + r * math.sin(a / 40 * 2 * math.pi))
                  for a in range(40)], True)]
    if kind == "arc":
        cx, cy, r, a0, sw = shape[1:]
        return [([(cx + r * math.cos(math.radians(a0 + sw * k / 30)),
                   cy + r * math.sin(math.radians(a0 + sw * k / 30)))
                  for k in range(31)], False)]
    if kind == "path":
        out, cur, pos = [], [], (0, 0)
        for c in shape[1]:
            op = c[0]
            if op == "M":
                if cur:
                    out.append((cur, False))
                pos = c[1:3]
                cur = [pos]
            elif op == "L":
                pos = c[1:3]
                cur.append(pos)
            elif op == "Q":
                x0, y0 = pos
                cx, cy, x, y = c[1:]
                for k in range(1, 13):
                    s = k / 12
                    cur.append(((1 - s) ** 2 * x0 + 2 * (1 - s) * s * cx + s * s * x,
                                (1 - s) ** 2 * y0 + 2 * (1 - s) * s * cy + s * s * y))
                pos = (x, y)
            elif op == "A":
                cx, cy, r, a0, sw = c[1:]
                for k in range(31):
                    a = math.radians(a0 + sw * k / 30)
                    cur.append((cx + r * math.cos(a), cy + r * math.sin(a)))
                pos = cur[-1]
            elif op == "Z":
                out.append((cur, True))
                cur = []
        if cur:
            out.append((cur, False))
        return out
    raise ValueError(kind)


def render(name, px, color, weight=1.6, tinted=True, bg=None):
    from PIL import Image, ImageDraw
    k = 8
    big = px * k
    u = big / 24
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    layers = ICONS[name]
    if tinted and layers.get(T):
        tint = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        d = ImageDraw.Draw(tint)
        for shape in layers[T]:
            for pts, _ in flatten(shape):
                d.polygon([(x * u, y * u) for x, y in pts], fill=color + (71,))
        img = Image.alpha_composite(img, tint)
    d = ImageDraw.Draw(img)
    w = max(1, round(weight * k * px / 22))
    for shape in layers.get(L, []):
        for pts, closed in flatten(shape):
            q = [(x * u, y * u) for x, y in pts]
            if closed:
                q = q + [q[0]]
            d.line(q, fill=color + (255,), width=w, joint="curve")
            for x, y in (q[0], q[-1]):
                d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2],
                          fill=color + (255,))
    for shape in layers.get(S, []):
        for pts, _ in flatten(shape):
            d.polygon([(x * u, y * u) for x, y in pts], fill=color + (255,))
    return img.resize((px, px), Image.LANCZOS)


def sheet(path_out, px=48):
    from PIL import Image, ImageDraw, ImageFont
    names = list(ICONS)
    cols = 8
    cell = px + 56
    rows = (len(names) + cols - 1) // cols
    out = Image.new("RGB", (cols * cell + 20, rows * (cell + 10) + 20),
                    (247, 242, 231))
    d = ImageDraw.Draw(out)
    try:
        font = ImageFont.truetype("fonts/NotoSansTC-Regular.ttf", 13)
    except OSError:
        font = None
    colors = [(52, 70, 56), (139, 64, 59), (49, 93, 71), (82, 119, 126),
              (118, 101, 138), (180, 154, 85)]
    for i, name in enumerate(names):
        x = 10 + (i % cols) * cell
        y = 10 + (i // cols) * (cell + 10)
        color = colors[i % len(colors)]
        soft = tuple(int(c * 0.18 + p * 0.82) for c, p in zip(color, (247, 242, 231)))
        d.rounded_rectangle([x + 18, y + 4, x + 18 + px + 20, y + 24 + px],
                            radius=14, fill=soft)
        icon = render(name, px, color)
        out.paste(icon, (x + 28, y + 14), icon)
        d.text((x + cell / 2, y + px + 38), name, fill=(116, 121, 108),
               anchor="mm", font=font)
    out.save(path_out)


if __name__ == "__main__":
    with open("lib/src/look/glyphs.dart", "w") as fh:
        fh.write(dart())
    if "--sheet" in sys.argv:
        sheet(sys.argv[sys.argv.index("--sheet") + 1])
