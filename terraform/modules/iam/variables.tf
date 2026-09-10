variable "cluster_name" {
  description = "Cluster name; must start with eks- so all role names respect the approved prefix"
  type        = string

  validation {
    condition     = startswith(var.cluster_name, "eks-")
    error_message = "cluster_name must start with the approved 'eks-' prefix."
  }
}
