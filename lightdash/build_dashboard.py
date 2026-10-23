import sys, json, uuid, re, pathlib
sys.path.insert(0, ".")
import ldbuild, ldapi
P = ldbuild.P; SPACE = ldbuild.SPACE
REPO = pathlib.Path(__file__).resolve().parent.parent  # repo root, wherever it is cloned

def nulls(t):
    return f"""select key as col, count(*) as n_rows, count(*) - count(*) filter (where value = 'null'::jsonb) as n_not_null,
       count(*) filter (where value = 'null'::jsonb) as n_null, count(*) filter (where value = '""'::jsonb) as n_blank
from public.{t} t, jsonb_each(to_jsonb(t)) group by key order by key"""

def pk(cols, nullcond, given, distinct, table):
    return f"""select '{cols}' as primary_key, '{given}' as given_by, count(*) as n_rows, count(distinct {distinct}) as n_distinct,
 count(*) filter (where {nullcond}) as n_null, count(*) = count(distinct {distinct}) as is_unique, count(*) filter (where {nullcond}) = 0 as is_not_null from public.{table}"""

def iqr(measures):  # list of (name, sql returning x)
    v = "\n  union all\n".join(f"  select '{n}' as measure, x from ({s}) t where x is not null" for n, s in measures)
    return f"""with v as (
{v}
), b as (select measure, percentile_cont(0.25) within group (order by x) as q1, percentile_cont(0.75) within group (order by x) as q3 from v group by measure)
select v.measure, count(*) as n_values, round(b.q1::numeric, 1) as q1, round(b.q3::numeric, 1) as q3,
 round((b.q1 - 1.5 * (b.q3 - b.q1))::numeric, 1) as lower_fence, round((b.q3 + 1.5 * (b.q3 - b.q1))::numeric, 1) as upper_fence,
 count(*) filter (where v.x < b.q1 - 1.5 * (b.q3 - b.q1) or v.x > b.q3 + 1.5 * (b.q3 - b.q1)) as n_outliers,
 round(min(v.x)::numeric, 1) as min_value, round(max(v.x)::numeric, 1) as max_value
from v join b using (measure) group by v.measure, b.q1, b.q3 order by 1"""

def fk_block(path):  # take the inner union of a per-table file
    t = (REPO/path).read_text()
    i = t.index("select fk, n_child_rows"); j = t.index("\n) f;", i)
    inner = t[t.index("from (", i) + 6 : j]
    inner = re.sub(r"--[^\n]*", "", inner)
    return "select fk, n_child_rows, n_null, n_matched, n_child_rows - n_null - n_matched as n_orphans, parent_is_unique from (" + inner + ") f"

GAPS = "select extract(epoch from change_time - lag(change_time) over (partition by deal_id order by change_time)) / 86400 as x from public.deal_changes where changed_field_key = 'stage_id'"
LAGS = "select extract(epoch from s.ts - a.ts) / 86400 as x from (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'add_time' group by 1) a join (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'stage_id' and new_value = '1' group by 1) s using (deal_id)"

FIND_SQL = (REPO/"vault/project/sql/07_data_quality_findings.sql").read_text()  # moved with the documentation PR
FIND_SQL = FIND_SQL[FIND_SQL.index("select row_number()"):].rstrip().rstrip(";")
FIND_SQL = re.sub(r"(?m)^\s*--[^\n]*$", "", FIND_SQL)

