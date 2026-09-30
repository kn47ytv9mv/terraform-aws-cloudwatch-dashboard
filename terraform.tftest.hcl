mock_provider "aws" {}

run "dashboard_name_rejects_characters_aws_does_not_accept" {
  command = plan

  variables {
    dashboard_name = "payments service"
  }

  expect_failures = [var.dashboard_name]
}

run "dashboard_name_rejects_a_name_over_255_characters" {
  command = plan

  variables {
    dashboard_name = join("", [for character in range(256) : "a"])
  }

  expect_failures = [var.dashboard_name]
}

run "a_dashboard_over_500_widgets_is_rejected" {
  command = plan

  variables {
    widgets = [
      for index in range(501) : { type = "text", width = 24, properties = jsonencode({ markdown = "filler" }) }
    ]
  }

  expect_failures = [var.widgets]
}

run "widget_type_must_be_one_aws_renders" {
  command = plan

  variables {
    widgets = [
      { type = "gauge", properties = jsonencode({ markdown = "hello" }) },
    ]
  }

  expect_failures = [var.widgets]
}

run "widget_properties_must_be_json" {
  command = plan

  variables {
    widgets = [
      { type = "text", properties = "markdown: hello" },
    ]
  }

  expect_failures = [var.widgets]
}

run "widget_width_must_fit_the_grid" {
  command = plan

  variables {
    widgets = [
      { type = "text", width = 25, properties = jsonencode({ markdown = "hello" }) },
    ]
  }

  expect_failures = [var.widgets]
}

run "widget_height_must_be_within_range" {
  command = plan

  variables {
    widgets = [
      { type = "text", height = 1001, properties = jsonencode({ markdown = "hello" }) },
    ]
  }

  expect_failures = [var.widgets]
}

run "a_half_pinned_widget_is_rejected" {
  command = plan

  variables {
    widgets = [
      { type = "text", x = 0, properties = jsonencode({ markdown = "hello" }) },
    ]
  }

  expect_failures = [var.widgets]
}

run "a_pinned_x_beyond_the_last_column_is_rejected" {
  command = plan

  variables {
    widgets = [
      { type = "text", x = 24, y = 0, properties = jsonencode({ markdown = "hello" }) },
    ]
  }

  expect_failures = [var.widgets]
}

run "a_negative_pinned_y_is_rejected" {
  command = plan

  variables {
    widgets = [
      { type = "text", x = 0, y = -1, properties = jsonencode({ markdown = "hello" }) },
    ]
  }

  expect_failures = [var.widgets]
}

run "widths_that_do_not_fill_a_row_are_rejected" {
  command = plan

  variables {
    widgets = [
      { type = "text", width = 12, properties = jsonencode({ markdown = "one" }) },
      { type = "text", width = 6, properties = jsonencode({ markdown = "two" }) },
      { type = "text", width = 12, properties = jsonencode({ markdown = "three" }) },
    ]
  }

  expect_failures = [var.widgets]
}

run "an_empty_dashboard_still_produces_a_valid_body" {
  command = plan

  variables {
    dashboard_name = "empty"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).widgets == []
    error_message = "An empty widgets list should render an empty widgets array, which AWS accepts, rather than omitting the key or failing."
  }

  assert {
    condition     = keys(jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body)) == ["widgets"]
    error_message = "A body with no time range or dashboard variables set should carry the widgets key alone."
  }
}

run "the_name_falls_back_to_a_generated_uuid" {
  command = apply

  assert {
    condition     = aws_cloudwatch_dashboard.resource.dashboard_name == random_uuid.resource.id
    error_message = "Leaving dashboard_name unset should fall back to the generated random_uuid."
  }
}

run "aws_defaults_apply_to_an_unsized_widget" {
  command = plan

  variables {
    widgets = [
      { type = "text", properties = jsonencode({ markdown = "hello" }) },
    ]
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).widgets[0].width == 6
    error_message = "An unsized widget should take AWS's own default width of 6 grid units."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).widgets[0].height == 6
    error_message = "An unsized widget should take AWS's own default height of 6 grid units."
  }
}

run "automatic_layout_wraps_to_a_second_row_and_stacks_by_the_tallest_widget" {
  command = plan

  variables {
    widgets = [
      { type = "text", width = 12, height = 6, properties = jsonencode({ markdown = "one" }) },
      { type = "text", width = 12, height = 8, properties = jsonencode({ markdown = "two" }) },
      { type = "text", width = 12, height = 4, properties = jsonencode({ markdown = "three" }) },
      { type = "text", width = 12, height = 4, properties = jsonencode({ markdown = "four" }) },
    ]
  }

  assert {
    condition = [
      for widget in jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).widgets : [widget.x, widget.y]
      ] == [
      [0, 0],
      [12, 0],
      [0, 8],
      [12, 8],
    ]
    error_message = "Two 12-wide widgets should fill the first row, the next two should wrap onto a second row, and that second row should begin below the tallest widget of the first."
  }
}

