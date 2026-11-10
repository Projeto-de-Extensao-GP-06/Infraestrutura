# -- CloudWatch Dashboards --------------------------------------------------
# Arquivo independente: pode ser apagado sem afetar o restante da infra.

resource "aws_cloudwatch_dashboard" "sgpj" {
  dashboard_name = "SGPJ-Infraestrutura"

  dashboard_body = jsonencode({
    widgets = [

      # -- Secao: EC2 CPU ----------------------------------------------------
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "## EC2 -- CPU Utilization"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 24
        height = 6
        properties = {
          title   = "CPU Utilization -- todas as instancias (%)"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 60
          stat    = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", module.compute.app_a_id, { label = "app-a" }],
            ["AWS/EC2", "CPUUtilization", "InstanceId", module.compute.app_b_id, { label = "app-b" }],
            ["AWS/EC2", "CPUUtilization", "InstanceId", module.compute.backend_a_id, { label = "backend-a" }],
            ["AWS/EC2", "CPUUtilization", "InstanceId", module.compute.backend_b_id, { label = "backend-b" }],
            ["AWS/EC2", "CPUUtilization", "InstanceId", module.compute.db_id, { label = "db (MySQL)" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },

      # -- Secao: EC2 Rede ---------------------------------------------------
      {
        type   = "text"
        x      = 0
        y      = 7
        width  = 24
        height = 1
        properties = {
          markdown = "## EC2 -- Network"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title   = "Network In (bytes)"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", module.compute.app_a_id, { label = "app-a" }],
            ["AWS/EC2", "NetworkIn", "InstanceId", module.compute.app_b_id, { label = "app-b" }],
            ["AWS/EC2", "NetworkIn", "InstanceId", module.compute.backend_a_id, { label = "backend-a" }],
            ["AWS/EC2", "NetworkIn", "InstanceId", module.compute.backend_b_id, { label = "backend-b" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title   = "Network Out (bytes)"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/EC2", "NetworkOut", "InstanceId", module.compute.app_a_id, { label = "app-a" }],
            ["AWS/EC2", "NetworkOut", "InstanceId", module.compute.app_b_id, { label = "app-b" }],
            ["AWS/EC2", "NetworkOut", "InstanceId", module.compute.backend_a_id, { label = "backend-a" }],
            ["AWS/EC2", "NetworkOut", "InstanceId", module.compute.backend_b_id, { label = "backend-b" }],
          ]
        }
      },

      # -- Secao: EC2 Status -------------------------------------------------
      {
        type   = "text"
        x      = 0
        y      = 14
        width  = 24
        height = 1
        properties = {
          markdown = "## EC2 -- Status Check"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 15
        width  = 24
        height = 6
        properties = {
          title   = "Status Check Failed (0 = OK, 1 = falha)"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 60
          stat    = "Maximum"
          metrics = [
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", module.compute.app_a_id, { label = "app-a" }],
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", module.compute.app_b_id, { label = "app-b" }],
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", module.compute.backend_a_id, { label = "backend-a" }],
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", module.compute.backend_b_id, { label = "backend-b" }],
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", module.compute.db_id, { label = "db (MySQL)" }]
          ]
          yAxis = { left = { min = 0, max = 2 } }
        }
      },

      # -- Secao: EFS --------------------------------------------------------
      {
        type   = "text"
        x      = 0
        y      = 34
        width  = 24
        height = 1
        properties = {
          markdown = "## EFS -- ${aws_efs_file_system.app_efs.id}"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 35
        width  = 12
        height = 6
        properties = {
          title  = "Data Read I/O (bytes)"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/EFS", "DataReadIOBytes", "FileSystemId", aws_efs_file_system.app_efs.id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 35
        width  = 12
        height = 6
        properties = {
          title  = "Data Write I/O (bytes)"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/EFS", "DataWriteIOBytes", "FileSystemId", aws_efs_file_system.app_efs.id]
          ]
        }
      },

      # -- Secao: ALB --------------------------------------------------------
      {
        type   = "text"
        x      = 0
        y      = 41
        width  = 24
        height = 1
        properties = {
          markdown = "## ALB -- alb-app"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 42
        width  = 8
        height = 6
        properties = {
          title  = "Request Count"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", module.compute.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 42
        width  = 8
        height = 6
        properties = {
          title  = "Target Response Time (segundos)"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.compute.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 42
        width  = 8
        height = 6
        properties = {
          title  = "Active Connections"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "ActiveConnectionCount", "LoadBalancer", module.compute.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 48
        width  = 8
        height = 6
        properties = {
          title   = "HTTP 2xx / 4xx / 5xx (Target)"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", module.compute.alb_arn_suffix, { label = "2xx", color = "#2ca02c" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", module.compute.alb_arn_suffix, { label = "4xx", color = "#ff7f0e" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", module.compute.alb_arn_suffix, { label = "5xx", color = "#d62728" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 48
        width  = 8
        height = 6
        properties = {
          title  = "HTTP 5xx -- ALB proprio"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", module.compute.alb_arn_suffix, { color = "#d62728" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 48
        width  = 8
        height = 6
        properties = {
          title  = "Healthy / Unhealthy Hosts"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", module.compute.target_group_arn_suffix, "LoadBalancer", module.compute.alb_arn_suffix, { label = "Healthy", color = "#2ca02c" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", module.compute.target_group_arn_suffix, "LoadBalancer", module.compute.alb_arn_suffix, { label = "Unhealthy", color = "#d62728" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
    ]
  })
}