KEYS_SQL = """select tbl, class, n_rows, primary_key, given_by, n_distinct, n_null, is_unique, is_not_null from (
 select 'deal_changes' tbl, 'FACT' class, count(*) n_rows, '(deal_id, changed_field_key, change_time)' primary_key, 'identified' given_by, count(distinct (deal_id, changed_field_key, change_time)) n_distinct, count(*) filter (where deal_id is null or changed_field_key is null or change_time is null) n_null, count(*) = count(distinct (deal_id, changed_field_key, change_time)) is_unique, count(*) filter (where deal_id is null or changed_field_key is null or change_time is null) = 0 is_not_null from public.deal_changes
 union all select 'activity','FACT',count(*),'activity_id','identified',count(distinct activity_id),count(*)-count(activity_id),count(*)=count(distinct activity_id),count(*)-count(activity_id)=0 from public.activity
 union all select 'activity_types','DICTIONARY',count(*),'id','task (init.sql)',count(distinct id),count(*)-count(id),count(*)=count(distinct id),count(*)-count(id)=0 from public.activity_types
 union all select 'users','DICTIONARY',count(*),'id','task (init.sql)',count(distinct id),count(*)-count(id),count(*)=count(distinct id),count(*)-count(id)=0 from public.users
 union all select 'stages','DICTIONARY',count(*),'stage_id','task (init.sql)',count(distinct stage_id),count(*)-count(stage_id),count(*)=count(distinct stage_id),count(*)-count(stage_id)=0 from public.stages
 union all select 'fields','DICTIONARY',count(*),'id','task (init.sql)',count(distinct id),count(*)-count(id),count(*)=count(distinct id),count(*)-count(id)=0 from public.fields) k
 order by case class when 'FACT' then 1 else 2 end, tbl"""

D = "https://developers.pipedrive.com/docs/api/v1/"; S = "https://support.pipedrive.com/en/article/"
CTX = "**Business context (company description provided with the task):** Enpal is a Berlin-based energy company selling residential and commercial energy solutions (PV systems, battery storage, EV wallboxes, heat pumps, smart meters) with zero-upfront-cost rental or purchase; over 115,000 customers. A household energy sale is long, so the sales funnel is a core KPI. This export has 1,995 deals and 4,579 activities: a small sample, not Enpal's scale."

def md(title, cls, grain, findings, fields, extra=""):
    f = "\n".join(f"- {x}" for x in findings)
    fl = "\n".join(f"- `{c}`: {d} ([docs]({u}); {s})" for c, d, u, s in fields)
    return f"**{title}** · {cls}\n\n{grain}\n\n**Findings in short**\n{f}\n\n{extra}**Fields used** (with the Pipedrive documentation)\n{fl}\n\n{CTX}"

TABS = []
# ---------------- Overview
TABS.append(("Overview", md("Six raw Pipedrive tables", "overview", "Two fact tables (one row per event) and four dictionaries (lookups the facts refer to). One tab per table follows; each has the same sections: all columns, primary key, foreign keys, nulls, outliers, descriptive analytics.",
 ["28 data quality checks: 11 pass, 9 flag a problem, 8 are documented as expected or descriptive", "the keys: 4 primary keys given by the task, 2 identified by testing (activity_id is not unique)", "activity.deal_id does not match the deals; lost reasons are inconsistent with the stages reached"], []),
 [("Tables, primary keys and the unique / not-null check", "Primary key of each table, given by the task or identified, with the check.", KEYS_SQL, "table", None, None, 36, 9),
  ("Data quality findings", "One row per check: class, violations, proposed test severity and result.", FIND_SQL, "table", None, None, 36, 14),
  ("Flagged findings: violations", "Violations of the checks that flag a problem.", "select 'f' || no || ' ' || left(finding, 42) as finding, violations from (" + FIND_SQL + ") q where result = 'flag' order by violations desc", "bar", "finding", ["violations"], 36, 10)]))

