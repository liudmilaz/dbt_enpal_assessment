import json, os, subprocess, sys
sys.path.insert(0, ".")
import ldapi
P = json.load(open("project.json"))["project"]["projectUuid"]
SNOW_CONNECTION = os.environ.get("SNOW_CONNECTION", "enpal")  # a snow CLI connection that can read ENPAL_RAW
SPACE = ldapi.call("GET", f"/api/v1/projects/{P}/spaces")["results"][0]["uuid"]

def columns_of(sql):  # column names as Snowflake returns them (unquoted aliases come back in upper case)
    out = subprocess.run(["snow","sql","-c",SNOW_CONNECTION,"--format","json","-q", f"use warehouse ENPAL_WH; select * from ({sql.rstrip().rstrip(';')}) q limit 1"], capture_output=True, text=True)
    try:
        rows = json.loads(out.stdout)[-1]
    except Exception:
        raise SystemExit("SQL error: " + (out.stderr or out.stdout)[-400:] + "\n" + sql[:300])
    if not rows: raise SystemExit("no rows, cannot read the columns: " + sql[:300])
    return list(rows[0].keys())

def as_returned(name, cols):  # the chart config must use the column name exactly as the warehouse returns it
    return next((c for c in cols if c.lower() == name.lower()), name)

def table_cfg(cols):
    return {"metadata": {"version": 1}, "type": "table",
            "columns": {c: {"visible": True, "reference": c, "label": c, "frozen": False, "order": i} for i, c in enumerate(cols)}}

def bar_cfg(x, ys, x_type="category", group=None, stack=False):
    return {"metadata": {"version": 1}, "type": "vertical_bar", "display": {},
            "fieldConfig": {"x": {"reference": x, "type": x_type}, "y": [{"reference": y, "aggregation": "sum"} for y in ys],
                            "groupBy": [{"reference": group}] if group else [], **({"stack": True} if stack else {})}}

def create_chart(name, description, sql, kind="table", x=None, ys=None, x_type="category", limit=500):
    cols = columns_of(sql)
    cfg = table_cfg(cols) if kind == "table" else bar_cfg(as_returned(x, cols), [as_returned(y, cols) for y in ys], x_type)
    r = ldapi.call("POST", f"/api/v1/projects/{P}/sqlRunner/saved",
                   {"name": name, "description": description, "sql": sql.strip().rstrip(";"), "limit": limit, "config": cfg, "spaceUuid": SPACE})
    if r.get("status") != "ok": raise SystemExit(f"create failed for {name}: {json.dumps(r)[:900]}")
    res = r["results"]
    return res.get("savedSqlUuid") or res.get("uuid")
