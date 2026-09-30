variable "dashboard_name" {
  default     = null
  description = "Name of the dashboard, unique within the account — dashboards are global rather than per-region, so a name is not free to repeat across regions the way most resource names are. AWS accepts only letters, digits, hyphens, and underscores, which means a name containing a space is rejected outright. If null, a unique name is generated, though a descriptive name is worth setting here since it is what an operator scans for in the console's dashboard list."

  validation {
    condition     = var.dashboard_name == null || can(regex("^[A-Za-z0-9_-]{1,255}$", var.dashboard_name))
    error_message = "dashboard_name may contain only letters, digits, hyphens, and underscores, and may be at most 255 characters long."
  }
}

variable "widgets" {
  default     = []
  description = "Widgets to place on the dashboard, in the order they should be laid out. Each entry gives its CloudWatch widget type, its size in grid units, and its properties as a JSON string — properties is carried through verbatim, so metric arrays, metric math, search expressions, annotations, and log queries are written exactly as AWS's dashboard body reference defines them. Leave x and y unset to have the module compute the position, or set both to pin the widget outside the automatic flow. An ARN or ID sourced from another module is safe to embed in properties: it is a value inside the JSON rather than a key the plan depends on. A dashboard holds at most 500 widgets."
  type = list(object({
    type       = string
    properties = string
    width      = optional(number, 6)
    height     = optional(number, 6)
    x          = optional(number)
    y          = optional(number)
  }))

  validation {
    condition     = length(var.widgets) <= 500
    error_message = "A dashboard holds at most 500 widgets."
  }

  validation {
    condition     = alltrue([for widget in var.widgets : contains(["metric", "text", "log", "alarm", "explorer", "chart", "custom"], widget.type)])
    error_message = "Each widget type must be one of 'metric', 'text', 'log', 'alarm', 'explorer', 'chart', or 'custom'."
  }

  validation {
    condition     = alltrue([for widget in var.widgets : can(jsondecode(widget.properties))])
    error_message = "Each widget's properties must be a JSON document — build it with jsonencode rather than assembling a string by hand."
  }

  validation {
    condition     = alltrue([for widget in var.widgets : widget.width >= 1 && widget.width <= 24])
    error_message = "Each widget's width must be between 1 and 24 grid units, the full width of the dashboard grid."
  }

  validation {
    condition     = alltrue([for widget in var.widgets : widget.height >= 1 && widget.height <= 1000])
    error_message = "Each widget's height must be between 1 and 1000 grid units."
  }

  validation {
    condition     = alltrue([for widget in var.widgets : (widget.x == null) == (widget.y == null)])
    error_message = "A widget must pin both x and y or neither — AWS requires each coordinate whenever the other is given, and a half-pinned widget has no defined position."
  }

  validation {
    condition     = alltrue([for widget in var.widgets : widget.x == null || (widget.x >= 0 && widget.x <= 23)])
    error_message = "A pinned x must be between 0 and 23, the leftmost and rightmost columns of the 24-column grid."
  }

  validation {
    condition     = alltrue([for widget in var.widgets : widget.y == null || widget.y >= 0])
    error_message = "A pinned y must be 0 or greater."
  }

  validation {
    condition = alltrue([
      for index, widget in var.widgets :
      widget.x != null || (sum(concat([0], [for position, other in var.widgets : other.width if position < index && other.x == null])) % 24) + widget.width <= 24
    ])
    error_message = "Automatic layout advances a cursor across the 24-column grid by cumulative width, so every row it completes has to fill exactly before the next one opens. At least one widget would cross the right edge instead: adjust the widths so each completed row sums to 24, or pin x and y on that widget to place it outside the flow."
  }
}

variable "variables_json" {
  default     = null
  description = "Dashboard variables as a JSON array matching AWS's own dashboard variable schema, which lets a viewer switch one dashboard between resources rather than duplicating it per resource. Taken as JSON for the same reason widget properties are — see the module's README."
}

variable "start" {
  default     = null
  description = "Time range the dashboard opens on, as an ISO 8601 duration counted back from now (for example '-PT3H' for the last three hours) or an absolute ISO 8601 timestamp. If null, the dashboard opens on whatever range the viewer last used."
}

variable "end" {
  default     = null
  description = "End of an absolute time range, as an ISO 8601 timestamp. Only meaningful alongside an absolute start, and pinning a dashboard to a fixed window in the past is rarely what an operational dashboard wants."
}

variable "period_override" {
  default     = null
  description = "Whether each widget keeps its own period ('inherit') or adopts the period implied by the dashboard's time range ('auto'). 'inherit' is worth setting when a widget's period was chosen deliberately to match how the metric is published, since 'auto' will otherwise coarsen it as the viewer zooms out."
}
