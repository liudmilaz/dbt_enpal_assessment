# Data dictionary

Only the fields the analysis needs, for the six raw tables from the Pipedrive CRM export. Each field links to the Pipedrive documentation that describes it and says whether the documentation defines it. This is the only place the fields are described; the `analyses/NN_<table>.sql` files refer here.

The business context (company, the sale, what each table means for the funnel) is in `docs/business_context.md`.

Documentation used (Pipedrive): [Deals API](https://developers.pipedrive.com/docs/api/v1/Deals), [Activities API](https://developers.pipedrive.com/docs/api/v1/Activities), [Activity types API](https://developers.pipedrive.com/docs/api/v1/ActivityTypes), [Stages API](https://developers.pipedrive.com/docs/api/v1/Stages), [Users API](https://developers.pipedrive.com/docs/api/v1/Users), [Deal fields API](https://developers.pipedrive.com/docs/api/v1/DealFields), support articles [Lost reasons](https://support.pipedrive.com/en/article/lost-reasons), [Customize pipeline stages](https://support.pipedrive.com/en/article/how-can-i-customize-my-pipeline-stages) and [How data is organized](https://support.pipedrive.com/en/article/how-is-pipedrive-data-organized). Where the official page does not define a field, the table says so; the API pages show collapsed response schemas, so some response fields can only be confirmed from third-party references (marked unofficial).

## deal_changes (fact): one change of one field of one deal

| Column | Meaning | Documentation | Status |
|---|---|---|---|
| `deal_id` | the deal the change belongs to | [Deals API: changelog](https://developers.pipedrive.com/docs/api/v1/Deals#getDealChangelog) | documented as the path parameter |
| `changed_field_key` | key of the field that changed (`field_key` of a changelog entry) | [Deals API: changelog](https://developers.pipedrive.com/docs/api/v1/Deals#getDealChangelog) | endpoint documented, response fields not defined; unofficial reference: [list updates about deal field values](https://developers.qodex.ai/pipedrive-api-collection/pipedrive-api-v1-2/deals-6/list-updates-about-deal-field-values-1) |
| `change_time` | when the change happened (`time` of a changelog entry) | [Deals API: changelog](https://developers.pipedrive.com/docs/api/v1/Deals#getDealChangelog) | not defined on the official page |
| `new_value` | value after the change: an id for `stage_id` and `user_id`, an option id for `lost_reason`, a timestamp for `add_time` | [Deals API: changelog](https://developers.pipedrive.com/docs/api/v1/Deals#getDealChangelog) | only third-party references list `new_value`; the export has no previous value and no author |
| key `stage_id` | the stage the deal moved into: "The ID of the deal stage" | [Deals API: add a deal](https://developers.pipedrive.com/docs/api/v1/Deals#addDeal) | documented |
| key `user_id` | the deal owner: "The ID of the user who owns the deal" (the API calls it `owner_id`) | [Deals API: add a deal](https://developers.pipedrive.com/docs/api/v1/Deals#addDeal) | documented under the name `owner_id` |
| key `add_time` | when the deal was created ("Deal created" in Settings, Data fields) | [Deals API: get all deals](https://developers.pipedrive.com/docs/api/v1/Deals#getDeals) | only mentioned as a sort field, not defined |
| key `lost_reason` | "The reason for losing the deal"; a predefined list set by an admin (Company settings, Lost reasons) or free text | [Support: Lost reasons](https://support.pipedrive.com/en/article/lost-reasons), [Deals API](https://developers.pipedrive.com/docs/api/v1/Deals#addDeal) | documented |

## activity (fact): one scheduled activity

| Column | Meaning | Documentation | Status |
|---|---|---|---|
| `activity_id` | the activity's id | [Activities API: get an activity](https://developers.pipedrive.com/docs/api/v1/Activities#getActivity) | documented; repeats in the export |
| `type` | the activity type, by its key string | [Activities API: add an activity](https://developers.pipedrive.com/docs/api/v1/Activities#addActivity), [Activity types API](https://developers.pipedrive.com/docs/api/v1/ActivityTypes) | documented |
| `assigned_to_user` | the user the activity belongs to ("The ID of the user who owns the activity", `owner_id`) | [Activities API: add an activity](https://developers.pipedrive.com/docs/api/v1/Activities#addActivity) | documented under the name `owner_id`; `assigned_to_user` is the export's name |
| `deal_id` | the deal linked to the activity | [Activities API: add an activity](https://developers.pipedrive.com/docs/api/v1/Activities#addActivity) | documented |
| `done` | "Whether the activity is marked as done or not" | [Activities API: add an activity](https://developers.pipedrive.com/docs/api/v1/Activities#addActivity) | documented |
| `due_to` | the planned date and time (the API has `due_date` and `due_time`) | [Activities API: add an activity](https://developers.pipedrive.com/docs/api/v1/Activities#addActivity) | documented as two fields; the export merges them |

## activity_types (dictionary)

| Column | Meaning | Documentation | Status |
|---|---|---|---|
| `id` | the activity type's id | [Activity types API](https://developers.pipedrive.com/docs/api/v1/ActivityTypes) | documented as a path parameter |
| `name` | the display name, for example Sales Call 1 | [Activity types API](https://developers.pipedrive.com/docs/api/v1/ActivityTypes) | documented as a body parameter |
| `type` | the key string that activities reference; generated from the name at creation and cannot be changed | [Activity types API](https://developers.pipedrive.com/docs/api/v1/ActivityTypes) | documented (`key_string`) |
| `active` | whether the type can be chosen for new activities; inactive types stay linked to old activities | Settings, Company settings, Activities (trial account) | `active_flag` is not described on the official API page |

## users (dictionary, master data)

| Column | Meaning | Documentation | Status |
|---|---|---|---|
| `id` | the user's id | [Users API](https://developers.pipedrive.com/docs/api/v1/Users) | documented as a path parameter |
| `email` | the user's email | [Users API](https://developers.pipedrive.com/docs/api/v1/Users) | documented; not unique in the export |
| `modified` | the last change of the user record | [Users API](https://developers.pipedrive.com/docs/api/v1/Users) | not documented on the official page |

## stages (dictionary)

| Column | Meaning | Documentation | Status |
|---|---|---|---|
| `stage_id` | the stage's id | [Stages API](https://developers.pipedrive.com/docs/api/v1/Stages) | documented |
| `stage_name` | the stage's name; stages are customised by the CRM admin | [Stages API](https://developers.pipedrive.com/docs/api/v1/Stages), [Support: customize pipeline stages](https://support.pipedrive.com/en/article/how-can-i-customize-my-pipeline-stages) | documented |

Not in the export: stage order (`order_nr`), win probability (`deal_probability`) and rotting settings; the funnel order is taken from the order of `stage_id`.

## fields (dictionary, metadata)

| Column | Meaning | Documentation | Status |
|---|---|---|---|
| `field_key` | the field's key, as used in the change log; default fields have readable keys, custom fields generated ones | [Deal fields API](https://developers.pipedrive.com/docs/api/v1/DealFields) | keys are mentioned, not defined |
| `name` | the field's display name (`field_name`), for example "Deal created" | [Deal fields API](https://developers.pipedrive.com/docs/api/v1/DealFields) | documented |
| `field_value_options` | the options of a single-option field: id and label; here the stage labels and the lost-reason options | [Deal fields API](https://developers.pipedrive.com/docs/api/v1/DealFields) | documented for single-option fields |
| `id` | the field's id in the export | [Deal fields API](https://developers.pipedrive.com/docs/api/v1/DealFields) | not defined on the official page |
