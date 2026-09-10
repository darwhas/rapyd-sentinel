output "cluster_role_arn" {
  # depends_on guarantees policies are attached before the
  # ARN is consumed by the EKS module.
  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
  value      = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
  value = aws_iam_role.node.arn
}
