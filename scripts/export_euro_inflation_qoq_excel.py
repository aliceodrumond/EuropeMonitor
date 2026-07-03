from __future__ import annotations

import csv
from collections import OrderedDict
from datetime import datetime
from pathlib import Path

import xlsxwriter


ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "public" / "data" / "inflation_series.csv"
OUTPUT_PATH = ROOT / "exports" / "euro_area_qoq_saar_inflation_10y.xlsx"

SERIES = OrderedDict(
    [
        ("Headline", "hicp_headline_qoq_saar"),
        ("Core", "hicp_core_qoq_saar"),
        ("Goods", "hicp_goods_qoq_saar"),
        ("Services", "hicp_services_qoq_saar"),
    ]
)

COLORS = {
    "Headline": "#191919",
    "Core": "#A83F39",
    "Goods": "#11675F",
    "Services": "#65B88F",
}


def load_rows() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with CSV_PATH.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            if row["series_id"] not in SERIES.values():
                continue
            if row["country"] != "Euro Area":
                continue
            rows.append(row)
    return rows


def build_table(rows: list[dict[str, str]]) -> list[tuple[datetime, dict[str, float | None]]]:
    by_date: dict[str, dict[str, float | None]] = {}
    for row in rows:
        date_key = row["date"]
        date_bucket = by_date.setdefault(date_key, {name: None for name in SERIES})
        for name, series_id in SERIES.items():
            if row["series_id"] == series_id:
                date_bucket[name] = float(row["value"])
                break

    cutoff = datetime(2016, 1, 1)
    table: list[tuple[datetime, dict[str, float | None]]] = []
    for date_key in sorted(by_date):
        dt = datetime.strptime(date_key, "%Y-%m-%d")
        if dt < cutoff:
            continue
        table.append((dt, by_date[date_key]))
    return table


def create_workbook(table: list[tuple[datetime, dict[str, float | None]]]) -> None:
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    workbook = xlsxwriter.Workbook(OUTPUT_PATH)
    worksheet = workbook.add_worksheet("QoQ SAAR")

    bg = "#F7F7F5"
    paper = "#FFFFFF"
    ink = "#191919"
    muted = "#707070"
    line = "#E4E1DA"

    workbook.set_custom_property("Source", str(CSV_PATH))

    title_fmt = workbook.add_format(
        {
            "bold": True,
            "font_size": 16,
            "font_color": ink,
            "bg_color": paper,
            "border": 0,
        }
    )
    subtitle_fmt = workbook.add_format(
        {
            "font_size": 10,
            "font_color": muted,
            "bg_color": paper,
        }
    )
    header_fmt = workbook.add_format(
        {
            "bold": True,
            "font_color": ink,
            "bg_color": bg,
            "bottom": 1,
            "bottom_color": line,
            "num_format": "@",
        }
    )
    date_fmt = workbook.add_format(
        {
            "num_format": "mmm/yy",
            "font_color": ink,
            "bg_color": paper,
        }
    )
    value_fmt = workbook.add_format(
        {
            "num_format": "0.00",
            "font_color": ink,
            "bg_color": paper,
        }
    )
    note_fmt = workbook.add_format(
        {
            "font_size": 9,
            "font_color": muted,
            "text_wrap": True,
            "bg_color": paper,
        }
    )

    worksheet.hide_gridlines(2)
    worksheet.set_zoom(90)
    worksheet.set_default_row(20)
    worksheet.set_column("A:A", 13)
    worksheet.set_column("B:E", 12)

    worksheet.write("A1", "Euro Area Inflation", title_fmt)
    worksheet.write("A2", "% QoQ SAAR | 10Y window | Headline, Core, Goods, Services", subtitle_fmt)
    worksheet.write_row("A4", ["Date", *SERIES.keys()], header_fmt)

    for row_idx, (dt, values) in enumerate(table, start=4):
        worksheet.write_datetime(row_idx, 0, dt, date_fmt)
        for col_idx, name in enumerate(SERIES.keys(), start=1):
            value = values[name]
            if value is None:
                worksheet.write_blank(row_idx, col_idx, None, value_fmt)
            else:
                worksheet.write_number(row_idx, col_idx, value, value_fmt)

    last_row = len(table) + 3

    chart = workbook.add_chart({"type": "line"})
    chart.set_size({"width": 1120, "height": 560})
    chart.set_title({"name": "Euro Area HICP Components | % QoQ SAAR"})
    chart.set_chartarea({"fill": {"color": paper}, "border": {"none": True}})
    chart.set_plotarea(
        {
            "fill": {"color": paper},
            "border": {"color": line},
        }
    )
    chart.set_legend({"position": "top"})
    chart.set_x_axis(
        {
            "date_axis": True,
            "num_format": "yy",
            "line": {"color": line},
            "major_gridlines": {"visible": True, "line": {"color": line}},
            "label_position": "low",
        }
    )
    chart.set_y_axis(
        {
            "name": "%",
            "min": -2,
            "max": 8,
            "major_unit": 2,
            "line": {"color": line},
            "major_gridlines": {"visible": True, "line": {"color": line}},
            "num_format": "0.00",
            "crossing": 0,
        }
    )

    for idx, name in enumerate(SERIES.keys(), start=1):
        chart.add_series(
            {
                "name": ["QoQ SAAR", 3, idx],
                "categories": ["QoQ SAAR", 4, 0, last_row, 0],
                "values": ["QoQ SAAR", 4, idx, last_row, idx],
                "line": {"color": COLORS[name], "width": 2.25},
            }
        )

    worksheet.insert_chart("G4", chart)
    worksheet.write(
        "A{}".format(last_row + 3),
        "Source: public/data/inflation_series.csv | Series: hicp_headline_qoq_saar, hicp_core_qoq_saar, hicp_goods_qoq_saar, hicp_services_qoq_saar",
        note_fmt,
    )

    workbook.close()


def main() -> None:
    rows = load_rows()
    table = build_table(rows)
    create_workbook(table)
    print(OUTPUT_PATH)


if __name__ == "__main__":
    main()