# ---------------- deal_changes
TABS.append(("deal_changes", md("deal_changes", "FACT · 15,406 rows", "One change of one field of one deal (an event log). Timestamp `change_time`, 2024-01-01 to 2025-03-11.",
 ["primary key: none given by the task; (deal_id, changed_field_key, change_time) is unique and not null (identified); deal_id repeats and there is no deals table", "foreign keys: all hold at 100% with 0 nulls (field key, owner, stage, lost reason)", "nulls: none; outliers: none in the gaps between stage events, 12 deals above the fence in the creation lag", "84% of deals skip a stage; 5 deals carry two lifecycles; every deal has a lost reason, and the reasons do not match the stages reached"],
 [("deal_id", "the deal the change belongs to", D+"Deals#getDealChangelog", "documented as the path parameter"), ("changed_field_key", "key of the field that changed", D+"Deals#getDealChangelog", "response fields not defined on the official page"), ("change_time", "when the change happened", D+"Deals#getDealChangelog", "not defined on the official page"), ("new_value", "value after the change (id, option id or timestamp)", D+"Deals#getDealChangelog", "not defined on the official page"),
  ("key stage_id", "the stage the deal moved into", D+"Deals#addDeal", "documented"), ("key user_id", "the deal owner (API name owner_id)", D+"Deals#addDeal", "documented as owner_id"), ("key add_time", "when the deal was created", D+"Deals#getDeals", "only mentioned as a sort field"), ("key lost_reason", "the reason for losing the deal; predefined list or free text", S+"lost-reasons", "documented")]),
 [("1. All columns (first rows)", "select * of the table.", "select * from public.deal_changes order by deal_id, change_time", "table", None, None, 36, 9, 100),
  ("2. Primary key", "Given or identified, unique and not null.", pk("(deal_id, changed_field_key, change_time)", "deal_id is null or changed_field_key is null or change_time is null", "identified", "(deal_id, changed_field_key, change_time)", "deal_changes"), "table", None, None, 36, 4),
  ("3. Foreign keys", "Nulls, matches, orphans and parent uniqueness.", fk_block("analyses/01_deal_changes.sql"), "table", None, None, 36, 8),
  ("4. Nulls and not nulls per column", "Per column.", nulls("deal_changes"), "table", None, None, 18, 8),
  ("5. Outliers (IQR)", "Fences q1 - 1.5 IQR and q3 + 1.5 IQR.", iqr([("days between stage events", GAPS), ("days from creation to first stage 1", LAGS)]), "table", None, None, 18, 8),
  ("6a. Events per field key", "Rows per field key.", "select changed_field_key, count(*) as n_events, count(distinct deal_id) as n_deals from public.deal_changes group by 1 order by 2 desc", "bar", "changed_field_key", ["n_events"], 18, 9),
  ("6b. Stage moves by size", "Distance from the previous stage; +1 is the next stage.", "with m as (select new_value::int - lag(new_value::int) over (partition by deal_id order by change_time) as mv from public.deal_changes where changed_field_key = 'stage_id') select (case when mv > 0 then '+' else '' end) || mv::text as move, count(*) as n_events from m where mv is not null group by mv order by mv", "bar", "move", ["n_events"], 18, 9),
  ("6c. Deals per stage: recorded vs backfilled", "Backfilled also counts the stages a deal skipped.", "with s as (select deal_id, new_value::int as st from public.deal_changes where changed_field_key = 'stage_id'), mx as (select deal_id, max(st) as mx from s group by 1) select n.st || ' ' || st.stage_name as stage, (select count(distinct deal_id) from s where st = n.st) as recorded, (select count(*) from mx where mx >= n.st) as backfilled from generate_series(1, 9) n(st) join public.stages st on st.stage_id = n.st order by n.st", "bar", "stage", ["recorded", "backfilled"], 36, 11),
  ("6d. Lost reasons with labels and how far those deals got", "The reasons do not describe where a deal stopped.", "with m as (select deal_id, max(new_value::int) as highest_stage from public.deal_changes where changed_field_key = 'stage_id' group by 1), lr as (select distinct l.deal_id, o.id as reason_id, o.label from public.deal_changes l join (select j ->> 'id' as id, j ->> 'label' as label from public.fields f, jsonb_array_elements(f.field_value_options) j where f.field_key = 'lost_reason') o on o.id = l.new_value where l.changed_field_key = 'lost_reason') select lr.label as lost_reason, count(*) as n_deals, count(*) filter (where m.highest_stage >= 3) as reached_needs_assessment, count(*) filter (where m.highest_stage >= 6) as reached_closing, count(*) filter (where m.highest_stage = 9) as reached_last_stage from lr join m using (deal_id) group by lr.reason_id, lr.label order by lr.reason_id", "bar", "lost_reason", ["n_deals", "reached_needs_assessment", "reached_closing", "reached_last_stage"], 36, 11),
  ("6e. Days between stage events", "Histogram in 3-day bins: flat, looks generated.", "with t as (" + GAPS + ") select (floor(x / 3) * 3)::int || '-' || ((floor(x / 3) * 3)::int + 2) as days, count(*) as n_gaps from t where x is not null group by floor(x / 3) order by floor(x / 3)", "bar", "days", ["n_gaps"], 18, 9),
  ("6f. Days from creation to the first stage 1 entry", "Histogram in 10-day bins.", "with t as (" + LAGS + ") select (floor(x / 10) * 10)::int || '-' || ((floor(x / 10) * 10)::int + 9) as days, count(*) as n_deals from t group by floor(x / 10) order by floor(x / 10)", "bar", "days", ["n_deals"], 18, 9),
  ("6g. Events per deal", "Distribution of events per deal.", "with c as (select deal_id, count(*) as n from public.deal_changes group by 1) select n::text as events_per_deal, count(*) as n_deals from c group by n order by n", "bar", "events_per_deal", ["n_deals"], 18, 9),
  ("6h. Created vs entering stage 1, by month", "A deal enters stage 1 weeks after it is created.", "select m as month, coalesce(created, 0) as created, coalesce(stage1, 0) as entered_stage_1 from (select to_char(date_trunc('month', ts), 'YYYY-MM') as m, count(*) as created from (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'add_time' group by 1) a group by 1) c full join (select to_char(date_trunc('month', ts), 'YYYY-MM') as m, count(*) as stage1 from (select deal_id, min(change_time) as ts from public.deal_changes where changed_field_key = 'stage_id' and new_value = '1' group by 1) s group by 1) e using (m) order by 1", "bar", "month", ["created", "entered_stage_1"], 18, 9)]))

