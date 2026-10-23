import json, subprocess, csv, io, sys
sys.path.insert(0, ".")
import ldapi
P = json.load(open("project.json"))["project"]["projectUuid"]
SPACE = ldapi.call("GET", f"/api/v1/projects/{P}/spaces")["results"][0]["uuid"]

def columns_of(sql):
    out = subprocess.run(["docker","exec","dbt_enpal_assessment-db-1","psql","-U","admin","-d","postgres","--csv","-c", f"select * from ({sql.rstrip().rstrip(';')}) q limit 0"], capture_output=True, text=True)
    if out.returncode: raise SystemExit("SQL error: " + out.stderr[:400] + "\n" + sql[:300])
    return next(csv.reader(io.StringIO(out.stdout)))

def table_cfg(cols):
    return {"metadata": {"version": 1}, "type": "table",
            "columns": {c: {"visible": True, "reference": c, "label": c, "frozen": False, "order": i} for i, c in enumerate(cols)}}

def bar_cfg(x, ys, x_type="category", group=None, stack=False):
    return {"metadata": {"version": 1}, "type": "vertical_bar", "display": {},
            "fieldConfig": {"x": {"reference": x, "type": x_type}, "y": [{"reference": y, "aggregation": "sum"} for y in ys],
                            "groupBy": [{"reference": group}] if group else [], **({"stack": True} if stack else {})}}

def create_chart(name, description, sql, kind="table", x=None, ys=None, x_type="category", limit=500):
    cols = columns_of(sql)
    cfg = table_cfg(cols) if kind == "table" else bar_cfg(x, ys, x_type)
    r = ldapi.call("POST", f"/api/v1/projects/{P}/sqlRunner/saved",
                   {"name": name, "description": description, "sql": sql.strip().rstrip(";"), "limit": limit, "config": cfg, "spaceUuid": SPACE})
    if r.get("status") != "ok": raise SystemExit(f"create failed for {name}: {json.dumps(r)[:900]}")
    res = r["results"]
    return res.get("savedSqlUuid") or res.get("uuid")
