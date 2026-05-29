data "aws_efs_file_system" "app_efs" {
  file_system_id = "fs-005d326a920e57a12"
}

# ── Mount Target AZ-a (usa UMA subnet da AZ-a) ───────────────────────────────
resource "aws_efs_mount_target" "az_a" {
  file_system_id  = data.aws_efs_file_system.app_efs.id
  subnet_id       = aws_subnet.private_backend_a.id
  security_groups = [aws_security_group.efs.id]
}

# ── Mount Target AZ-b ───────────────────────────────────────────────────────
resource "aws_efs_mount_target" "az_b" {
  file_system_id  = data.aws_efs_file_system.app_efs.id
  subnet_id       = aws_subnet.private_backend_b.id
  security_groups = [aws_security_group.efs.id]
}