# ---------------- activity
TABS.append(("activity", md("activity", "FACT · 4,579 rows", "One scheduled activity (a call or meeting planned for a time). Timestamp `due_to`, 2024-01-01 to 2024-09-13; `done` says whether it was marked done.",
 ["primary key: none given by the task; activity_id is the intended key but is not unique (4,568 of 4,579); the full row is unique, so the model needs a surrogate key", "foreign keys: assigned user and type hold at 100%; deal_id fails (8 of 4,579 rows match)", "nulls: none; outliers: none in due_to", "the 11 repeated ids are collisions of unrelated activities, not duplicates; about half of every type is done"],
 [("activity_id", "the activity's id", D+"Activities#getActivity", "documented; repeats in the export"), ("type", "the activity type (key string)", D+"Activities#addActivity", "documented"), ("assigned_to_user", "the user the activity belongs to (owner_id)", D+"Activities#addActivity", "documented as owner_id"), ("deal_id", "the deal linked to the activity", D+"Activities#addActivity", "documented"), ("done", "whether the activity is marked as done", D+"Activities#addActivity", "documented"), ("due_to", "the planned date and time (due_date and due_time)", D+"Activities#addActivity", "documented as two fields")]),
 [("1. All columns (first rows)", "select * of the table.", "select * from public.activity order by due_to", "table", None, None, 36, 9, 100),
  ("2. Primary key", "activity_id is not unique.", pk("activity_id", "activity_id is null", "identified", "activity_id", "activity"), "table", None, None, 18, 4),
  ("2b. Full row uniqueness", "The full row is unique, so a surrogate key works.", "select count(*) as n_rows, count(distinct (activity_id, type, assigned_to_user, deal_id, done, due_to)) as n_distinct_full_rows from public.activity", "table", None, None, 18, 4),
  ("3. Foreign keys", "Nulls, matches, orphans and parent uniqueness.", fk_block("analyses/02_activity.sql"), "table", None, None, 36, 6),
  ("4. Nulls and not nulls per column", "Per column.", nulls("activity"), "table", None, None, 18, 8),
  ("5. Outliers (IQR)", "due_to as days since 1970.", iqr([("due_to (days since 1970)", "select extract(epoch from due_to) / 86400 as x from public.activity")]), "table", None, None, 18, 8),
  ("6a. Activity types and the done flag", "About half of every type is done.", "select type, count(*) filter (where done) as done, count(*) filter (where not done) as not_done from public.activity group by 1 order by 1", "bar", "type", ["done", "not_done"], 18, 9),
  ("6b. Activities per month and type", "About 500 a month until mid September.", "select to_char(date_trunc('month', due_to), 'YYYY-MM') as month, type, count(*) as n from public.activity group by 1, 2 order by 1, 2", "bar_group", "month", ["n"], 18, 9, 500, "type"),
  ("6c. The 11 repeated activity ids", "Deal, user and due date differ in every pair: collisions, not duplicates.", "select activity_id, count(*) as n, count(distinct deal_id) as n_deals, count(distinct assigned_to_user) as n_users, count(distinct type) as n_types, count(distinct due_to) as n_due_dates from public.activity group by activity_id having count(*) > 1 order by activity_id", "table", None, None, 18, 9),
  ("6d. Can activities be joined to deals", "Only a few activity deal ids exist in deal_changes.", "select count(distinct a.deal_id) as n_activity_deal_ids, count(distinct a.deal_id) filter (where exists (select 1 from public.deal_changes d where d.deal_id = a.deal_id)) as found_in_deal_changes, (select count(distinct deal_id) from public.deal_changes) as n_deals_in_deal_changes from public.activity a", "table", None, None, 18, 9)]))

