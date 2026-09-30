# terraform-aws-cloudwatch-dashboard

Terraform module for a CloudWatch dashboard — an arrangement of metric,
log, alarm, and text widgets on a shared grid, with the grid coordinates
computed rather than hand-maintained.

## Cost

The first three dashboards in an account are free, and every dashboard
beyond that bills per dashboard-month regardless of how many widgets it
carries. Adding a widget to an existing dashboard therefore costs
nothing, while splitting the same widgets across two dashboards may
cost something. A `custom` widget is the one exception: it bills for
the Lambda function it invokes on every refresh, separately from the
dashboard. See AWS's
[CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/) page
for current rates.

## Design

`aws_cloudwatch_dashboard` has three attributes: a name, a JSON body,
and a computed ARN. A module that only forwarded the body would add
nothing, so the module's whole reason for existing is what it builds
that body out of — which is to say, the grid arithmetic.

### Widget properties are taken as JSON

Each widget's `properties` is a JSON string, written with `jsonencode`.
This is the same call
[`terraform-aws-wafv2-web-acl`](https://github.com/kn47ytv9mv/terraform-aws-wafv2-web-acl)
makes for `rules_json`, for the same reason: the shape cannot be
expressed as an HCL type without losing information. A metric widget's
`metrics` is a mixed array of arrays with an optional trailing options
object —

```json
[["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "payments-db", { "stat": "Average" }]]
```

— and HCL has no type that admits both strings and an object in one
array. Collapsing it to `any` gains nothing over a string, while
forcing an object type would silently lose the features that make
CloudWatch dashboards worth writing at all: per-metric annotations,
metric math expressions, and `SEARCH` expressions. Validate a
properties document against AWS's
[dashboard body reference](https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/CloudWatch-Dashboard-Body-Structure.html)
rather than against this module's schema, which checks only the fields
outside `properties`.

An ARN, ID, or name sourced from another module is safe to embed in
`properties` even though it is unknown until apply. It is a value
inside a `jsonencode` rather than a key the plan depends on, so nothing
about the plan's shape rests on it — the rendered `dashboard_body`
simply reads as known-after-apply until the value it references exists.

### Widgets are an ordered list, not a map

`widgets` is a `list(object(...))` keyed by nothing. This is a
deliberate exception to the family's usual preference for
caller-keyed maps, and it is not a defect to be corrected. A map is
required when a variable's entries become separate resource instances
through `for_each`, because the keys become resource addresses that
Terraform has to know at plan time. Widgets are not that: they are
elements of a JSON array inside a single resource, so there is no
`for_each`, no resource addressing, and no plan-time key requirement.
What there is instead is order — declaration order is what the layout
reads to decide where each widget goes, and a map would sort its
entries alphabetically by key and scramble the arrangement.

### Automatic layout

CloudWatch's grid is 24 columns wide, and every widget carries `x`,
`y`, `width`, and `height`. Keeping those coordinates correct by hand
across twenty widgets, every time one is inserted or resized, is the
actual daily cost of maintaining a dashboard as code, and it is pure
arithmetic. So the module does it: leave `x` and `y` unset and widgets
flow left to right in declaration order, open a new row when the
current one fills, and drop each new row below the tallest widget of
the row above.

The module positions each widget from the cumulative width of the
widgets declared before it, because HCL has no way to carry a running
cursor across a list — there is no fold, no user-defined function, and
a `locals` entry cannot refer to itself. One rule follows from that:
**every row the layout completes has to fill exactly, so the widths
have to sum to 24 at each row boundary.** The last row may be short,
but no widget may straddle a boundary. A single width repeated tiles
the grid whenever it divides 24 — which covers 6, 8, 12, and 24, the
widths most dashboards are built from — and a mixed row tiles whenever
its own widths sum to 24, as `12 + 6 + 6` and `16 + 8` do. A widget
that would cross a row boundary is rejected at plan time with a message
naming the remedy, rather than silently rendering in the wrong place.

Setting both `x` and `y` on a widget pins it, and a pinned widget is
honoured exactly. A pinned widget is also outside the flow entirely: it
neither advances the cursor nor reserves space, which is what makes it
a clean escape hatch for an arrangement the flow cannot express. The
consequence worth knowing is that mixing pinned and flowed widgets on
the same dashboard can overlap them, since the flow does not know the
pinned widget is there. Pin all of them or none of them unless the
pinned widget sits below everything the flow produces.

The rendered body is exposed as the `dashboard_body` output, so the
computed coordinates can be reviewed in a plan without opening the
console.

### What this module does not cover

The dashboard resource does not accept tags. CloudWatch's own
`PutDashboard` API does, and so does `TagResource`, but the AWS
provider exposes neither on `aws_cloudwatch_dashboard`, so there is no
`tags` variable here rather than one that would be quietly discarded.

Alarms themselves belong to
[`terraform-aws-cloudwatch-metric-alarm`](https://github.com/kn47ytv9mv/terraform-aws-cloudwatch-metric-alarm).
An `alarm` widget on a dashboard displays alarms that already exist; it
does not create them, and a dashboard is not a substitute for one — a
dashboard is read by somebody who has already decided to look, while an
alarm is what tells them to look.

## Usage

Three widgets, no coordinates: the two half-width widgets share the
first row and the full-width widget takes the row below.

```hcl
module "payments_dashboard" {
  source = "kn47ytv9mv/cloudwatch-dashboard/aws"

  dashboard_name = "payments-service"

  widgets = [
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = jsonencode({
        title  = "Request rate"
        region = "us-east-1"
        stat   = "Sum"
        period = 60
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/payments/0123456789abcdef"],
        ]
      })
    },
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = jsonencode({
        title  = "Target latency"
        region = "us-east-1"
        stat   = "p99"
        period = 60
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "app/payments/0123456789abcdef"],
        ]
      })
    },
    {
      type   = "metric"
      width  = 24
      height = 6
      properties = jsonencode({
        title  = "Database CPU"
        region = "us-east-1"
        period = 300
        metrics = [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "payments-db", { stat = "Average" }],
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "payments-db", { stat = "Maximum" }],
        ]
      })
    },
  ]
}
```

Or directly from this repository, with every widget pinned to an exact
coordinate so a banner sits above two unequal panels — an arrangement
whose widths do not tile the grid, and so one the flow would reject:

```hcl
module "capacity_dashboard" {
  source = "github.com/kn47ytv9mv/terraform-aws-cloudwatch-dashboard"

  dashboard_name  = "capacity-review"
  start           = "-PT12H"
  period_override = "inherit"

  widgets = [
    {
      type   = "text"
      x      = 0
      y      = 0
      width  = 24
      height = 2
      properties = jsonencode({
        markdown = "# Capacity review\nOwned by the platform team. Change it through Terraform rather than the console."
      })
    },
    {
      type   = "alarm"
      x      = 0
      y      = 2
      width  = 8
      height = 6
      properties = jsonencode({
        title  = "Saturation alarms"
        alarms = ["arn:aws:cloudwatch:us-east-1:123456789012:alarm:payments-cpu-high"]
      })
    },
    {
      type   = "metric"
      x      = 8
      y      = 2
      width  = 16
      height = 6
      properties = jsonencode({
        title  = "Queue depth"
        region = "us-east-1"
        stat   = "Maximum"
        period = 60
        metrics = [
          ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "payments-inbound"],
        ]
      })
    },
  ]
}
```

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.3 |
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| dashboard_name | Name of the dashboard, unique within the account — dashboards are global rather than per-region. Only letters, digits, hyphens, and underscores are accepted, up to 255 characters. If null, a unique name is generated. | `null` | no |
| widgets | Widgets in the order they should be laid out. Each entry gives its `type`, its `properties` as a JSON string, and optionally `width` (default `6`), `height` (default `6`), and a pinned `x` and `y`. At most 500 entries. | `[]` | no |
| variables_json | Dashboard variables as a JSON array, which lets one dashboard be switched between resources rather than duplicated per resource. | `null` | no |
| start | Time range the dashboard opens on, as an ISO 8601 duration back from now (`'-PT3H'`) or an absolute timestamp. | `null` | no |
| end | End of an absolute time range, as an ISO 8601 timestamp. Only meaningful alongside an absolute `start`. | `null` | no |
| period_override | `'inherit'` to keep each widget's own period, or `'auto'` to derive it from the dashboard's time range. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| id | The ID of the dashboard, which is its name. |
| arn | The ARN of the dashboard. |
| dashboard_name | The name of the dashboard, as it appears in the CloudWatch console's dashboard list. |
| dashboard_body | The rendered dashboard body, with every computed widget coordinate resolved. |

## License

MIT — see [LICENSE.md](LICENSE.md).