run "automatic_layout_flows_mixed_widths_across_three_rows" {
  command = plan

  variables {
    widgets = [
      { type = "text", width = 8, height = 3, properties = jsonencode({ markdown = "a" }) },
      { type = "text", width = 8, height = 3, properties = jsonencode({ markdown = "b" }) },
      { type = "text", width = 8, height = 3, properties = jsonencode({ markdown = "c" }) },
      { type = "text", width = 24, height = 5, properties = jsonencode({ markdown = "d" }) },
      { type = "text", width = 6, height = 2, properties = jsonencode({ markdown = "e" }) },
      { type = "text", width = 6, height = 2, properties = jsonencode({ markdown = "f" }) },
      { type = "text", width = 6, height = 2, properties = jsonencode({ markdown = "g" }) },
      { type = "text", width = 6, height = 2, properties = jsonencode({ markdown = "h" }) },
    ]
  }

  assert {
    condition = [
      for widget in jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).widgets : [widget.x, widget.y]
      ] == [
      [0, 0],
      [8, 0],
      [16, 0],
      [0, 3],
      [0, 8],
      [6, 8],
      [12, 8],
      [18, 8],
    ]
    error_message = "Widgets should flow left to right at their declared widths, open a new row once the current one fills, and drop each row below the tallest widget of the row above."
  }
}

run "a_pinned_coordinate_is_honoured_and_stays_out_of_the_flow" {
  command = plan

  variables {
    widgets = [
      { type = "text", width = 12, height = 6, properties = jsonencode({ markdown = "flowed" }) },
      { type = "text", width = 8, height = 6, x = 20, y = 50, properties = jsonencode({ markdown = "pinned" }) },
      { type = "text", width = 12, height = 6, properties = jsonencode({ markdown = "flowed" }) },
    ]
  }

  assert {
    condition = [
      for widget in jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).widgets : [widget.x, widget.y]
      ] == [
      [0, 0],
      [20, 50],
      [12, 0],
    ]
    error_message = "A pinned widget should keep the coordinates it was given, and should neither advance the layout cursor nor displace the flowed widget that follows it."
  }
}

run "widget_properties_are_carried_through_verbatim" {
  command = plan

  variables {
    widgets = [
      {
        type   = "metric"
        width  = 24
        height = 6
        properties = jsonencode({
          title  = "Database CPU"
          region = "us-east-1"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "payments-db", { stat = "Average" }],
          ]
        })
      },
    ]
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).widgets[0].properties.metrics[0][4].stat == "Average"
    error_message = "The trailing options object of a metric array should survive into the dashboard body untouched, since it cannot be expressed as an HCL type."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).widgets[0].properties.title == "Database CPU"
    error_message = "Widget properties should be embedded as JSON rather than as a quoted string."
  }
}

run "the_time_range_and_dashboard_variables_reach_the_body" {
  command = plan

  variables {
    dashboard_name  = "ranged"
    start           = "-PT12H"
    end             = "2026-09-30T00:00:00.000Z"
    period_override = "inherit"
    variables_json = jsonencode([
      {
        type         = "property"
        property     = "InstanceId"
        inputType    = "select"
        id           = "instance"
        label        = "Instance"
        visible      = true
        search       = "AWS/EC2 CPUUtilization"
        populateFrom = "InstanceId"
      },
    ])
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).start == "-PT12H"
    error_message = "start should reach the dashboard body under its own name."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).periodOverride == "inherit"
    error_message = "period_override should reach the dashboard body as AWS's camel-cased periodOverride key."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).variables[0].property == "InstanceId"
    error_message = "variables_json should be embedded as a JSON array rather than as a quoted string."
  }
}

run "readme_automatic_layout_example" {
  command = plan

  variables {
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

  assert {
    condition = [
      for widget in jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).widgets : [widget.x, widget.y]
      ] == [
      [0, 0],
      [12, 0],
      [0, 6],
    ]
    error_message = "The README's automatic-layout example should put the two half-width widgets side by side and the full-width widget on the row below."
  }
}

run "readme_pinned_layout_example" {
  command = plan

  variables {
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

  assert {
    condition = [
      for widget in jsondecode(aws_cloudwatch_dashboard.resource.dashboard_body).widgets : [widget.x, widget.y]
      ] == [
      [0, 0],
      [0, 2],
      [8, 2],
    ]
    error_message = "The README's pinned example should place every widget exactly where it was pinned."
  }
}