# ---------------- dictionaries
def dict_tab(name, rows, grain, findings, fields, sample_sql, pk_sql, descr_charts, outliers=None):
    charts = [("1. All columns", "select * of the table.", sample_sql, "table", None, None, 36, 8, 100), ("2. Primary key", "Given by the task, unique and not null.", pk_sql, "table", None, None, 36, 4),
              ("4. Nulls and not nulls per column", "Per column.", nulls(name), "table", None, None, 18, 8)]
    if outliers: charts.append(("5. Outliers (IQR)", "Fences q1 - 1.5 IQR and q3 + 1.5 IQR.", outliers, "table", None, None, 18, 8))
    charts += descr_charts
    return (name, md(name, f"DICTIONARY · {rows}", grain, findings, fields), charts)

TABS.append(dict_tab("activity_types", "4 rows", "One activity type; decodes `activity.type` (a key string) into a name.",
 ["primary key: id, given by the task, unique and not null; type is also unique and is the column activities reference", "foreign keys: none; referenced by activity.type (4 of 4 types used); nulls: none; outliers: not applicable", "Follow Up Call is inactive but used by 1,133 activities; After Close Call is not a funnel step"],
 [("id", "the activity type's id", D+"ActivityTypes", "documented"), ("name", "the display name", D+"ActivityTypes", "documented"), ("type", "the key string that activities reference; fixed at creation", D+"ActivityTypes", "documented (key_string)"), ("active", "whether the type can be chosen for new activities", "https://datacanonic.pipedrive.com/settings/activity_settings", "not described in the API docs")],
 "select * from public.activity_types order by id", pk("id", "id is null", "task (init.sql)", "id", "activity_types"),
 [("6a. Usage: activities and done per type", "Which types the activities use.", "select t.name, t.type, t.active, count(a.activity_id) as n_activities, count(a.activity_id) filter (where a.done) as n_done from public.activity_types t left join public.activity a on a.type = t.type group by 1, 2, 3 order by 1", "bar", "name", ["n_activities", "n_done"], 36, 9)]))

