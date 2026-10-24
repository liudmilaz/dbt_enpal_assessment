"""Deals Overview dashboard in Lightdash, on the dbt marts fct_deals and rep_sales_funnel_monthly.

Layout follows the reference picture: KPI tiles on the left (conversion gauge, big numbers), a monthly trend, two funnels.
The export has no won/lost status and no amount: "closed" = reached Closing (stage 6); the amount tiles of the
reference are replaced by leads and by the funnel of all task steps. Data quality lives in Elementary, not here.

Usage (from lightdash/, after `lightdash deploy`): python3 -I build_funnel_dashboard.py <project-uuid>
"""
import json, sys, uuid
sys.path.insert(0, ".")
import ldapi

P = sys.argv[1]
SPACE = ldapi.call("GET", f"/api/v1/projects/{P}/spaces")["results"][0]["uuid"]

FCT, REP = "fct_deals", "rep_sales_funnel_monthly"


def flt(field, operator, values):
    return {"id": str(uuid.uuid4()), "target": {"fieldId": field}, "operator": operator, "values": values}


def query(explore, dimensions, metrics, filters=(), sorts=(), limit=500):
    q = {"exploreName": explore, "dimensions": list(dimensions), "metrics": list(metrics),
         "filters": {}, "sorts": [{"fieldId": f, "descending": d} for f, d in sorts], "limit": limit,
         "tableCalculations": [], "additionalMetrics": []}
    if filters:
        q["filters"] = {"dimensions": {"id": str(uuid.uuid4()), "and": list(filters)}}
    return q


def save(name, description, metric_query, chart_config, pivot=None):
    body = {"name": name, "description": description, "tableName": metric_query["exploreName"],
            "metricQuery": metric_query, "chartConfig": chart_config,
            "tableConfig": {"columnOrder": metric_query["dimensions"] + metric_query["metrics"]}, "spaceUuid": SPACE}
    if pivot:
        body["pivotConfig"] = {"columns": pivot}
    r = ldapi.call("POST", f"/api/v1/projects/{P}/saved", body)
    if r.get("status") != "ok":
        raise SystemExit(f"{name}: {json.dumps(r)[:800]}")
    return r["results"]["uuid"]


charts = {}

# 1. Gauge: conversion of the January 2024 lead cohort
charts["gauge"] = save(
    "Deal conversion rate: Jan 2024 cohort",
    "Deals that entered stage 1 in January 2024 and reached Closing, divided by all of them.",
    query(FCT, [], [f"{FCT}_conversion_rate"], [flt(f"{FCT}_lead_month_month", "equals", ["2024-01-01"])]),
    {"type": "gauge", "config": {"selectedField": f"{FCT}_conversion_rate", "min": 0, "max": 1, "showAxisLabels": True,
                                 "sections": [{"min": 0, "max": 0.5, "color": "#E5534B"},
                                              {"min": 0.5, "max": 0.7, "color": "#F2C744"},
                                              {"min": 0.7, "max": 1, "color": "#57CC78"}]}})

# 2. Big number: closed deals in the latest busy month, compared with the month before
charts["closed"] = save(
    "Closed deals: Oct 2024",
    "Deals that reached Closing in October 2024, compared with September 2024.",
    query(FCT, [f"{FCT}_closing_month_month"], [f"{FCT}_closed_deals"],
          [flt(f"{FCT}_closing_month_month", "inBetween", ["2024-09-01", "2024-10-01"])],
          [(f"{FCT}_closing_month_month", True)]),
    {"type": "big_number", "config": {"selectedField": f"{FCT}_closed_deals", "label": "Closed deals: Oct 2024",
                                      "showBigNumberLabel": True, "showComparison": True,
                                      "comparisonFormat": "raw", "comparisonLabel": "vs Sep 2024"}})

# 3. Big number: new leads in the last month with new deals, compared with the month before
charts["leads"] = save(
    "New leads: Sep 2024",
    "Deals that entered stage 1 in September 2024 (new deals stop on 2024-09-13), compared with August 2024.",
    query(FCT, [f"{FCT}_lead_month_month"], [f"{FCT}_leads"],
          [flt(f"{FCT}_lead_month_month", "inBetween", ["2024-08-01", "2024-09-01"])],
          [(f"{FCT}_lead_month_month", True)]),
    {"type": "big_number", "config": {"selectedField": f"{FCT}_leads", "label": "New leads: Sep 2024",
                                      "showBigNumberLabel": True, "showComparison": True,
                                      "comparisonFormat": "raw", "comparisonLabel": "vs Aug 2024"}})

