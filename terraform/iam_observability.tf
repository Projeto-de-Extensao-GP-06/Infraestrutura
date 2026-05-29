data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "observability_ec2_role" {
  count = var.enable_observability_iam ? 1 : 0

  name               = "sgpj-observability-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = { Name = "sgpj-observability-ec2-role" }
}

data "aws_iam_policy_document" "cloudwatch_exporter_read" {
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "tag:GetResources",
      "ec2:DescribeInstances",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeTargetGroups",
      "rds:DescribeDBInstances",
      "elasticfilesystem:DescribeFileSystems"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cloudwatch_exporter_read" {
  count = var.enable_observability_iam ? 1 : 0

  name   = "sgpj-cloudwatch-exporter-read"
  role   = aws_iam_role.observability_ec2_role[0].id
  policy = data.aws_iam_policy_document.cloudwatch_exporter_read.json
}

resource "aws_iam_instance_profile" "observability_ec2_profile" {
  count = var.enable_observability_iam ? 1 : 0

  name = "sgpj-observability-ec2-profile"
  role = aws_iam_role.observability_ec2_role[0].name
}