TABS.append(dict_tab("users", "1,787 rows", "One user (master data): current state only; `modified` is the last change of the user.",
 ["primary key: id, given by the task, unique and not null; email is not a key (4 emails are shared by 2 users each)", "foreign keys: none; referenced by activity.assigned_to_user and the owner events (1,757 of 1,787 users)", "nulls: none; outliers: none in modified"],
 [("id", "the user's id", D+"Users", "documented"), ("email", "the user's email", D+"Users", "documented; not unique in the export"), ("modified", "the last change of the user record", D+"Users", "not documented")],
 "select * from public.users order by id", pk("id", "id is null", "task (init.sql)", "id", "users"),
 [("6a. Emails shared by more than one user", "Email is not a key.", "select email, count(*) as n_users, array_agg(id order by id)::text as user_ids from public.users group by email having count(*) > 1 order by email", "table", None, None, 18, 8),
  ("6b. Users referenced by the facts", "Referenced by an activity or an owner event.", "select count(*) as n_users, count(*) filter (where u.id in (select assigned_to_user from public.activity) or u.id in (select new_value::int from public.deal_changes where changed_field_key = 'user_id')) as n_referenced from public.users u", "table", None, None, 18, 8),
  ("6c. Users by month of the last change", "Spread of the modified column.", "select to_char(date_trunc('month', modified), 'YYYY-MM') as month, count(*) as n_users from public.users group by 1 order by 1", "bar", "month", ["n_users"], 36, 9)],
 iqr([("modified (days since 1970)", "select extract(epoch from modified) / 86400 as x from public.users")])))

TABS.append(dict_tab("stages", "9 rows", "One pipeline stage: id and name; the order of stage_id is the order of the funnel steps.",
 ["primary key: stage_id, given by the task, unique and not null; stage_name is also unique", "foreign keys: none; referenced by the stage events (9 of 9 stages used); nulls: none; outliers: not applicable", "the second stage is spelled Qualified lead here and Qualified Lead in fields"],
 [("stage_id", "the stage's id", D+"Stages", "documented"), ("stage_name", "the stage's name; customised by the CRM admin", D+"Stages", "documented; see also "+S+"how-can-i-customize-my-pipeline-stages")],
 "select * from public.stages order by stage_id", pk("stage_id", "stage_id is null", "task (init.sql)", "stage_id", "stages"),
 [("6a. Usage and spelling", "Deals per stage and the label in fields.", "select s.stage_id, s.stage_name, o.label as label_in_fields, s.stage_name = o.label as same_spelling, count(distinct d.deal_id) as n_deals_entered from public.stages s left join (select (j ->> 'id')::int as id, j ->> 'label' as label from public.fields f, jsonb_array_elements(f.field_value_options) j where f.field_key = 'stage_id') o on o.id = s.stage_id left join public.deal_changes d on d.changed_field_key = 'stage_id' and d.new_value::int = s.stage_id group by 1, 2, 3 order by 1", "table", None, None, 36, 9),
  ("6b. Deals that entered each stage", "Recorded entries only.", "select s.stage_id || ' ' || s.stage_name as stage, count(distinct d.deal_id) as n_deals_entered from public.stages s left join public.deal_changes d on d.changed_field_key = 'stage_id' and d.new_value::int = s.stage_id group by s.stage_id, s.stage_name order by s.stage_id", "bar", "stage", ["n_deals_entered"], 36, 9)]))

