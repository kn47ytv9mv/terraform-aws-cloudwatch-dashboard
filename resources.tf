locals {
  flow_indices = [for index, widget in var.widgets : index if widget.x == null]
  flow_widths  = [for index in local.flow_indices : var.widgets[index].width]
  flow_offsets = [for slot in range(length(local.flow_indices)) : sum(concat([0], slice(local.flow_widths, 0, slot)))]
  flow_rows    = [for offset in local.flow_offsets : floor(offset / 24)]

  row_count = ceil(sum(concat([0], local.flow_widths)) / 24)

  row_heights = [
    for row in range(local.row_count) :
    max(concat([0], [for slot, index in local.flow_indices : var.widgets[index].height if local.flow_rows[slot] == row])...)
  ]

  row_tops = [for row in range(local.row_count) : sum(concat([0], slice(local.row_heights, 0, row)))]

  flowed_x = { for slot, index in local.flow_indices : index => local.flow_offsets[slot] % 24 }
  flowed_y = { for slot, index in local.flow_indices : index => local.row_tops[local.flow_rows[slot]] }

  dashboard_body = jsonencode(merge(
    {
      widgets = [
        for index, widget in var.widgets : {
          type       = widget.type
          width      = widget.width
          height     = widget.height
          x          = lookup(local.flowed_x, index, widget.x)
          y          = lookup(local.flowed_y, index, widget.y)
          properties = jsondecode(widget.properties)
        }
      ]
    },
    { for value in var.variables_json[*] : "variables" => jsondecode(value) },
    { for value in var.start[*] : "start" => value },
    { for value in var.end[*] : "end" => value },
    { for value in var.period_override[*] : "periodOverride" => value },
  ))
}

resource "random_uuid" "resource" {}

resource "aws_cloudwatch_dashboard" "resource" {
  dashboard_name = coalesce(var.dashboard_name, random_uuid.resource.id)
  dashboard_body = local.dashboard_body
}

output "id" {
  description = "The ID of the dashboard, which is its name."
  value       = aws_cloudwatch_dashboard.resource.id
}

output "arn" {
  description = "The ARN of the dashboard."
  value       = aws_cloudwatch_dashboard.resource.dashboard_arn
}

output "dashboard_name" {
  description = "The name of the dashboard, as it appears in the CloudWatch console's dashboard list."
  value       = aws_cloudwatch_dashboard.resource.dashboard_name
}

output "dashboard_body" {
  description = "The rendered dashboard body, with every computed widget coordinate resolved. Useful for reviewing the layout the module produced without opening the console."
  value       = aws_cloudwatch_dashboard.resource.dashboard_body
}