# 4. Big number: average sales cycle
charts["cycle"] = save(
    "Avg sales cycle",
    "Average days from the first entry into stage 1 to Closing, over all closed deals (generated timing, D5).",
    query(FCT, [], [f"{FCT}_avg_sales_cycle_days"]),
    {"type": "big_number", "config": {"selectedField": f"{FCT}_avg_sales_cycle_days", "label": "Avg sales cycle (days)",
                                      "showBigNumberLabel": True}})

# 5. Monthly trend: leads and closed deals per month, from the report
month, step, deals = f"{REP}_month_month", f"{REP}_kpi_name", f"{REP}_total_deals"
charts["trend"] = save(
    "Monthly funnel trend",
    "Lead Generation and Closing per month (rep_sales_funnel_monthly).",
    query(REP, [month, step], [deals], [flt(step, "equals", ["Lead Generation", "Closing"])], [(month, False)]),
    {"type": "cartesian", "config": {"layout": {"xField": month, "yField": [deals]},
                                     "eChartsConfig": {"series": [
                                         {"type": "line", "encode": {"xRef": {"field": month},
                                                                     "yRef": {"field": deals, "pivotValues": [{"field": step, "value": v}]}},
                                          "smooth": True}
                                         for v in ["Lead Generation", "Closing"]]}}},
    pivot=[step])

# 6. Funnel: the nine stage steps over the whole window
funnel_query = lambda filters: query(REP, [step, "dim_funnel_step_sort_order"], [deals], filters,
                                     [("dim_funnel_step_sort_order", False)])
funnel_config = {"type": "funnel", "config": {"dataInput": "row", "fieldId": deals, "showLegend": True,
                                              "labels": {"position": "inside", "showValue": True, "showPercentage": True}}}
charts["funnel_stages"] = save(
    "Deal stages by count",
    "Distinct deals that reached each stage, 2024-01 to 2025-02 (skipped stages counted as reached).",
    funnel_query([flt("dim_funnel_step_source_type", "equals", ["stage"])]), funnel_config)

# 7. Funnel: all eleven task steps, with the two call steps
charts["funnel_steps"] = save(
    "All funnel steps (task KPIs)",
    "The eleven steps of rep_sales_funnel_monthly, calls 2.1 and 3.1 included (done calls, own deal ids).",
    funnel_query([]), funnel_config)

# Dashboard: header, KPI column on the left, trend and funnels on the right
tile = lambda key, title, x, y, w, h: {"type": "saved_chart", "x": x, "y": y, "w": w, "h": h,
                                       "properties": {"title": title, "savedChartUuid": charts[key]}}
tiles = [
    {"type": "markdown", "x": 0, "y": 0, "w": 36, "h": 3, "properties": {"title": "", "content": "## Deals Overview\nEnpal Pipedrive export, 2024-01 to 2025-02. Closed = reached Closing (stage 6); the export has no won/lost status and no amounts."}},
    tile("gauge", "Deal conversion rate: Jan 2024 cohort", 0, 3, 9, 7),
    tile("closed", "Closed deals: Oct 2024", 0, 10, 9, 5),
    tile("leads", "New leads: Sep 2024", 0, 15, 9, 5),
    tile("cycle", "Avg sales cycle", 0, 20, 9, 5),
    tile("trend", "Monthly funnel trend", 9, 3, 9, 22),
    tile("funnel_stages", "Deal stages by count", 18, 3, 9, 22),
    tile("funnel_steps", "All funnel steps (task KPIs)", 27, 3, 9, 22),
]
r = ldapi.call("POST", f"/api/v1/projects/{P}/dashboards",
               {"name": "Deals Overview", "description": "Sales funnel of the Pipedrive export: conversion, closed deals, leads, sales cycle, monthly trend and funnels.",
                "tiles": tiles, "tabs": [], "spaceUuid": SPACE})
if r.get("status") != "ok":
    raise SystemExit(json.dumps(r)[:800])
print("DASHBOARD", f"http://localhost:8080/projects/{P}/dashboards/{r['results']['uuid']}/view")
