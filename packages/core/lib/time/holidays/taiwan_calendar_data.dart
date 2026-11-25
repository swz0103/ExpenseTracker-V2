// DATA FILE: edit the table, not the code around it.
//
// Taiwan's days off and make-up workdays that differ from "Saturday and
// Sunday off": every weekday the government offices are closed
// (`holiday`) and every weekend day they work (`workday`). A holiday that
// falls on a weekend is not listed, since the weekend already covers it.
//
// Source: 行政院人事行政總處「中華民國政府行政機關辦公日曆表」, the
// official open data set https://data.gov.tw/dataset/14718, files:
//   2025 (民國 114 年, 1141020 更新): https://www.dgpa.gov.tw/FileConversion?filename=dgpa/files/202510/b84cb88a-803c-4621-a843-d637b2775615.csv
//   2026 (民國 115 年): https://www.dgpa.gov.tw/FileConversion?filename=dgpa/files/202506/a52331bd-a189-466b-b0f0-cae3062bbf74.csv
//   2027 (民國 116 年): https://www.dgpa.gov.tw/FileConversion?filename=dgpa/files/202607/f538b1ff-ba60-4c63-9477-10db8e6612d1.csv
// Retrieved: 2026-11-22. Rows are the days whose 是否放假 differs from
// the weekend rule, with its 備註 as the name.
//
// To add a year: append its rows and add the year to the `years:` line;
// a year not listed there is not verified, and callers fall back to
// weekends only.

/// The table, one row per line: `date,holiday|workday,name`.
const taiwanCalendarTable = '''
years:2025,2026,2027
2025-01-01,holiday,開國紀念日
2025-01-27,holiday,小年夜
2025-01-28,holiday,農曆除夕
2025-01-29,holiday,春節
2025-01-30,holiday,春節
2025-01-31,holiday,春節
2025-02-08,workday,補行上班
2025-02-28,holiday,和平紀念日
2025-04-03,holiday,補假
2025-04-04,holiday,兒童節及民族掃墓節
2025-05-30,holiday,補假
2025-09-29,holiday,補假
2025-10-06,holiday,中秋節
2025-10-10,holiday,國慶日
2025-10-24,holiday,補假
2025-12-25,holiday,行憲紀念日
2026-01-01,holiday,開國紀念日
2026-02-16,holiday,農曆除夕
2026-02-17,holiday,春節
2026-02-18,holiday,春節
2026-02-19,holiday,春節
2026-02-20,holiday,補假
2026-02-27,holiday,補假
2026-04-03,holiday,補假
2026-04-06,holiday,補假
2026-05-01,holiday,勞動節
2026-06-19,holiday,端午節
2026-09-25,holiday,中秋節
2026-09-28,holiday,孔子誕辰紀念日/教師節
2026-10-09,holiday,補假
2026-10-26,holiday,補假
2026-12-25,holiday,行憲紀念日
2027-01-01,holiday,開國紀念日
2027-02-04,holiday,小年夜
2027-02-05,holiday,農曆除夕
2027-02-08,holiday,春節
2027-02-09,holiday,補假
2027-02-10,holiday,補假
2027-03-01,holiday,補假
2027-04-05,holiday,清明節
2027-04-06,holiday,補假
2027-04-30,holiday,補假
2027-06-09,holiday,端午節
2027-09-15,holiday,中秋節
2027-09-28,holiday,孔子誕辰紀念日/教師節
2027-10-11,holiday,補假
2027-10-25,holiday,臺灣光復暨金門古寧頭大捷紀念日
2027-12-24,holiday,補假
2027-12-31,holiday,補假
''';
