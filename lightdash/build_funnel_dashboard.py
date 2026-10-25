"""Sales Funnel dashboard in Lightdash, on the dbt mart rep_sales_funnel_monthly (monthly grain).

A monthly trend and two funnels. Quarters or years need the event grain in the semantic layer: the call steps 2.1
and 3.1 count distinct deal ids per month and must not be summed across months. Data quality lives in Elementary.

Usage (from lightdash/, after `lightdash deploy`): python3 -I build_funnel_dashboard.py <project-uuid>
"""
import json, sys, uuid
sys.path.insert(0, ".")
import ldapi

P = sys.argv[1]
SPACE = ldapi.call("GET", f"/api/v1/projects/{P}/spaces")["results"][0]["uuid"]

REP = "rep_sales_funnel_monthly"


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

# 1. Monthly trend: leads and closed deals per month, from the report
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

# 2. Funnel: the nine stage steps over the whole window
funnel_query = lambda filters: query(REP, [step, "dim_funnel_step_sort_order"], [deals], filters,
                                     [("dim_funnel_step_sort_order", False)])
funnel_config = {"type": "funnel", "config": {"dataInput": "row", "fieldId": deals, "showLegend": True,
                                              "labels": {"position": "inside", "showValue": True, "showPercentage": True}}}
charts["funnel_stages"] = save(
    "Deal stages by count",
    "Distinct deals that reached each stage, 2024-01 to 2025-02 (skipped stages counted as reached).",
    funnel_query([flt("dim_funnel_step_source_type", "equals", ["stage"])]), funnel_config)

# 3. Funnel: all eleven task steps, with the two call steps
charts["funnel_steps"] = save(
    "All funnel steps (task KPIs)",
    "The eleven steps of rep_sales_funnel_monthly, calls 2.1 and 3.1 included (done calls, own deal ids).",
    funnel_query([]), funnel_config)

# Dashboard: header, then trend and funnels side by side
tile = lambda key, title, x, y, w, h: {"type": "saved_chart", "x": x, "y": y, "w": w, "h": h,
                                       "properties": {"title": title, "savedChartUuid": charts[key]}}
tiles = [
    {"type": "markdown", "x": 0, "y": 0, "w": 36, "h": 3, "properties": {"title": "", "content": "## Sales Funnel\nEnpal Pipedrive export, by month. Skipped stages count as reached; calls 2.1 and 3.1 are done calls with their own deal ids."}},
    tile("trend", "Monthly funnel trend", 0, 3, 12, 22),
    tile("funnel_stages", "Deal stages by count", 12, 3, 12, 22),
    tile("funnel_steps", "All funnel steps (task KPIs)", 24, 3, 12, 22),
]
r = ldapi.call("POST", f"/api/v1/projects/{P}/dashboards",
               {"name": "Sales Funnel", "description": "Sales funnel of the Pipedrive export by month: trend and funnels from rep_sales_funnel_monthly.",
                "tiles": tiles, "tabs": [], "spaceUuid": SPACE})
if r.get("status") != "ok":
    raise SystemExit(json.dumps(r)[:800])
print("DASHBOARD", f"http://localhost:8080/projects/{P}/dashboards/{r['results']['uuid']}/view")