TABS.append(dict_tab("fields", "4 rows", "One deal field: key, display name and, for single-option fields, the option list as JSON.",
 ["primary key: id, given by the task, unique and not null; field_key is also unique and is the column deal_changes references", "foreign keys: none; nulls: only field_value_options, 2 of 4 rows (not applicable); outliers: not applicable", "stage labels and lost-reason options sit inside the JSON column"],
 [("field_key", "the field's key as used in the change log", D+"DealFields", "keys mentioned, not defined"), ("name", "the display name (field_name)", D+"DealFields", "documented"), ("field_value_options", "options of a single-option field: id and label", D+"DealFields", "documented for single-option fields"), ("id", "the field's id in the export", D+"DealFields", "not defined")],
 "select * from public.fields order by id", pk("id", "id is null", "task (init.sql)", "id", "fields"),
 [("6a. Options inside field_value_options", "Stage labels and lost-reason options.", "select f.field_key, f.name, j ->> 'id' as option_id, j ->> 'label' as label from public.fields f, jsonb_array_elements(f.field_value_options) j order by f.field_key, (j ->> 'id')::int", "table", None, None, 18, 12),
  ("6b. Events per field key", "Usage in deal_changes.", "select f.field_key, count(d.deal_id) as n_events from public.fields f left join public.deal_changes d on d.changed_field_key = f.field_key group by 1 order by 2 desc", "bar", "field_key", ["n_events"], 18, 12)]))

# ---------------- create charts and the dashboard
tabs = []; tiles = []
for order, (tab_name, md_text, charts) in enumerate(TABS):
    tab_uuid = str(uuid.uuid4()); tabs.append({"uuid": tab_uuid, "name": tab_name, "order": order})
    tiles.append({"type": "markdown", "x": 0, "y": 0, "w": 36, "h": 13 if tab_name != "Overview" else 7, "tabUuid": tab_uuid, "properties": {"title": "", "content": md_text, "hideFrame": False}})
    y = 13 if tab_name != "Overview" else 7; x = 0; row_h = 0
    for c in charts:
        name, desc, sql, kind, xcol, ys, w, h = c[:8]; limit = c[8] if len(c) > 8 else 500; group = c[9] if len(c) > 9 else None
        title = f"{tab_name}: {name}"
        if kind == "table": u = ldbuild.create_chart(title, desc, sql, "table", limit=limit)
        elif kind == "bar_group":
            cols = ldbuild.columns_of(sql)
            cfg = ldbuild.bar_cfg(xcol, ys, group=group, stack=True)
            r = ldapi.call("POST", f"/api/v1/projects/{P}/sqlRunner/saved", {"name": title, "description": desc, "sql": sql.strip(), "limit": limit, "config": cfg, "spaceUuid": SPACE})
            assert r.get("status") == "ok", json.dumps(r)[:600]; u = r["results"].get("savedSqlUuid") or r["results"].get("uuid")
        else: u = ldbuild.create_chart(title, desc, sql, "bar", x=xcol, ys=ys, limit=limit)
        if x + w > 36: x = 0; y += row_h; row_h = 0
        tiles.append({"type": "sql_chart", "x": x, "y": y, "w": w, "h": h, "tabUuid": tab_uuid, "properties": {"title": name, "savedSqlUuid": u, "chartName": title, "hideTitle": False}})
        x += w; row_h = max(row_h, h)
        if x >= 36: x = 0; y += row_h; row_h = 0
    print("tab", tab_name, "charts", len(charts))
dash = {"name": "Enpal Pipedrive: exploratory analysis per table", "description": "One tab per raw Pipedrive table: all columns, primary key, foreign keys, nulls, outliers and descriptive analytics, plus an overview of the data quality findings.", "tiles": tiles, "tabs": tabs, "spaceUuid": SPACE}
r = ldapi.call("POST", f"/api/v1/projects/{P}/dashboards", dash)
print(json.dumps(r)[:700])
if r.get("status") == "ok":
    d = r["results"]; print("DASHBOARD", f"http://localhost:8080/projects/{P}/dashboards/{d['uuid']}/view")
